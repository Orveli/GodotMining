# Rakennuksen esikatselu — näyttää ghostin ennen sijoitusta
class_name BuildPreview
extends Node2D

const GRID_SIZE := 8        # Vastaa pixel_world.gd:n GRID_SIZE
const LAUNCHER_SW := 4      # Vastaa launcher.gd:n SHAFT_WIDTH
const LAUNCHER_BL := 6      # Vastaa launcher.gd:n BARREL_LENGTH

var preview_pixels: Array[Vector2i] = []
var preview_color: Color = Color(0.6, 0.5, 0.2, 0.35)  # Oletusväri: konveyori-keltainen
var is_valid: bool = true  # Tosi = sijoitus kelpaa (vihreä), epätosi = ei kelpa (punainen)
var start_marker: Vector2 = Vector2(-100.0, -100.0)
var end_marker: Vector2 = Vector2(-100.0, -100.0)
var snap_point: Vector2 = Vector2(-100.0, -100.0)
var show_snap: bool = false
var show_spawner: bool = false   # Näytä spawner-esikatselu
var show_launcher: bool = false  # Näytä hissilinko-esikatselu
var is_wall: bool = false        # Piirretäänkö seinä-esikatselu (harmaa, ei pinta-viivaa)
var launcher_phase: int = 0
var launcher_start: Vector2 = Vector2(-100.0, -100.0)
var launcher_end: Vector2 = Vector2(-100.0, -100.0)
var launcher_dir: float = 1.0
var launcher_cursor: Vector2 = Vector2(-100.0, -100.0)


func clear() -> void:
	preview_pixels.clear()
	start_marker = Vector2(-100.0, -100.0)
	end_marker = Vector2(-100.0, -100.0)
	show_snap = false
	show_spawner = false
	show_launcher = false
	is_wall = false
	is_valid = true
	preview_color = Color(0.6, 0.5, 0.2, 0.35)
	queue_redraw()


func _draw() -> void:
	# Pikseliesikatselut — väri riippuu is_valid-tilasta ja rakennustyypistä
	var pixel_color: Color
	if is_wall:
		# Seinä: harmaa validin mukaan
		pixel_color = Color(0.2, 0.9, 0.2, 0.45) if is_valid else Color(0.9, 0.2, 0.2, 0.45)
	else:
		# Konveyori ja muut: vihreä/punainen is_valid mukaan
		pixel_color = Color(0.2, 0.9, 0.2, 0.4) if is_valid else Color(0.9, 0.2, 0.2, 0.4)

	for p in preview_pixels:
		draw_rect(Rect2(Vector2(p), Vector2(1.0, 1.0)), pixel_color)
		if not is_wall:
			# Konveyori: pinta-esikatselu (ohut viiva yläpuolella)
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

	# Hissilinko-esikatselu
	if show_launcher:
		_draw_launcher_preview()


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


func _draw_launcher_preview() -> void:
	# Hissilinkon kolmivaiheinen esikatselu — koordinaatit ovat jo grid-avaruudessa
	# (BuildPreview on skaalattu grid-kooksi)
	match launcher_phase:
		1:  # Pohjan valinta: vihreä snap-ruutu kursorissa
			_draw_grid_overlay(launcher_cursor)
			draw_rect(Rect2(launcher_cursor.x, launcher_cursor.y,
					float(LAUNCHER_SW), 2.0),
					Color(0.0, 1.0, 0.0, 0.7), false, 0.6)

		2:  # Katon valinta: pohja lukittu, x lukittu kursorille
			var locked_cursor := Vector2(launcher_start.x, launcher_cursor.y)
			# Pohjan piste (vihreä)
			draw_rect(Rect2(launcher_start.x, launcher_start.y,
					float(LAUNCHER_SW), 2.0),
					Color(0.0, 1.0, 0.0, 0.8), false, 0.8)
			# Kuilughost pohja → kursori
			var shaft_h := launcher_start.y - locked_cursor.y
			if shaft_h > 0.0:
				draw_rect(Rect2(launcher_start.x, locked_cursor.y,
						float(LAUNCHER_SW), shaft_h),
						Color(0.3, 0.5, 1.0, 0.3), true)
				draw_rect(Rect2(launcher_start.x, locked_cursor.y,
						float(LAUNCHER_SW), shaft_h),
						Color(0.3, 0.5, 1.0, 0.8), false, 0.6)
			# Katon piste (oranssi)
			draw_rect(Rect2(locked_cursor.x, locked_cursor.y,
					float(LAUNCHER_SW), 2.0),
					Color(1.0, 0.5, 0.0, 0.8), false, 0.8)

		3:  # Suunnan valinta: täysi kuilu + tykkiputki hiiren puolelle
			var shaft_h := launcher_start.y - launcher_end.y
			# Kuilu
			if shaft_h > 0.0:
				draw_rect(Rect2(launcher_end.x, launcher_end.y,
						float(LAUNCHER_SW), shaft_h),
						Color(0.3, 0.5, 1.0, 0.4), true)
				draw_rect(Rect2(launcher_end.x, launcher_end.y,
						float(LAUNCHER_SW), shaft_h),
						Color(0.3, 0.5, 1.0, 0.9), false, 0.8)
			# Tykkiputki hiiren puolelle
			var barrel_x: float
			if launcher_dir > 0.0:
				barrel_x = launcher_end.x + float(LAUNCHER_SW)
			else:
				barrel_x = launcher_end.x - float(LAUNCHER_BL)
			draw_rect(Rect2(barrel_x, launcher_end.y, float(LAUNCHER_BL), 2.0),
					Color(1.0, 0.7, 0.0, 0.9), true)
			# Suuntanuoli
			var arrow_start := Vector2(launcher_end.x + float(LAUNCHER_SW) * 0.5,
					launcher_end.y + 1.0)
			var arrow_end := arrow_start + Vector2(20.0 * launcher_dir, 0.0)
			draw_line(arrow_start, arrow_end, Color(1.0, 1.0, 0.0, 0.9), 0.8)
			draw_line(arrow_end, arrow_end + Vector2(-6.0 * launcher_dir, -3.0),
					Color(1.0, 1.0, 0.0, 0.9), 0.8)
			draw_line(arrow_end, arrow_end + Vector2(-6.0 * launcher_dir, 3.0),
					Color(1.0, 1.0, 0.0, 0.9), 0.8)
