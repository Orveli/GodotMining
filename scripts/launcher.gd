# Hissi-linko: imee materiaalia kuilun kautta ylös, ampuu vaakasuoraan tykkiputkesta
class_name Launcher
extends Node2D

const SHAFT_WIDTH := 4         # Kuilun leveys pikseleinä
const BARREL_LENGTH := 6       # Tykkiputken pituus pikseleinä
const LAUNCH_SPEED := 120.0    # px/s perusnopeus
const LAUNCH_ANGLE_DEG := 0.0  # Vaakasuora laukaisukulma
const ANGLE_VARIANCE := 5.0    # ±astetta hajontaa
const SPEED_VARIANCE := 0.15   # ±15% nopeushajonta
const INTAKE_COOLDOWN := 0.08  # s per pikseli-erä
const MAX_INTAKE_PER_FRAME := 4  # Pikseleitä per frame maksimissaan
const FLOOR_MAT := 3           # MAT_STONE

var start_pos: Vector2i = Vector2i.ZERO   # Pohja (hihnan kohdalla)
var end_pos: Vector2i = Vector2i.ZERO     # Katto (suoraan ylhäällä)
var launch_dir: float = 1.0              # 1.0=oikealle, -1.0=vasemmalle
var structure_pixels: Array[Vector2i] = []
var intake_pixels: Array[Vector2i] = []  # Pohjan pikselit joista imetään
var barrel_tip: Vector2i = Vector2i.ZERO  # Tykkiputken kärki
var broken: bool = false
var cooldown_timer: float = 0.0
var _flash_timer: float = 0.0


func build_structure(start: Vector2i, end: Vector2i, dir: float) -> void:
	# Rakentaa hissilinkon: kuilu + jalusta + tykkiputki
	start_pos = start
	end_pos = end
	launch_dir = dir
	structure_pixels.clear()
	intake_pixels.clear()

	# Kuilu: start.y ylhäältä end.y:hyn asti
	# Vasen reuna (x == end.x) ja oikea reuna (x == end.x + SHAFT_WIDTH - 1) = kivi
	# Sisus tyhjä — materiaali nousee siitä
	for y in range(end.y, start.y):
		for x in range(end.x, end.x + SHAFT_WIDTH):
			if x == end.x or x == end.x + SHAFT_WIDTH - 1:
				# Reunapikselit ovat kiveä
				structure_pixels.append(Vector2i(x, y))
			# Sisäpikselit jätetään tyhjäksi — ei lisätä structure_pixels

	# Jalusta: 2 alinta riviä, koko leveys — tuki kuille
	for y in range(start.y, start.y + 2):
		for x in range(start.x, start.x + SHAFT_WIDTH):
			structure_pixels.append(Vector2i(x, y))

	# Tykkiputki: 1 pikseli korkea, BARREL_LENGTH pitkä
	# Lähtee kuilun yläreunasta oikealle tai vasemmalle
	var barrel_start_x: int
	if dir > 0:
		# Tykkiputki oikealle — alkaa kuilun oikeasta reunasta
		barrel_start_x = end.x + SHAFT_WIDTH
		barrel_tip = Vector2i(barrel_start_x + BARREL_LENGTH - 1, end.y)
	else:
		# Tykkiputki vasemmalle — alkaa kuilun vasemmasta reunasta - 1
		barrel_start_x = end.x - BARREL_LENGTH
		barrel_tip = Vector2i(barrel_start_x, end.y)
	for bx in range(barrel_start_x, barrel_start_x + BARREL_LENGTH):
		structure_pixels.append(Vector2i(bx, end.y))
		structure_pixels.append(Vector2i(bx, end.y + 1))  # 2px korkea

	# Intake-pikselit: pohjan ylin rivi (start.y) — tästä imetään materiaali
	for x in range(start.x, start.x + SHAFT_WIDTH):
		intake_pixels.append(Vector2i(x, start.y - 1))

	position = Vector2.ZERO
	queue_redraw()


func write_to_grid(grid: PackedByteArray, color_seed: PackedByteArray, w: int) -> void:
	# Kirjoittaa rakennuksen kivipikselit gridiin
	for p in structure_pixels:
		var idx := p.y * w + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = FLOOR_MAT
			color_seed[idx] = randi() % 256


func check_intact(grid: PackedByteArray, w: int) -> bool:
	# Tarkistaa että kaikki rakenteen pikselit ovat edelleen kiveä
	for p in structure_pixels:
		var idx := p.y * w + p.x
		if idx < 0 or idx >= grid.size():
			return false
		if grid[idx] != FLOOR_MAT:
			return false
	return true


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func update_launcher(grid: PackedByteArray, w: int, delta: float) -> Array[Dictionary]:
	# Skannaa intake-pikselit, poistaa materiaalin gridistä ja palauttaa laukaistavat pikselit
	var launched: Array[Dictionary] = []
	if broken:
		return launched

	cooldown_timer -= delta
	if cooldown_timer > 0.0:
		return launched

	var count := 0
	for p in intake_pixels:
		if count >= MAX_INTAKE_PER_FRAME:
			break
		var idx := p.y * w + p.x
		if idx < 0 or idx >= grid.size():
			continue
		var mat := grid[idx]
		if mat == 0 or mat == FLOOR_MAT:  # Tyhjä tai kivi — ohita
			continue

		# Poista materiaali gridistä
		grid[idx] = 0

		# Laske laukaisuvektori — vaakasuora hajonnan kera
		var angle_rad := deg_to_rad(LAUNCH_ANGLE_DEG + randf_range(-ANGLE_VARIANCE, ANGLE_VARIANCE))
		var speed := LAUNCH_SPEED * (1.0 + randf_range(-SPEED_VARIANCE, SPEED_VARIANCE))
		var vel := Vector2(cos(angle_rad) * launch_dir, sin(angle_rad)) * speed

		launched.append({
			"pos": Vector2(float(barrel_tip.x), float(barrel_tip.y)),
			"vel": vel,
			"mat": mat,
			"seed": randi() % 256,
			"age": 0.0
		})
		count += 1

	if count > 0:
		cooldown_timer = INTAKE_COOLDOWN
		_flash_timer = 0.1

	# Laske flash-timer alas joka päivityksellä
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer < 0.0:
			_flash_timer = 0.0
		queue_redraw()

	return launched


func _draw() -> void:
	if structure_pixels.is_empty():
		return

	# Laukaisuvalo barrel_tip-kohdassa
	if _flash_timer > 0.0:
		draw_circle(Vector2(float(barrel_tip.x) + 0.5, float(barrel_tip.y) + 0.5),
			2.0, Color(1.0, 0.8, 0.2, _flash_timer * 5.0))

	# Suuntanuoli tykkiputken kärkeen
	var arrow_start := Vector2(float(barrel_tip.x) + 0.5, float(barrel_tip.y) + 0.5)
	var arrow_end := arrow_start + Vector2(launch_dir * 3.0, 0.0)
	draw_line(arrow_start, arrow_end, Color(0.9, 0.6, 0.1, 0.7), 0.5)
	draw_line(arrow_end, arrow_end + Vector2(-launch_dir * 1.5, -1.0), Color(0.9, 0.6, 0.1, 0.7), 0.5)
	draw_line(arrow_end, arrow_end + Vector2(-launch_dir * 1.5, 1.0), Color(0.9, 0.6, 0.1, 0.7), 0.5)
