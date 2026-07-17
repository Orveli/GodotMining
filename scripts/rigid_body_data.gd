# Yksittäisen rigid body -kappaleen tiedot
class_name RigidBodyData

# Identiteetti
var body_id: int = 0                    # 1-65535, vastaa body_id-kenttää gridissä
var material: int = 3                   # Oletuksena MAT_STONE

# Muoto — pikselit suhteessa painopisteeseen (lokaalikoordinaatit)
var local_pixels: Array[Vector2i] = []

# Fysiikka
var position: Vector2 = Vector2.ZERO    # Painopisteen sijainti maailmassa (float, subpixel)
var velocity: Vector2 = Vector2.ZERO    # Nopeus pikseleinä/frame
var angle: float = 0.0                  # Kiertymä radiaaneissa
var angular_velocity: float = 0.0       # Kiertymänopeus rad/frame
var mass: float = 0.0                   # = local_pixels.size()
var inertia: float = 1.0                # Hitausmomentti (Σ etäisyys² painopisteestä)

# Väri-siemenet jokaiselle pikselille (sama järjestys kuin local_pixels)
var pixel_seeds: PackedByteArray = PackedByteArray()

# Tila
var is_sleeping: bool = false
var sleep_counter: int = 0
var is_static: bool = false

# --- Rotaatiocache (flat) — kierretyt offsetit suhteessa painopisteeseen ---
# Lasketaan uudelleen vain kun kulma muuttuu. rot_ox/rot_oy ovat rinnakkaiset
# local_pixels-listan kanssa. Maailmapikseli = offset + pyöristetty positio.
var rot_ox: PackedInt32Array = PackedInt32Array()
var rot_oy: PackedInt32Array = PackedInt32Array()
var rot_min_x: int = 0                  # kierrettyjen offsettien AABB (leveys/pohjatarkistus)
var rot_max_x: int = 0
var rot_min_y: int = 0
var rot_max_y: int = 0
var _rot_angle: float = INF

# --- Aukoton "täytetty muoto" (flat) — offsetit + lähde-indeksi ---
# filled_src[k] = lähde local-pikselin indeksi, tai -1 = aukontäyttö.
# Sidottu rot-cachen referenssikulmaan (_rot_angle) — EI current angleen — jotta
# täytetty muoto on aina yhtenevä sen rot-cachen kanssa josta se johdetaan.
# (Törmäyskoodi voi rakentaa rot-cachen uudelleen erase/write-välissä.)
var filled_ox: PackedInt32Array = PackedInt32Array()
var filled_oy: PackedInt32Array = PackedInt32Array()
var filled_src: PackedInt32Array = PackedInt32Array()
var _filled_rot_angle: float = INF

# --- Pohjapinta (flat) — tipping-momenttia varten ---
# Offsetit joiden alla (y+1) ei ole kappaleen omaa pikseliä.
# Sidottu rot-cachen referenssikulmaan (kuten filled).
var bottom_ox: PackedInt32Array = PackedInt32Array()
var bottom_oy: PackedInt32Array = PackedInt32Array()
var _bottom_rot_angle: float = INF

# Johdetut (lasketaan tarvittaessa)
var bbox: Rect2i = Rect2i()

const SLEEP_THRESHOLD_FRAMES := 30  # Nopeampi nukahtaminen suorituskyvyn parantamiseksi
const MIN_VELOCITY := 0.08
const MIN_ANGULAR_VELOCITY := 0.001


# Laske painopiste ja muunna pikselit lokaalikoordinaateiksi
func calculate_from_world_pixels(world_pixels: Array[Vector2i], seeds: PackedByteArray) -> void:
	# Laske painopiste (center of mass)
	var sum := Vector2.ZERO
	for p in world_pixels:
		sum += Vector2(p)
	position = sum / float(world_pixels.size())

	# Muunna lokaalikoordinaateiksi
	local_pixels.clear()
	pixel_seeds = seeds.duplicate()
	for p in world_pixels:
		local_pixels.append(Vector2i(
			p.x - roundi(position.x),
			p.y - roundi(position.y)
		))

	mass = float(local_pixels.size())
	_calculate_inertia()
	_update_bbox()


# Palauta pikselien maailmakoordinaatit huomioiden sijainti ja kiertymä.
# HUOM: allokoi uuden taulukon — sisäiset kuumat polut iteroivat rot_ox/rot_oy
# suoraan. Tämä on tarjolla ulkoisille kutsujille (testit, _split_if_needed).
func get_world_pixels() -> Array[Vector2i]:
	_ensure_rot_cache()
	var n := rot_ox.size()
	var result: Array[Vector2i] = []
	result.resize(n)
	var px := roundi(position.x)
	var py := roundi(position.y)
	for i in n:
		result[i] = Vector2i(rot_ox[i] + px, rot_oy[i] + py)
	return result


