class_name Crusher
extends Node2D

const CRUSHER_W := 16
const CRUSHER_H := 10
const INTAKE_W := 8
const FLOOR_MAT := 3  # MAT_STONE
const CRUSH_COOLDOWN := 1.2  # Sekunteina

# Reseptit: input_material -> { count: int, output: int, output_count: int }
const RECIPES := {
	18: { "count": 1, "output": 1, "output_count": 3 },  # GRAVEL → SAND (1 sora → 3 hiekkaa)
}

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var intake_x: Array[int] = []
var output_x: int = 0
var output_y: int = 0

var collected: Dictionary = {}
var smelt_timer: float = 0.0
var broken: bool = false
var _flash_timer: float = 0.0

# Crusher-output — pixel_world lukee nämä ja kirjoittaa gridiin
var output_ready: bool = false
var output_drop_pos: Vector2i = Vector2i.ZERO
var output_material: int = 1   # MAT_SAND
var output_amount: int = 0


func setup(center: Vector2i) -> void:
	grid_pos = Vector2i(center.x - CRUSHER_W / 2, center.y - CRUSHER_H / 2)
	structure_pixels.clear()
	intake_x.clear()

	# Rakenne sama kuin furnace (output-aukko mukana)
	var intake_start := grid_pos.x + (CRUSHER_W - INTAKE_W) / 2

	# Rivi 0: reunat + intake-aukko
	for dx in CRUSHER_W:
		var px := grid_pos.x + dx
		var py := grid_pos.y
		if px < intake_start or px >= intake_start + INTAKE_W:
			structure_pixels.append(Vector2i(px, py))
		else:
			intake_x.append(px)

	# Rivit 1..H-2: täynnä
	for dy in range(1, CRUSHER_H - 1):
		for dx in CRUSHER_W:
			structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + dy))

	# Rivi H-1: output-aukko 8px keskellä
	var output_start := grid_pos.x + (CRUSHER_W - 8) / 2
	for dx in CRUSHER_W:
		var px := grid_pos.x + dx
		if px < output_start or px >= output_start + 8:
			structure_pixels.append(Vector2i(px, grid_pos.y + CRUSHER_H - 1))
	output_x = output_start
	output_y = grid_pos.y + CRUSHER_H  # Tuotos tippuu tämän rivin alle

	position = Vector2.ZERO
	queue_redraw()


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 120 + randi() % 20  # Sinertävä kivi


func update_crusher(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> bool:
	var modified := false

	# Kerää materiaaleja intake-aukon yläpuolelta
	var intake_y := grid_pos.y - 1
	if intake_y >= 0:
		for ix in intake_x:
			if ix >= 0 and ix < w:
				var idx := intake_y * w + ix
				var mat_id: int = grid[idx]
				if mat_id == 0:
					# Tyhjä — ohita
					continue
				elif RECIPES.has(mat_id):
					# Resepti-input — kerää normaalisti
					grid[idx] = 0
					color_seed[idx] = randi() % 256
					collected[mat_id] = collected.get(mat_id, 0) + 1
					modified = true
					queue_redraw()
				elif mat_id in [4, 9, 16]:
					# Orgaaninen (WOOD, WOOD_FALLING, COAL) — muutu tuhkaksi
					grid[idx] = 8  # MAT_ASH
					color_seed[idx] = randi() % 256
					modified = true
				elif mat_id in [14, 15]:
					# Metalli (IRON, GOLD) — hävitetään
					grid[idx] = 0
					color_seed[idx] = randi() % 256
					modified = true
				else:
					# Muu — hävitetään
					grid[idx] = 0
					color_seed[idx] = randi() % 256
					modified = true

	# Murskausvaihe — tarkista täyttyikö jokin resepti
	if not output_ready:
		for input_mat: int in RECIPES.keys():
			var recipe: Dictionary = RECIPES[input_mat]
			var have: int = collected.get(input_mat, 0)
			if have >= recipe["count"]:
				smelt_timer += delta
				if smelt_timer >= CRUSH_COOLDOWN:
					smelt_timer = 0.0
					collected[input_mat] = have - recipe["count"]
					output_drop_pos = Vector2i(output_x, output_y)
					output_material = recipe["output"]
					output_amount = recipe["output_count"]
					output_ready = true
					_flash_timer = 0.3
					modified = true
					queue_redraw()
					break
				break  # Odottaa tätä reseptiä

	if _flash_timer > 0.0:
		_flash_timer -= delta
		queue_redraw()

	return modified


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func get_intake_center() -> Vector2i:
	# Sisääntulon keskipiste (yläpuolelta pudotetaan materiaalia)
	var intake_start := grid_pos.x + (CRUSHER_W - INTAKE_W) / 2
	return Vector2i(intake_start + INTAKE_W / 2, grid_pos.y - 1)


func get_output_center() -> Vector2i:
	# Ulostulon keskipiste (alta tippuu murskattu materiaali)
	return Vector2i(output_x + 4, output_y)


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Edistymispalkit kaikille resepteille
	var bar_y_offset := 0
	for input_mat: int in RECIPES.keys():
		var have: int = collected.get(input_mat, 0)
		if have > 0:
			var progress := float(have) / float(RECIPES[input_mat]["count"])
			var bar_w := float(CRUSHER_W) * minf(progress, 1.0)
			var bar_color := Color(0.5, 0.6, 1.0, 0.7)  # Sininen
			if input_mat == 18:
				bar_color = Color(0.7, 0.65, 0.55, 0.7)  # Beige soralle
			draw_rect(Rect2(float(grid_pos.x), float(grid_pos.y + 1 + bar_y_offset), bar_w, 0.5), bar_color)
			bar_y_offset += 1
	# Hehku kun murskataan
	if _flash_timer > 0.0:
		draw_rect(Rect2(float(grid_pos.x + 1), float(grid_pos.y + 1),
			float(CRUSHER_W - 2), float(CRUSHER_H - 2)),
			Color(0.4, 0.6, 1.0, _flash_timer * 2.0))
