class_name Furnace
extends Node2D

const FURNACE_W := 6
const FURNACE_H := 5
const INTAKE_W := 3
const SAND_REQUIRED := 8
const FLOOR_MAT := 3  # MAT_STONE
const MAT_GLASS_ID := 10
const SMELT_COOLDOWN := 0.5

var grid_pos: Vector2i = Vector2i.ZERO  # Vasen yläkulma
var structure_pixels: Array[Vector2i] = []
var intake_x: Array[int] = []  # 3 intake-sarakkeen x-koordinaatit
var output_x: int = 0
var output_y: int = 0
var sand_collected: int = 0
var smelt_timer: float = 0.0
var broken: bool = false
var _flash_timer: float = 0.0
var glass_ready: bool = false  # pixel_world luo rigid bodyn kun tosi
var glass_drop_pos: Vector2i = Vector2i.ZERO


func setup(center: Vector2i) -> void:
	grid_pos = Vector2i(center.x - FURNACE_W / 2, center.y - FURNACE_H / 2)
	structure_pixels.clear()
	intake_x.clear()

	# Rakenteen muoto:
	# Rivi 0: XX...X (vasen reuna + oikea reuna, keskellä intake-aukko 3px)
	# Rivit 1-3: XXXXXX (täynnä)
	# Rivi 4: XX..XX (output-aukko 2px keskellä)
	var intake_start := grid_pos.x + (FURNACE_W - INTAKE_W) / 2

	for dx in FURNACE_W:
		var px := grid_pos.x + dx
		var py := grid_pos.y
		# Rivi 0: jätä intake-aukko auki
		if px < intake_start or px >= intake_start + INTAKE_W:
			structure_pixels.append(Vector2i(px, py))
		else:
			intake_x.append(px)  # Tallenna intake-sarakkeet

	for dy in range(1, FURNACE_H - 1):
		for dx in FURNACE_W:
			structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + dy))

	# Rivi 4: output-aukko 2px keskellä
	var output_start := grid_pos.x + (FURNACE_W - 2) / 2
	for dx in FURNACE_W:
		var px := grid_pos.x + dx
		if px < output_start or px >= output_start + 2:
			structure_pixels.append(Vector2i(px, grid_pos.y + FURNACE_H - 1))
	output_x = output_start
	output_y = grid_pos.y + FURNACE_H  # Tuotos tippuu tämän rivin alle

	position = Vector2.ZERO
	queue_redraw()


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 85 + randi() % 15  # Punertava kivi


func update_furnace(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> bool:
	if broken:
		return false
	# Eheyden tarkistus
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			if grid[sp.y * w + sp.x] != FLOOR_MAT:
				broken = true
				queue_redraw()
				return false

	var modified := false

	# Kerää hiekkaa intake-aukon yläpuolelta
	var intake_y := grid_pos.y - 1
	if intake_y >= 0:
		for ix in intake_x:
			if ix >= 0 and ix < w:
				var idx := intake_y * w + ix
				if grid[idx] == 1:  # MAT_SAND
					grid[idx] = 0
					color_seed[idx] = randi() % 256
					sand_collected += 1
					modified = true
					queue_redraw()

	# Sulatusvaihe — pixel_world luo rigid bodyn
	if sand_collected >= SAND_REQUIRED and not glass_ready:
		smelt_timer += delta
		if smelt_timer >= SMELT_COOLDOWN:
			smelt_timer = 0.0
			sand_collected -= SAND_REQUIRED
			glass_drop_pos = Vector2i(output_x, output_y)
			glass_ready = true
			_flash_timer = 0.3
			modified = true
			queue_redraw()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		queue_redraw()

	return modified


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Progress-palkki (hiekkalaskuri)
	var progress := float(sand_collected) / float(SAND_REQUIRED)
	var bar_w := float(FURNACE_W) * progress
	draw_rect(Rect2(float(grid_pos.x), float(grid_pos.y + 1), bar_w, 0.5),
		Color(1.0, 0.6, 0.1, 0.7))
	# Hehku kun sulatetaan
	if _flash_timer > 0.0:
		draw_rect(Rect2(float(grid_pos.x + 1), float(grid_pos.y + 1),
			float(FURNACE_W - 2), float(FURNACE_H - 2)),
			Color(1.0, 0.8, 0.3, _flash_timer * 2.0))
	# Label: kerätyn hiekan määrä
	# (Godot draw_string ei ole saatavilla Node2D:ssa ilman fonttia, joten ei tekstiä)
