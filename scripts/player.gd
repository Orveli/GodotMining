extends RefCounted

# Pelaajan koko pikseleinä
const WIDTH := 4
const HEIGHT := 7

# Fysiikka
const GRAVITY := 0.35
const JUMP_VELOCITY := -3.5
const MOVE_SPEED := 1.2
const MAX_FALL_SPEED := 5.0
const WATER_GRAVITY := 0.08
const WATER_MOVE_SPEED := 0.8
const WATER_JUMP_VELOCITY := -1.5
const WATER_MAX_FALL_SPEED := 1.0
const FRICTION := 0.75

# Kiinteät materiaalit joihin törmätään
const SOLID_MATERIALS: Array[int] = [1, 3, 4, 8, 9]  # SAND, STONE, WOOD, ASH, WOOD_FALLING

var position: Vector2 = Vector2(208.0, 50.0)  # Aloituspaikka keskellä, ylhäällä
var velocity: Vector2 = Vector2.ZERO
var on_ground := false
var in_water := false
var facing_right := true

# Värit pelaajaspritelle (yksinkertainen pikseligrafiiikka)
# 0 = läpinäkyvä, 1 = vartalo, 2 = pää, 3 = jalat
const SPRITE: Array[Array] = [
	[0, 2, 2, 0],  # Pää ylärivi
	[0, 2, 2, 0],  # Pää alarivi
	[1, 1, 1, 1],  # Hartiat
	[0, 1, 1, 0],  # Vartalo
	[0, 1, 1, 0],  # Vartalo
	[0, 3, 3, 0],  # Jalat ylä
	[3, 0, 0, 3],  # Jalat ala (levällään)
]

const SPRITE_COLORS: Array[Color] = [
	Color(0, 0, 0, 0),          # 0 = läpinäkyvä
	Color(0.2, 0.6, 0.9, 1.0),  # 1 = vartalo (sininen)
	Color(0.9, 0.75, 0.55, 1.0),# 2 = pää (iho)
	Color(0.3, 0.2, 0.5, 1.0),  # 3 = jalat (tumma)
]


func update(grid: PackedByteArray, w: int, h: int) -> void:
	_handle_movement()
	_apply_physics(grid, w, h)


func _handle_movement() -> void:
	# Vaakasuuntainen liike
	var move_dir := 0.0
	if Input.is_key_pressed(KEY_A):
		move_dir -= 1.0
		facing_right = false
	if Input.is_key_pressed(KEY_D):
		move_dir += 1.0
		facing_right = true

	var speed := WATER_MOVE_SPEED if in_water else MOVE_SPEED
	if move_dir != 0.0:
		velocity.x = move_dir * speed
	else:
		velocity.x *= FRICTION

	# Hyppy
	if Input.is_key_pressed(KEY_W):
		if on_ground:
			velocity.y = JUMP_VELOCITY
		elif in_water:
			velocity.y = WATER_JUMP_VELOCITY


func _apply_physics(grid: PackedByteArray, w: int, h: int) -> void:
	# Painovoima
	var grav := WATER_GRAVITY if in_water else GRAVITY
	var max_fall := WATER_MAX_FALL_SPEED if in_water else MAX_FALL_SPEED
	velocity.y = minf(velocity.y + grav, max_fall)

	# Liiku X-suunnassa ja tarkista törmäys
	var new_x := position.x + velocity.x
	if not _check_collision(new_x, position.y, grid, w, h):
		position.x = new_x
	else:
		# Kokeile kiivetä 1-2 pikseliä ylös (portaat)
		var climbed := false
		for step in range(1, 3):
			if not _check_collision(new_x, position.y - float(step), grid, w, h):
				position.x = new_x
				position.y -= float(step)
				climbed = true
				break
		if not climbed:
			velocity.x = 0.0

	# Liiku Y-suunnassa ja tarkista törmäys
	var new_y := position.y + velocity.y
	if not _check_collision(position.x, new_y, grid, w, h):
		position.y = new_y
		on_ground = false
	else:
		if velocity.y > 0.0:
			# Laskeutuminen — etsi tarkka paikka
			var step := 0.5
			var test_y := position.y
			while test_y < new_y:
				test_y += step
				if _check_collision(position.x, test_y, grid, w, h):
					position.y = test_y - step
					on_ground = true
					break
		velocity.y = 0.0

	# Tarkista onko vedessä
	in_water = _check_material_at(position.x, position.y, grid, w, h, 2)  # MAT_WATER = 2

	# Rajaa ruudukon sisälle
	position.x = clampf(position.x, 1.0, float(w - WIDTH - 1))
	position.y = clampf(position.y, 1.0, float(h - HEIGHT - 1))


func _check_collision(px: float, py: float, grid: PackedByteArray, w: int, h: int) -> bool:
	# Tarkista pelaajan jokainen pikseli törmäyksille
	var left := int(px)
	var top := int(py)
	for dy in HEIGHT:
		var gy := top + dy
		if gy < 0 or gy >= h:
			return true
		for dx in WIDTH:
			var gx := left + dx
			if gx < 0 or gx >= w:
				return true
			# Tarkista vain sprite-pikselit (ei läpinäkyviä)
			if SPRITE[dy][dx] == 0:
				continue
			var mat: int = grid[gy * w + gx]
			if mat in SOLID_MATERIALS:
				return true
	return false


func _check_material_at(px: float, py: float, grid: PackedByteArray, w: int, h: int, mat_id: int) -> bool:
	# Tarkista onko pelaajan keskellä tiettyä materiaalia
	var cx := int(px) + WIDTH / 2
	var cy := int(py) + HEIGHT / 2
	if cx < 0 or cx >= w or cy < 0 or cy >= h:
		return false
	return grid[cy * w + cx] == mat_id


func get_grid_pos() -> Vector2i:
	return Vector2i(int(position.x), int(position.y))


func spawn_at_surface(grid: PackedByteArray, w: int, h: int) -> void:
	# Etsi vapaa paikka maailman yläosasta
	var spawn_x := w / 2
	for y in range(5, h - HEIGHT):
		if not _check_collision(float(spawn_x), float(y), grid, w, h):
			# Tarkista onko alhaalla maata (ei tiputa tyhjyyteen)
			var found_ground := false
			for check_y in range(y + 1, mini(y + 50, h)):
				if _check_collision(float(spawn_x), float(check_y), grid, w, h):
					found_ground = true
					break
			if found_ground:
				position = Vector2(float(spawn_x), float(y))
				return
	# Fallback
	position = Vector2(float(spawn_x), 50.0)
