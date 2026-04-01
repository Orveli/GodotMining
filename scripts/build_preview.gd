# Rakennuksen esikatselu — näyttää ghostin ennen sijoitusta
class_name BuildPreview
extends Node2D

const GRID_SIZE := 8  # Vastaa pixel_world.gd:n GRID_SIZE
const SLING_W := 6    # Vastaa sling.gd:n SLING_W
const SLING_H := 5    # Vastaa sling.gd:n SLING_H

var preview_pixels: Array[Vector2i] = []
var start_marker: Vector2 = Vector2(-100.0, -100.0)
var end_marker: Vector2 = Vector2(-100.0, -100.0)
var snap_point: Vector2 = Vector2(-100.0, -100.0)
var show_snap: bool = false
var show_spawner: bool = false  # Näytä spawner-esikatselu
var show_sling: bool = false    # Näytä linko-esikatselu
var sling_pos: Vector2 = Vector2(-100.0, -100.0)  # Snap-kohtaan
var sling_dir: float = 1.0      # 1.0=oikealle, -1.0=vasemmalle


func clear() -> void:
	preview_pixels.clear()
	start_marker = Vector2(-100.0, -100.0)
	end_marker = Vector2(-100.0, -100.0)
	show_snap = false
	show_spawner = false
	show_sling = false
	queue_redraw()


func _draw() -> void:
	# Liukuhihnan lattia-esikatselu (1px paksu)
	for p in preview_pixels:
		draw_rect(Rect2(Vector2(p), Vector2(1.0, 1.0)), Color(0.6, 0.5, 0.2, 0.35))
		# Pinta-esikatselu (ohut viiva yläpuolella)
		draw_rect(Rect2(Vector2(p.x + 0.1, p.y - 0.7), Vector2(0.8, 0.4)), Color(0.8, 0.7, 0.3, 0.2))

	# Aloituspiste (vihreä)
	if start_marker.x >= 0.0:
		draw_circle(start_marker + Vector2(0.5, 0.5), 2.5, Color(0.2, 0.9, 0.2, 0.4))
		draw_arc(start_marker + Vector2(0.5, 0.5), 3.0, 0.0, TAU, 16, Color(0.2, 0.9, 0.2, 0.6), 0.5)

	# Loppupiste / kursori (oranssi)
	if end_marker.x >= 0.0:
		if show_spawner:
			# Spawner-esikatselu (puulaatikko)
			var hw := 7.0
			var hh := 10.0
			draw_rect(Rect2(end_marker.x - hw, end_marker.y - hh, hw * 2.0, hh),
				Color(0.45, 0.28, 0.1, 0.4))
			draw_rect(Rect2(end_marker.x - hw, end_marker.y - hh, hw * 2.0, hh),
				Color(0.3, 0.18, 0.05, 0.6), false, 0.6)
		else:
			draw_circle(end_marker + Vector2(0.5, 0.5), 2.5, Color(0.9, 0.6, 0.1, 0.4))

	# Snap-indikaattori (sininen pulssi)
	if show_snap:
		draw_arc(snap_point + Vector2(0.5, 0.5), 4.0, 0.0, TAU, 20, Color(0.3, 0.6, 1.0, 0.7), 0.7)
		draw_circle(snap_point + Vector2(0.5, 0.5), 1.5, Color(0.3, 0.6, 1.0, 0.5))

	# Linko-esikatselu
	if show_sling and sling_pos.x >= 0.0:
		_draw_grid_overlay(sling_pos)
		_draw_sling_ghost(sling_pos, sling_dir)


func _draw_grid_overlay(center: Vector2) -> void:
	# Piirrä 3×3 grid-solua kursorin ympärille (8px välein)
	var grid_color := Color(0.5, 0.5, 0.5, 0.25)
	var half := 1  # Solujen määrä joka suuntaan
	var grid_f := float(GRID_SIZE)

	# Laske lähimmän grid-pisteen vasen yläkulma
	var snap_x: float = floorf(center.x / grid_f) * grid_f - grid_f * float(half)
	var snap_y: float = floorf(center.y / grid_f) * grid_f - grid_f * float(half)

	for gy in range(half * 2 + 2):
		for gx in range(half * 2 + 2):
			var rx: float = snap_x + float(gx) * grid_f
			var ry: float = snap_y + float(gy) * grid_f
			draw_rect(Rect2(rx, ry, grid_f, grid_f), grid_color, false, 0.3)

	# Highlight snap-kohtaan (kirkkaampi reunus)
	var sx: float = floorf(center.x / grid_f) * grid_f
	var sy: float = floorf(center.y / grid_f) * grid_f
	draw_rect(Rect2(sx, sy, grid_f, grid_f), Color(0.9, 0.7, 0.1, 0.6), false, 0.5)


func _draw_sling_ghost(pos: Vector2, dir: float) -> void:
	# Linkon ghost: outline + nuoli suuntaan
	var sw := float(SLING_W)
	var sh := float(SLING_H)

	# Ulkorajaus
	draw_rect(Rect2(pos.x, pos.y, sw, sh), Color(0.7, 0.5, 0.2, 0.35), true)
	draw_rect(Rect2(pos.x, pos.y, sw, sh), Color(0.9, 0.7, 0.3, 0.7), false, 0.5)

	# Suuntanuoli
	var tip_x := pos.x + sw * 0.5
	var tip_y := pos.y + 1.0
	var arr_x := tip_x + dir * 3.0
	draw_line(Vector2(tip_x, tip_y + sh * 0.2), Vector2(arr_x, tip_y - 1.0),
		Color(1.0, 0.6, 0.1, 0.8), 0.7)
	# Nuolen kärki
	draw_line(Vector2(arr_x, tip_y - 1.0), Vector2(arr_x - dir * 1.5, tip_y),
		Color(1.0, 0.6, 0.1, 0.8), 0.5)
	draw_line(Vector2(arr_x, tip_y - 1.0), Vector2(arr_x - dir * 1.5, tip_y - 2.0),
		Color(1.0, 0.6, 0.1, 0.8), 0.5)
