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

# Jetpack-fysiikka
const JETPACK_THRUST := 0.18        # kiihtyvyys per frame (W/S/A/D)
const JETPACK_HOVER_GRAVITY := 0.03  # erittäin kevyt leijunta alas
const JETPACK_DRAG := 0.97          # ilmanvastus per frame — momentum säilyy
const JETPACK_MAX_SPEED := 4.0      # max nopeus kaikissa suunnissa

# Kiinteät materiaalit joihin törmätään
const SOLID_MATERIALS: Array[int] = [3]  # STONE

# Pehmeät materiaalit (pintana toimivat, ei blokkaavat sivuilta)
const SOFT_MATERIALS: Array[int] = [1, 4, 6, 7, 8, 9]  # SAND, WOOD, OIL, STEAM, ASH, WOOD_FALLING (ei vettä)

var position: Vector2 = Vector2(208.0, 50.0)  # Aloituspaikka keskellä, ylhäällä
var velocity: Vector2 = Vector2.ZERO
var on_ground := false
var in_water := false
var in_material := false
var facing_right := true
var drop_through := false  # Putoaminen pehmeän materiaalin läpi
var diving := false  # Sukellustila — pelaaja uppoaa pohjaan
var jetpack_active := false  # Jetpack päällä/pois
var _space_was_pressed := false  # Rising-edge detektio space-näppäimelle

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
	# Space-toggle jetpackille (rising-edge detektio)
	var space_now := Input.is_key_pressed(KEY_SPACE)
	if space_now and not _space_was_pressed:
		jetpack_active = !jetpack_active
	_space_was_pressed = space_now

	if jetpack_active:
		# Jetpack: kiihtyvyyspohjainen ohjaus — momentum säilyy, drag hidastaa hitaasti
		if Input.is_key_pressed(KEY_W):
			velocity.y -= JETPACK_THRUST
		# S ei thrustaa — pelaaja vain tippuu hoverin verran
		if Input.is_key_pressed(KEY_A):
			velocity.x -= JETPACK_THRUST / 3.0
			facing_right = false
		if Input.is_key_pressed(KEY_D):
			velocity.x += JETPACK_THRUST / 3.0
			facing_right = true

		# Kevyt ilmanvastus — momentum kantaa mutta ei ikuisesti
		velocity.x *= JETPACK_DRAG
		velocity.y *= JETPACK_DRAG

		velocity.x = clampf(velocity.x, -JETPACK_MAX_SPEED, JETPACK_MAX_SPEED)
		velocity.y = clampf(velocity.y, -JETPACK_MAX_SPEED, JETPACK_MAX_SPEED)
		return

	# Normaali ohjaus (jetpack pois)
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

	# W: hyppy maalla, lopeta sukellus vedessä
	if Input.is_key_pressed(KEY_W):
		if on_ground:
			velocity.y = JUMP_VELOCITY
		elif diving:
			diving = false
		elif in_material:
			velocity.y = WATER_JUMP_VELOCITY

	# S: sukella vedessä, pudota pehmeän läpi maalla
	if Input.is_key_pressed(KEY_S):
		if in_water:
			diving = true
		elif on_ground:
			drop_through = true


func _count_submerged_rows(px: float, py: float, grid: PackedByteArray, w: int, h: int) -> int:
	# Laskee kuinka monta sprite-riviä on veden sisällä
	var count := 0
	var left := int(px)
	var top := int(py)
	for dy in HEIGHT:
		var gy := top + dy
		if gy < 0 or gy >= h:
			continue
		for dx in WIDTH:
			if SPRITE[dy][dx] == 0:
				continue
			var gx := left + dx
			if gx < 0 or gx >= w:
				continue
			if grid[gy * w + gx] == 2:  # WATER
				count += 1
				break  # Laske rivi vain kerran
	return count


func _check_head_in_water(px: float, py: float, grid: PackedByteArray, w: int, h: int) -> bool:
	# Tarkista onko pää (rivit 0-1) veden sisällä
	var left := int(px)
	var top := int(py)
	for dy in 2:
		var gy := top + dy
		if gy < 0 or gy >= h:
			continue
		for dx in WIDTH:
			if SPRITE[dy][dx] == 0:
				continue
			var gx := left + dx
			if gx < 0 or gx >= w:
				continue
			if grid[gy * w + gx] == 2:
				return true
	return false


