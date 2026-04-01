# Rakennuksen esikatselu — näyttää ghostin ennen sijoitusta
class_name BuildPreview
extends Node2D

var preview_pixels: Array[Vector2i] = []
var start_marker: Vector2 = Vector2(-100.0, -100.0)
var end_marker: Vector2 = Vector2(-100.0, -100.0)
var snap_point: Vector2 = Vector2(-100.0, -100.0)
var show_snap: bool = false
var show_spawner: bool = false  # Näytä spawner-esikatselu


func clear() -> void:
	preview_pixels.clear()
	start_marker = Vector2(-100.0, -100.0)
	end_marker = Vector2(-100.0, -100.0)
	show_snap = false
	show_spawner = false
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
