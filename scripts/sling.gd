# Linko-rakennus — ampuu hihnan pikselit ilmaan ballistisella liikeradalla
class_name Sling
extends Node2D

const SLING_W := 6
const SLING_H := 5
const LAUNCH_SPEED := 90.0       # px/s perusnopeus
const LAUNCH_ANGLE_DEG := -50.0  # asteita (negatiivinen = ylös)
const ANGLE_VARIANCE := 12.0     # ±astetta
const SPEED_VARIANCE := 0.2      # ±20%
const INTAKE_COOLDOWN := 0.12    # s per pikseli
const MAX_INTAKE_PER_FRAME := 3  # pikseleitä per frame
const FLOOR_MAT := 3             # MAT_STONE

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var intake_pixels: Array[Vector2i] = []  # hihnan yläpuolella olevat paikat
var launch_dir: float = 1.0              # 1.0=oikealle, -1.0=vasemmalle
var broken: bool = false
var cooldown_timer: float = 0.0
var _flash_timer: float = 0.0


func build_structure(pos: Vector2i, dir: float) -> void:
	# Rakenna linko grid_pos-kohtaan, dir on suunta
	grid_pos = pos
	launch_dir = dir
	structure_pixels.clear()
	intake_pixels.clear()

	# Jalusta: 2 alinta riviä, koko leveys
	for x in SLING_W:
		for y in range(SLING_H - 2, SLING_H):
			structure_pixels.append(Vector2i(pos.x + x, pos.y + y))

	# Varsi: keskilinja ylöspäin
	for y in range(1, SLING_H - 2):
		structure_pixels.append(Vector2i(pos.x + SLING_W / 2, pos.y + y))

	# Intake: jalusta - 3 riviä (kuopan yläpuolella)
	for x in SLING_W:
		intake_pixels.append(Vector2i(pos.x + x, pos.y + SLING_H - 3))

	position = Vector2.ZERO
	queue_redraw()


func write_to_grid(grid: PackedByteArray, color_seed: PackedByteArray, w: int) -> void:
	for p in structure_pixels:
		var idx := p.y * w + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = FLOOR_MAT
			color_seed[idx] = randi() % 256


func check_intact(grid: PackedByteArray, w: int) -> bool:
	for p in structure_pixels:
		var idx := p.y * w + p.x
		if idx < 0 or idx >= grid.size():
			return false
		if grid[idx] != FLOOR_MAT:
			return false
	return true


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func update_sling(grid: PackedByteArray, w: int, delta: float) -> Array[Dictionary]:
	# Palauttaa laukaistavat pikselit
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
		if mat == 0 or mat == FLOOR_MAT:  # tyhjä tai kivi — ohita
			continue

		# Poista gridistä
		grid[idx] = 0

		# Laske laukaisuvektori
		var angle_rad := deg_to_rad(LAUNCH_ANGLE_DEG + randf_range(-ANGLE_VARIANCE, ANGLE_VARIANCE))
		var speed := LAUNCH_SPEED * (1.0 + randf_range(-SPEED_VARIANCE, SPEED_VARIANCE))
		var vel := Vector2(cos(angle_rad) * launch_dir, sin(angle_rad)) * speed
		launched.append({
			"pos": Vector2(p.x, p.y),
			"vel": vel,
			"mat": mat,
			"seed": randi() % 256,
			"age": 0.0
		})
		count += 1

	if count > 0:
		cooldown_timer = INTAKE_COOLDOWN
		_flash_timer = 0.1
		queue_redraw()

	return launched


func _draw() -> void:
	if structure_pixels.is_empty():
		return

	# Varren nuoli suuntaan
	var tip_x := float(grid_pos.x + SLING_W / 2)
	var tip_y := float(grid_pos.y + 1)
	var arrow_dx := launch_dir * 2.5
	draw_line(
		Vector2(tip_x, tip_y),
		Vector2(tip_x + arrow_dx, tip_y - 1.5),
		Color(0.9, 0.6, 0.1, 0.7), 0.5
	)

	# Laukaisuvalo kun ammutaan
	if _flash_timer > 0.0:
		draw_circle(Vector2(tip_x, tip_y), 2.0, Color(1.0, 0.8, 0.2, _flash_timer * 5.0))
