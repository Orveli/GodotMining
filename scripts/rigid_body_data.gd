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

# Johdetut (lasketaan tarvittaessa)
var bbox: Rect2i = Rect2i()

const SLEEP_THRESHOLD_FRAMES := 90  # Pidempi odotus ennen nukahtamista
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
	var result: Array[Vector2i] = []
	var cos_a := cos(angle)
	var sin_a := sin(angle)

	for lp in local_pixels:
		# Kierrä lokaalipikseli painopisteen ympäri
		var rx := lp.x * cos_a - lp.y * sin_a
		var ry := lp.x * sin_a + lp.y * cos_a
		# Lisää painopisteen sijainti
		result.append(Vector2i(
			roundi(position.x + rx),
			roundi(position.y + ry)
		))

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
