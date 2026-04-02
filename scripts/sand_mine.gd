class_name SandMine
extends Node2D

const MINE_W := 4
const MINE_H := 4
const SPAWN_INTERVAL := 1.0
const FLOOR_MAT := 3  # MAT_STONE

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var spawn_timer: float = 0.0
var broken: bool = false


func setup(center: Vector2i) -> void:
	grid_pos = Vector2i(center.x - MINE_W / 2, center.y - MINE_H / 2)
	structure_pixels.clear()
	# Kaikki 4x4 pikselit ovat rakennetta
	for dy in MINE_H:
		for dx in MINE_W:
			structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + dy))
	position = Vector2.ZERO
	queue_redraw()


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 120 + randi() % 20


func update_mine(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> bool:
	spawn_timer += delta
	if spawn_timer < SPAWN_INTERVAL:
		return false
	spawn_timer -= SPAWN_INTERVAL
	# Tiputa hiekka rakenteen yläpuolelle
	var spawn_y := grid_pos.y - 1
	if spawn_y < 0:
		return false
	# Etsi vapaa kohta rakenteen leveydeltä
	var start_x := grid_pos.x + MINE_W / 2  # Keskeltä
	for dx in range(0, MINE_W):
		var try_x := start_x + (dx / 2 if dx % 2 == 0 else -(dx + 1) / 2)
		if try_x < 0 or try_x >= w:
			continue
		var idx := spawn_y * w + try_x
		if grid[idx] == 0:
			grid[idx] = 1  # MAT_SAND
			color_seed[idx] = randi() % 256
			return true
	return false


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Piirrä overlay rakennuksen päällä
	var rect := Rect2(float(grid_pos.x), float(grid_pos.y) - 1.0, float(MINE_W), 0.5)
	draw_rect(rect, Color(0.9, 0.8, 0.2, 0.5))
	# Nuoli alas
	for i in 3:
		draw_rect(Rect2(float(grid_pos.x + MINE_W / 2) - 0.3, float(grid_pos.y) - 1.5 + float(i) * 0.5, 0.6, 0.4),
			Color(0.9, 0.7, 0.1, 0.7 - float(i) * 0.2))
