class_name Furnace
extends Node2D

const FURNACE_W := 12
const FURNACE_H := 10
const INTAKE_W := 6
const FLOOR_MAT := 3  # MAT_STONE
const SMELT_COOLDOWN := 1.5  # ~11 hiekkaa/s, vähän alle launcherin tahdin

# Reseptit: input_material -> { count: int, output: int }
const RECIPES := {
	1:  { "count": 16, "output": 10 },  # Sand -> Glass
	12: { "count": 12, "output": 14 },  # Iron Ore -> Iron
	13: { "count": 8,  "output": 15 },  # Gold Ore -> Gold
}

var grid_pos: Vector2i = Vector2i.ZERO  # Vasen yläkulma
var structure_pixels: Array[Vector2i] = []
var intake_x: Array[int] = []  # 3 intake-sarakkeen x-koordinaatit
var output_x: int = 0
var output_y: int = 0
# Kerätty määrä per input-materiaali
var collected: Dictionary = {}
var smelt_timer: float = 0.0
var broken: bool = false
var _flash_timer: float = 0.0
var glass_ready: bool = false  # pixel_world luo rigid bodyn kun tosi
var glass_drop_pos: Vector2i = Vector2i.ZERO
var output_material: int = 10  # Mikä materiaali pudotetaan seuraavaksi


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

	# Rivi (H-1): output-aukko 4px keskellä
	var output_start := grid_pos.x + (FURNACE_W - 4) / 2
	for dx in FURNACE_W:
		var px := grid_pos.x + dx
		if px < output_start or px >= output_start + 4:
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

	# Kerää materiaaleja intake-aukon yläpuolelta (kaikki resepti-inputit)
	var intake_y := grid_pos.y - 1
	if intake_y >= 0:
		for ix in intake_x:
			if ix >= 0 and ix < w:
				var idx := intake_y * w + ix
				var mat_id: int = grid[idx]
				if RECIPES.has(mat_id):
					grid[idx] = 0
					color_seed[idx] = randi() % 256
					collected[mat_id] = collected.get(mat_id, 0) + 1
					modified = true
					queue_redraw()

	# Sulatusvaihe — tarkista täyttyikö jokin resepti
	if not glass_ready:
		for input_mat: int in RECIPES.keys():
			var recipe: Dictionary = RECIPES[input_mat]
			var have: int = collected.get(input_mat, 0)
			if have >= recipe["count"]:
				smelt_timer += delta
				if smelt_timer >= SMELT_COOLDOWN:
					smelt_timer = 0.0
					collected[input_mat] = have - recipe["count"]
					glass_drop_pos = Vector2i(output_x, output_y)
					output_material = recipe["output"]
					glass_ready = true
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


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Progress-palkit kaikille resepteille joissa on materiaalia
	var bar_y_offset := 0
	for input_mat: int in RECIPES.keys():
		var have: int = collected.get(input_mat, 0)
		if have > 0:
			var progress := float(have) / float(RECIPES[input_mat]["count"])
			var bar_w := float(FURNACE_W) * minf(progress, 1.0)
			# Eri väri per materiaali: hiekka=keltainen, rauta=punainen, kulta=kultainen
			var bar_color := Color(1.0, 0.6, 0.1, 0.7)
			if input_mat == 12:
				bar_color = Color(0.7, 0.3, 0.2, 0.7)
			elif input_mat == 13:
				bar_color = Color(0.9, 0.8, 0.1, 0.7)
			draw_rect(Rect2(float(grid_pos.x), float(grid_pos.y + 1 + bar_y_offset), bar_w, 0.5), bar_color)
			bar_y_offset += 1
	# Hehku kun sulatetaan
	if _flash_timer > 0.0:
		draw_rect(Rect2(float(grid_pos.x + 1), float(grid_pos.y + 1),
			float(FURNACE_W - 2), float(FURNACE_H - 2)),
			Color(1.0, 0.8, 0.3, _flash_timer * 2.0))
