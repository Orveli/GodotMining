class_name Drill
extends Node2D

const DRILL_W := 4
const DRILL_H := 6
const FLOOR_MAT := 3   # MAT_STONE
const DRILL_RATE := 2.0   # Pikselirivi/sekunti
const FALL_SPEED := 40.0  # px/sekunti putoaminen

# Materiaalit joiden läpi pora ei voi pudota (kiinteät)
const SOLID_MATS: Array[int] = [3, 19, 4, 9]  # STONE, BEDROCK, WOOD, WOOD_FALLING

enum State { FALLING, DRILLING, STUCK }

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var state: State = State.FALLING
var fall_progress: float = 0.0  # Kertymä putoamiseen
var drill_timer: float = 0.0
var broken: bool = false  # Asettuu true kun pora poistuu käytöstä (bedrock/reunaputoaminen)


func setup(center: Vector2i) -> void:
	grid_pos = Vector2i(center.x - DRILL_W / 2, center.y - DRILL_H / 2)
	_rebuild_structure()
	position = Vector2.ZERO
	queue_redraw()


func _rebuild_structure() -> void:
	structure_pixels.clear()
	for dy in DRILL_H:
		for dx in DRILL_W:
			structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + dy))


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 80 + randi() % 20


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func update_drill(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float, mat_bedrock: int) -> bool:
	var modified := false
	match state:
		State.FALLING:
			modified = _update_falling(grid, color_seed, w, h, delta)
		State.DRILLING:
			modified = _update_drilling(grid, color_seed, w, h, delta, mat_bedrock)
	return modified


func _update_falling(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> bool:
	# Tarkista onko alla vapaata tilaa
	var bottom_y := grid_pos.y + DRILL_H
	if bottom_y >= h:
		# Putoaminen vei ruudukon ulkopuolelle — merkitse rikki
		broken = true
		queue_redraw()
		return false

	# Tarkista kaikki pikselit drillin alla
	var can_fall := true
	for dx in DRILL_W:
		var check_x := grid_pos.x + dx
		var check_y := bottom_y
		if check_x < 0 or check_x >= w or check_y >= h:
			can_fall = false
			break
		var idx := check_y * w + check_x
		var mat := grid[idx]
		if mat in SOLID_MATS:
			can_fall = false
			break

	if can_fall:
		fall_progress += FALL_SPEED * delta
		if fall_progress >= 1.0:
			var steps := int(fall_progress)
			fall_progress -= float(steps)
			# Poista vanhat structure-pikselit gridistä
			_erase_from_grid(grid, color_seed, w, h)
			grid_pos.y += steps
			_rebuild_structure()
			# Kirjoita uudet
			build_structure(grid, color_seed, w, h)
			queue_redraw()
			return true
	else:
		# Kiinnitetty — vaihda DRILLING-tilaan
		state = State.DRILLING
		queue_redraw()
	return false


func _update_drilling(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float, mat_bedrock: int) -> bool:
	drill_timer += delta
	if drill_timer < 1.0 / DRILL_RATE:
		return false
	drill_timer -= 1.0 / DRILL_RATE

	# Poraa yksi pikselirivi drillin alapuolelta
	var drill_y := grid_pos.y + DRILL_H
	if drill_y >= h:
		# Ruudukon pohja saavutettu — pora on käyttökelvoton
		broken = true
		queue_redraw()
		return false

	var hit_bedrock := false
	for dx in DRILL_W:
		var px := grid_pos.x + dx
		if px < 0 or px >= w:
			continue
		var idx := drill_y * w + px
		var mat := grid[idx]
		if mat == mat_bedrock:
			hit_bedrock = true
			break
		if mat != 0:
			grid[idx] = 0
			color_seed[idx] = randi() % 256

	if hit_bedrock:
		# Bedrock-törmäys — pora poistetaan käytöstä
		broken = true
		queue_redraw()

	return true


func _erase_from_grid(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = 0
			color_seed[idx] = randi() % 256


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	var color := Color(0.5, 0.5, 0.6, 0.8)
	match state:
		State.FALLING:
			color = Color(0.6, 0.6, 0.7, 0.9)
		State.DRILLING:
			color = Color(0.3, 0.7, 0.3, 0.9)  # Vihreä = poraa
		State.STUCK:
			color = Color(0.7, 0.3, 0.3, 0.9)  # Punainen = pysähtynyt
	draw_rect(Rect2(float(grid_pos.x), float(grid_pos.y), float(DRILL_W), float(DRILL_H)), color, false, 0.5)
