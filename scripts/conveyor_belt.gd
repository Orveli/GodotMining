# Liukuhihna — siirtää materiaaleja JA kanoja start→end suuntaan
# Lattia = 1px kivipikseli, materiaalit liikkuvat pinnalla
class_name ConveyorBelt
extends Node2D

const BELT_SPEED := 4  # Siirrot per sekunti
const FLOOR_MAT := 3   # MAT_STONE


var start_pos: Vector2i = Vector2i.ZERO
var end_pos: Vector2i = Vector2i.ZERO
var floor_pixels: Array[Vector2i] = []  # Lattia, järjestys: start→end
var belt_dir_x: float = 1.0  # Normalisoitu x-suunta (-1 tai 1)
var anim_offset: float = 0.0
var move_timer: float = 0.0
var move_interval: float = 1.0 / float(BELT_SPEED)
# Nopea lookup: floor-pikselien x-koordinaatit per y-rivi
var floor_set: Dictionary = {}  # Vector2i → true
var broken: bool = false  # Tosi kun hihna on tuhoutunut


func setup(start: Vector2i, end_p: Vector2i) -> void:
	start_pos = start
	end_pos = end_p
	floor_pixels = bresenham_line(start, end_p)
	belt_dir_x = signf(float(end_p.x - start.x)) if end_p.x != start.x else 1.0
	# Rakenna lookup
	floor_set.clear()
	for fp in floor_pixels:
		floor_set[fp] = true
	position = Vector2.ZERO
	queue_redraw()


func build_floor(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	# 3 pikseliä paksu lattia — estää hiekan putoamisen läpi nopealla pudotuksella
	# Visuaalisesti ohut (overlay piirtää vain pinnan), mutta fysiikka kestää
	for fp in floor_pixels:
		for dy in range(0, 3):
			var y := fp.y + dy
			if y < 0 or y >= h or fp.x < 0 or fp.x >= w:
				continue
			var idx := y * w + fp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 175 - dy * 10


func update_belt(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> bool:
	anim_offset = fmod(anim_offset + delta * 8.0, 3000.0)  # Estä float-tarkkuuden heikkeneminen
	queue_redraw()

	move_timer += delta
	if move_timer < move_interval:
		return false
	move_timer -= move_interval

	var modified := false

	# Käsittele lopusta alkuun — materiaalit virtaavat start→end
	for i in range(floor_pixels.size() - 1, -1, -1):
		var fp: Vector2i = floor_pixels[i]

		# Kohde-lattiapiste (seuraava hihnalla tai hihnan pää)
		var next_x: int
		var next_y: int
		if i < floor_pixels.size() - 1:
			next_x = floor_pixels[i + 1].x
			next_y = floor_pixels[i + 1].y
		else:
			next_x = fp.x + int(belt_dir_x)
			next_y = fp.y

		var dy_off := next_y - fp.y  # Kulmakorjaus vinoille hihnoille

		# Skannaa pino alhaalta ylös — liikuta koko kolumni kerralla
		for sy in range(fp.y - 1, -1, -1):
			if fp.x < 0 or fp.x >= w or sy < 0 or sy >= h:
				break
			var src_idx := sy * w + fp.x
			var mat := grid[src_idx]
			if mat == 0:
				break  # Tyhjä — pino päättyy
			if not _is_movable(mat):
				break  # Kiinteä materiaali — pino pysähtyy
			var dest_y := sy + dy_off
			if next_x < 0 or next_x >= w or dest_y < 0 or dest_y >= h:
				continue
			if grid[dest_y * w + next_x] != 0:
				continue  # Kohde varattu — simulaatiofysiikka hoitaa rinteen
			grid[dest_y * w + next_x] = mat
			color_seed[dest_y * w + next_x] = color_seed[src_idx]
			grid[src_idx] = 0
			color_seed[src_idx] = randi() % 256
			modified = true

	return modified


func _draw() -> void:
	if floor_pixels.is_empty():
		return

	for i in floor_pixels.size():
		var fp: Vector2i = floor_pixels[i]
		# Ohut pinta-highlight lattian yläpuolella
		var surf_pos := Vector2(float(fp.x), float(fp.y) - 1.0)
		draw_rect(Rect2(surf_pos + Vector2(0.1, 0.3), Vector2(0.8, 0.5)),
			Color(0.6, 0.5, 0.2, 0.2))

		# Animoidut pienet pisteet/viivat
		var phase := fmod(float(i) - anim_offset, 3.0)
		if phase < 0.0:
			phase += 3.0
		if phase < 1.0:
			var alpha := 0.4 * (1.0 - phase)
			draw_rect(Rect2(surf_pos + Vector2(0.3, 0.4), Vector2(0.4, 0.3)),
				Color(0.9, 0.8, 0.3, alpha))


func _is_movable(mat: int) -> bool:
	return mat == 1 or mat == 2 or mat == 6 or mat == 7 or mat == 8 or mat == 10


static func bresenham_line(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var dx := absi(to.x - from.x)
	var dy := absi(to.y - from.y)
	var sx := 1 if from.x < to.x else -1
	var sy := 1 if from.y < to.y else -1
	var err := dx - dy
	var x := from.x
	var y := from.y

	while true:
		points.append(Vector2i(x, y))
		if x == to.x and y == to.y:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy

	return points