# Päivitä nukahtamistila
func update_sleep() -> void:
	if velocity.length() < MIN_VELOCITY and absf(angular_velocity) < MIN_ANGULAR_VELOCITY:
		sleep_counter += 1
		if sleep_counter >= SLEEP_THRESHOLD_FRAMES:
			is_sleeping = true
			velocity = Vector2.ZERO
			angular_velocity = 0.0
			# Kohdista lähimpään kokonaislukusijaintiin (säilytä kulma)
			position = Vector2(roundi(position.x), roundi(position.y))
	else:
		sleep_counter = 0
		is_sleeping = false


# Herätä kappale (esim. törmäys tai tuho)
func wake_up() -> void:
	is_sleeping = false
	sleep_counter = 0


# Poista pikseli kappaleesta (tuho/leikkaus)
# Palauttaa true jos kappale on vielä olemassa
func remove_pixel(local_index: int) -> bool:
	if local_index < 0 or local_index >= local_pixels.size():
		return local_pixels.size() > 0

	local_pixels.remove_at(local_index)
	if local_index < pixel_seeds.size():
		pixel_seeds.remove_at(local_index)

	if local_pixels.is_empty():
		return false

	# Laske painopiste uudelleen
	_recalculate_center_of_mass()
	mass = float(local_pixels.size())
	_calculate_inertia()
	_update_bbox()
	return true


# Rakenna kierretyt offsetit + niiden AABB. Ainoa cache jota get_world_pixels ja
# törmäystarkistukset tarvitsevat — pidetään halpana.
func _ensure_rot_cache() -> void:
	if absf(_rot_angle - angle) < 0.0005 and not rot_ox.is_empty():
		return
	var n := local_pixels.size()
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	rot_ox.resize(n)
	rot_oy.resize(n)
	var mnx := 0x7FFFFFFF
	var mxx := -0x7FFFFFFF
	var mny := 0x7FFFFFFF
	var mxy := -0x7FFFFFFF
	for i in n:
		var lp := local_pixels[i]
		var ox := roundi(lp.x * cos_a - lp.y * sin_a)
		var oy := roundi(lp.x * sin_a + lp.y * cos_a)
		rot_ox[i] = ox
		rot_oy[i] = oy
		if ox < mnx: mnx = ox
		if ox > mxx: mxx = ox
		if oy < mny: mny = oy
		if oy > mxy: mxy = oy
	if n == 0:
		mnx = 0; mxx = 0; mny = 0; mxy = 0
	rot_min_x = mnx
	rot_max_x = mxx
	rot_min_y = mny
	rot_max_y = mxy
	_rot_angle = angle


# Rakenna aukoton täytetty muoto (offsetit + lähde-indeksi). Vastaa aiempaa
# _get_filled_world_pixels()-logiikkaa mutta position-riippumattomasti ja flat-
# rakenteina. Käytetään flat bittikarttaa (src_map) Dictionaryn sijaan.
func _ensure_filled_cache() -> void:
	_ensure_rot_cache()
	# Rakenna uudelleen vain jos rot-cache on muuttunut (tarkka float-vertailu:
	# molemmat pitävät saman kopioidun kulma-arvon).
	if _filled_rot_angle == _rot_angle and not filled_ox.is_empty():
		return
	filled_ox.clear()
	filled_oy.clear()
	filled_src.clear()
	var n := local_pixels.size()
	if n == 0:
		_filled_rot_angle = _rot_angle
		return

	var min_x := rot_min_x
	var min_y := rot_min_y
	var flat_w := rot_max_x - min_x + 1
	var flat_h := rot_max_y - min_y + 1

	# src_map: offset → slotti filled-taulukoissa, -1 = tyhjä
	var src_map := PackedInt32Array()
	src_map.resize(flat_w * flat_h)
	src_map.fill(-1)

	# Vaihe A: todelliset pikselit (viimeinen kirjoitus voittaa duplikaatti-offsetilla)
	for i in n:
		var fx := rot_ox[i] - min_x
		var fy := rot_oy[i] - min_y
		var idx := fy * flat_w + fx
		var slot := src_map[idx]
		if slot == -1:
			src_map[idx] = filled_ox.size()
			filled_ox.append(rot_ox[i])
			filled_oy.append(rot_oy[i])
			filled_src.append(i)
		else:
			filled_src[slot] = i

	# Local-pikseli → indeksi -kartta (naapurin kierretyn offsetin hakuun)
	var lminx := bbox.position.x
	var lminy := bbox.position.y
	var lw := bbox.size.x
	var lh := bbox.size.y
	var local_idx_map := PackedInt32Array()
	local_idx_map.resize(lw * lh)
	local_idx_map.fill(-1)
	for i in n:
		var lp := local_pixels[i]
		local_idx_map[(lp.y - lminy) * lw + (lp.x - lminx)] = i

	# Vaihe B: aukontäyttö vierekkäisten (oikea + ala) pikselien väliin
	for i in n:
		var lp := local_pixels[i]
		var rox_a := rot_ox[i]
		var roy_a := rot_oy[i]
		for d in 2:
			var nbx := lp.x + (1 if d == 0 else 0)
			var nby := lp.y + (0 if d == 0 else 1)
			if nbx < lminx or nbx >= lminx + lw or nby < lminy or nby >= lminy + lh:
				continue
			var j := local_idx_map[(nby - lminy) * lw + (nbx - lminx)]
			if j < 0:
				continue
			var rox_b := rot_ox[j]
			var roy_b := rot_oy[j]
			var mdist := absi(rox_b - rox_a) + absi(roy_b - roy_a)
			if mdist <= 1:
				continue
			# mid1 = (rox_a, roy_b)
			var m1 := (roy_b - min_y) * flat_w + (rox_a - min_x)
			if src_map[m1] == -1:
				src_map[m1] = filled_ox.size()
				filled_ox.append(rox_a)
				filled_oy.append(roy_b)
				filled_src.append(-1)
			# mid2 = (rox_b, roy_a), lisätään vain jos eri kuin mid1
			if not (rox_b == rox_a and roy_a == roy_b):
				var m2 := (roy_a - min_y) * flat_w + (rox_b - min_x)
				if src_map[m2] == -1:
					src_map[m2] = filled_ox.size()
					filled_ox.append(rox_b)
					filled_oy.append(roy_a)
					filled_src.append(-1)

	_filled_rot_angle = _rot_angle


