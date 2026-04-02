class_name MoneyExit
extends Node2D

const EXIT_W := 12
const EXIT_H := 10
const INTAKE_W := 6
const FLOOR_MAT := 3  # MAT_STONE

# Hinnat per pikseli — kaikki materiaalit tuottavat vähintään 1 rahan
# Jalostus nostaa arvoa
const PRICES := {
	0:  0,   # EMPTY — ei mitään
	10: 3,   # GLASS → 3
	14: 5,   # IRON  → 5
	15: 12,  # GOLD  → 12
}
const DEFAULT_PRICE := 1  # Kaikki muut materiaalit: 1 raha

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var intake_x: Array[int] = []
var total_earned: int = 0
var broken: bool = false
var _flash_timer: float = 0.0
var _label: Label


func setup(center: Vector2i) -> void:
	grid_pos = Vector2i(center.x - EXIT_W / 2, center.y - EXIT_H / 2)
	structure_pixels.clear()
	intake_x.clear()

	# Rakenne:
	# Rivi 0: reunat + intake-aukko (INTAKE_W px leveä, keskellä)
	# Rivit 1..H-2: täynnä
	# Rivi H-1: kiinteä alarivi (EI output-aukkoa)
	var intake_start := grid_pos.x + (EXIT_W - INTAKE_W) / 2

	for dx in EXIT_W:
		var px := grid_pos.x + dx
		var py := grid_pos.y
		if px < intake_start or px >= intake_start + INTAKE_W:
			structure_pixels.append(Vector2i(px, py))
		else:
			intake_x.append(px)

	for dy in range(1, EXIT_H - 1):
		for dx in EXIT_W:
			structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + dy))

	# Alarivi — täysin suljettu
	for dx in EXIT_W:
		structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + EXIT_H - 1))

	position = Vector2.ZERO

	# Rahamäärä-label rakennuksen yläpuolelle
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
	_label.position = Vector2(float(grid_pos.x), float(grid_pos.y) - 10.0)
	_label.text = "$0"
	add_child(_label)

	queue_redraw()


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 100 + randi() % 30  # Vihertävä kivi


func update_exit(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> int:
	var frame_earnings: int = 0

	# Skannaa intake-alue (rivi rakennuksen yläpuolella)
	var intake_y := grid_pos.y - 1
	if intake_y >= 0:
		for ix in intake_x:
			if ix >= 0 and ix < w:
				var idx := intake_y * w + ix
				var mat_id: int = grid[idx]
				if mat_id == 0:
					continue
				var earned: int = PRICES.get(mat_id, DEFAULT_PRICE)
				frame_earnings += earned
				total_earned += earned
				grid[idx] = 0
				color_seed[idx] = randi() % 256
				_flash_timer = 0.2
				queue_redraw()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		queue_redraw()

	_label.text = "$%d" % total_earned
	return frame_earnings


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Hehku kun raha tulee sisään
	if _flash_timer > 0.0:
		draw_rect(
			Rect2(float(grid_pos.x + 1), float(grid_pos.y + 1),
				float(EXIT_W - 2), float(EXIT_H - 2)),
			Color(0.2, 1.0, 0.3, _flash_timer * 3.0)
		)
