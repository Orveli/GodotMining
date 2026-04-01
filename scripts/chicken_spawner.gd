# Kanaspawneri — tiputtaa kanoja tasaiseen tahtiin
# Visuaalinen puulaatikko, positio grid-koordinaateissa
extends Node2D

const SPAWN_INTERVAL := 3.0  # Sekunteja kanojen välillä
const BOX_W := 14.0  # Visuaalinen leveys (grid-pikseleitä)
const BOX_H := 10.0  # Visuaalinen korkeus

var spawn_timer: float = 1.0  # Ensimmäinen kana nopeammin
var grid_pos: Vector2 = Vector2.ZERO


func setup(pos: Vector2) -> void:
	grid_pos = pos
	position = pos
	queue_redraw()


func update_spawner(delta: float) -> bool:
	spawn_timer -= delta
	if spawn_timer <= 0.0:
		spawn_timer = SPAWN_INTERVAL
		return true
	return false


func get_spawn_pos() -> Vector2:
	# Kana tippuu laatikon aukosta
	return grid_pos + Vector2(0.0, 2.0)


func _draw() -> void:
	var hw := BOX_W / 2.0
	var hh := BOX_H

	# Tausta (puunruskea)
	draw_rect(Rect2(-hw, -hh, BOX_W, hh), Color(0.45, 0.28, 0.1))

	# Reunaviivat (tummempi)
	draw_rect(Rect2(-hw, -hh, BOX_W, hh), Color(0.3, 0.18, 0.05), false, 0.8)

	# Vaakasuorat lankut
	for i in range(1, int(hh / 3)):
		var y := -hh + float(i) * 3.0
		draw_line(Vector2(-hw, y), Vector2(hw, y), Color(0.35, 0.2, 0.07), 0.5)

	# Aukko alhaalla keskellä (josta kanat tippuvat)
	draw_rect(Rect2(-2.5, -4.0, 5.0, 4.0), Color(0.06, 0.03, 0.0))

	# Pienet koristepisteet (naulat)
	for corner_x in [-hw + 1.0, hw - 1.0]:
		for corner_y in [-hh + 1.0, -1.0]:
			draw_circle(Vector2(corner_x, corner_y), 0.5, Color(0.55, 0.5, 0.4))