# Rakenna pohjapinta: offsetit joiden alla (y+1) EI ole kappaleen omaa pikseliä.
# Vastaa aiempaa tipping-logiikan body_set-pohjaista pohjapikselien etsintää.
func _ensure_bottom_cache() -> void:
	_ensure_rot_cache()
	if _bottom_rot_angle == _rot_angle and not bottom_ox.is_empty():
		return
	bottom_ox.clear()
	bottom_oy.clear()
	var n := rot_ox.size()
	if n == 0:
		_bottom_rot_angle = _rot_angle
		return

	var min_x := rot_min_x
	var min_y := rot_min_y
	var flat_w := rot_max_x - min_x + 1
	var flat_h := rot_max_y - min_y + 1

	# Merkitse kaikki kappaleen offsetit läsnäoleviksi
	var present := PackedByteArray()
	present.resize(flat_w * flat_h)  # resize nollaa
	for i in n:
		present[(rot_oy[i] - min_y) * flat_w + (rot_ox[i] - min_x)] = 1

	for i in n:
		var below_y := rot_oy[i] + 1
		var has_below := false
		if below_y <= rot_max_y:
			has_below = present[(below_y - min_y) * flat_w + (rot_ox[i] - min_x)] == 1
		if not has_below:
			bottom_ox.append(rot_ox[i])
			bottom_oy.append(rot_oy[i])

	_bottom_rot_angle = _rot_angle


# Sisäinen: laske painopiste uudelleen lokaalipikseleiden perusteella
func _recalculate_center_of_mass() -> void:
	var sum := Vector2.ZERO
	for lp in local_pixels:
		sum += Vector2(lp)
	var local_com := sum / float(local_pixels.size())

	# Siirrä painopiste ja päivitä lokaalikoordinaatit
	var offset := Vector2i(roundi(local_com.x), roundi(local_com.y))
	if offset != Vector2i.ZERO:
		position += Vector2(offset)
		for i in local_pixels.size():
			local_pixels[i] -= offset


# Laske hitausmomentti (moment of inertia) pikselimassasta
func _calculate_inertia() -> void:
	inertia = 0.0
	for lp in local_pixels:
		inertia += float(lp.x * lp.x + lp.y * lp.y)
	inertia = maxf(inertia, 1.0)


func _update_bbox() -> void:
	if local_pixels.is_empty():
		bbox = Rect2i()
		_invalidate_shape_caches()
		return

	var min_p := local_pixels[0]
	var max_p := local_pixels[0]
	for lp in local_pixels:
		min_p.x = mini(min_p.x, lp.x)
		min_p.y = mini(min_p.y, lp.y)
		max_p.x = maxi(max_p.x, lp.x)
		max_p.y = maxi(max_p.y, lp.y)

	bbox = Rect2i(min_p, max_p - min_p + Vector2i.ONE)
	_invalidate_shape_caches()  # Pakota kaikkien cachejen uudelleenlaskenta


# Mitätöi kaikki muoto-cachet (kutsutaan kun local_pixels muuttuu)
func _invalidate_shape_caches() -> void:
	_rot_angle = INF
	_filled_rot_angle = INF
	_bottom_rot_angle = INF