func _apply_physics(grid: PackedByteArray, w: int, h: int) -> void:
	# Painovoima + kelluntafysiikka
	var submerged_rows := _count_submerged_rows(position.x, position.y, grid, w, h)
	if submerged_rows > 0 and not diving:
		var head_wet := _check_head_in_water(position.x, position.y, grid, w, h)
		if head_wet:
			# Pää vedessä — nouse ylöspäin, vahva vaimennus
			velocity.y = velocity.y * 0.35 - 0.25
		else:
			# Pää pinnalla, vartalo vedessä — pysähdy tähän tasoon
			velocity.y *= 0.35
		velocity.y = clampf(velocity.y, -WATER_MAX_FALL_SPEED, WATER_MAX_FALL_SPEED)
	elif submerged_rows > 0 and diving:
		# Sukellus — laske hitaasti pohjaan
		velocity.y = minf(velocity.y + WATER_GRAVITY, WATER_MAX_FALL_SPEED)
	elif in_material:
		velocity.y = minf(velocity.y + WATER_GRAVITY, WATER_MAX_FALL_SPEED)
	elif jetpack_active:
		# Jetpack: erittäin kevyt leijunta alas ilman thrusttia
		velocity.y = minf(velocity.y + JETPACK_HOVER_GRAVITY, JETPACK_MAX_SPEED)
	else:
		# Nollaa sukellustila kun poistutaan vedestä
		diving = false
		velocity.y = minf(velocity.y + GRAVITY, MAX_FALL_SPEED)

	# Liiku X-suunnassa ja tarkista törmäys (pehmeät eivät blokkaa sivusuunnassa)
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
	# Pehmeä törmäys alaspäin kun ei pudota tahallaan
	var soft_down := not drop_through
	if not _check_collision(position.x, new_y, grid, w, h, velocity.y >= 0.0 and soft_down):
		position.y = new_y
		on_ground = false
	else:
		if velocity.y > 0.0:
			# Laskeutuminen — etsi tarkka paikka
			var step := 0.5
			var test_y := position.y
			var use_soft := not drop_through
			while test_y < new_y:
				test_y += step
				if _check_collision(position.x, test_y, grid, w, h, use_soft):
					position.y = test_y - step
					on_ground = true
					break
		velocity.y = 0.0

	# Nollaa drop_through kun jalat eivät enää kosketa pehmeää materiaalia
	if drop_through and not _check_feet_on_soft(position.x, position.y, grid, w, h):
		drop_through = false

	# Päivitä vedessä-tila kelluntarivejen perusteella
	in_water = submerged_rows > 0

	# Tarkista onko pelaaja materiaalin sisällä (voi uida ylöspäin)
	in_material = _check_any_material(position.x, position.y, grid, w, h)

	# Rajaa ruudukon sisälle
	position.x = clampf(position.x, 1.0, float(w - WIDTH - 1))
	position.y = clampf(position.y, 1.0, float(h - HEIGHT - 1))


func _check_collision(px: float, py: float, grid: PackedByteArray, w: int, h: int, include_soft: bool = false) -> bool:
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
			if include_soft and mat in SOFT_MATERIALS:
				return true
	return false


func _check_feet_on_soft(px: float, py: float, grid: PackedByteArray, w: int, h: int) -> bool:
	# Tarkista onko jalkojen alla pehmeää materiaalia (1 pikseli jalkojen alla)
	var bottom_y := int(py) + HEIGHT
	if bottom_y >= h:
		return false
	for dx in WIDTH:
		if SPRITE[HEIGHT - 1][dx] == 0:
			continue
		var gx := int(px) + dx
		if gx < 0 or gx >= w:
			continue
		var mat: int = grid[bottom_y * w + gx]
		if mat in SOFT_MATERIALS:
			return true
	return false


func _check_material_at(px: float, py: float, grid: PackedByteArray, w: int, h: int, mat_id: int) -> bool:
	# Tarkista onko pelaajan keskellä tiettyä materiaalia
	var cx := int(px) + WIDTH / 2
	var cy := int(py) + HEIGHT / 2
	if cx < 0 or cx >= w or cy < 0 or cy >= h:
		return false
	return grid[cy * w + cx] == mat_id


func _check_any_material(px: float, py: float, grid: PackedByteArray, w: int, h: int) -> bool:
	# Tarkista onko pelaajan keskellä hiekkaa, vettä tai öljyä (uintimateriaali)
	var cx := int(px) + WIDTH / 2
	var cy := int(py) + HEIGHT / 2
	if cx < 0 or cx >= w or cy < 0 or cy >= h:
		return false
	var mat := grid[cy * w + cx]
	return mat == 1 or mat == 2 or mat == 6  # SAND, WATER, OIL


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
