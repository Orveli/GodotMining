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

# Rotaatiocache — lasketaan uudelleen vain kun kulma muuttuu
var _rot_cache: Array[Vector2i] = []
var _rot_angle: float = INF

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


# Palauta pikselien maailmakoordinaatit huomioiden sijainti ja kiertymä
func get_world_pixels() -> Array[Vector2i]:
	_ensure_rot_cache()
	var result: Array[Vector2i] = []
	result.resize(_rot_cache.size())
	var px := roundi(position.x)
	var py := roundi(position.y)
	for i in _rot_cache.size():
		result[i] = Vector2i(_rot_cache[i].x + px, _rot_cache[i].y + py)
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


func _ensure_rot_cache() -> void:
	if absf(_rot_angle - angle) < 0.0005 and not _rot_cache.is_empty():
		return
	var cos_a := cos(angle)
	var sin_a := sin(angle)
	_rot_cache.resize(local_pixels.size())
	for i in local_pixels.size():
		var lp := local_pixels[i]
		_rot_cache[i] = Vector2i(
			roundi(lp.x * cos_a - lp.y * sin_a),
			roundi(lp.x * sin_a + lp.y * cos_a)
		)
	_rot_angle = angle


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
		return

	var min_p := local_pixels[0]
	var max_p := local_pixels[0]
	for lp in local_pixels:
		min_p.x = mini(min_p.x, lp.x)
		min_p.y = mini(min_p.y, lp.y)
		max_p.x = maxi(max_p.x, lp.x)
		max_p.y = maxi(max_p.y, lp.y)

	bbox = Rect2i(min_p, max_p - min_p + Vector2i.ONE)
	_rot_angle = INF  # Pakota rotaatiocachen uudelleenlaskenta
