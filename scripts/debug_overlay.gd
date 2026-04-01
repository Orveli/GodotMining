extends Control
# Debug-overlay — näyttää simulaation tilastot pelin päällä
# Paina F3 näyttääksesi/piilottaaksesi

# Viitteet
var pixel_world: Node
var physics_world: Node

var visible_overlay: bool = false
var update_interval: float = 0.5  # päivitys 2x/s
var timer: float = 0.0

# Kerätyt tiedot
var mat_counts: Dictionary = {}
var body_count: int = 0
var fps: float = 0.0
var frame_count: int = 0

# Materiaalinimet ID:n mukaan
const MAT_NAMES: Dictionary = {
	0: "EMPTY",
	1: "SAND",
	2: "WATER",
	3: "STONE",
	4: "WOOD",
	5: "FIRE",
	6: "OIL",
	7: "STEAM",
	8: "ASH",
	9: "WOOD_FALL",
	10: "GLASS",
}

# Materiaalien näyttövärit overlayssa
const MAT_COLORS: Dictionary = {
	0: Color(0.4, 0.4, 0.4),
	1: Color(0.9, 0.8, 0.4),
	2: Color(0.3, 0.5, 1.0),
	3: Color(0.6, 0.6, 0.6),
	4: Color(0.5, 0.3, 0.1),
	5: Color(1.0, 0.4, 0.0),
	6: Color(0.2, 0.15, 0.05),
	7: Color(0.7, 0.7, 0.85),
	8: Color(0.35, 0.35, 0.35),
	9: Color(0.65, 0.4, 0.15),
	10: Color(0.6, 0.85, 0.9),
}

const PANEL_MARGIN := Vector2(10.0, 10.0)
const LINE_HEIGHT := 18.0
const PANEL_W := 230.0
const FONT_SIZE := 13


func _ready() -> void:
	# Hae nodet automaattisesti — PixelWorld on sisarena Main:n alla
	pixel_world = get_node_or_null("../PixelWorld")
	if pixel_world == null:
		# Varmuuden vuoksi kokeile myös vanhempana
		pixel_world = get_node_or_null("../../PixelWorld")
	if pixel_world != null and pixel_world.has_property("physics_world"):
		physics_world = pixel_world.get("physics_world")

	visible = false
	z_index = 100
	# Estetään overlayltä inputin syöminen pelilogiikalta
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_F3:
		visible_overlay = not visible_overlay
		visible = visible_overlay
		queue_redraw()


func _process(delta: float) -> void:
	if not visible_overlay:
		return
	timer += delta
	if timer >= update_interval:
		timer = 0.0
		_collect_stats()
		queue_redraw()


func _collect_stats() -> void:
	fps = Engine.get_frames_per_second()

	if pixel_world == null:
		return

	# Luetaan frame_count suoraan pixel_worldilta
	frame_count = pixel_world.get("frame_count") if pixel_world.has_method("get") else 0

	# Laske materiaalit pixel_worldin grid-datasta
	var grid_data: PackedByteArray = pixel_world.get("grid")
	mat_counts.clear()
	if grid_data != null and grid_data.size() > 0:
		for i in grid_data.size():
			var m: int = grid_data[i]
			if mat_counts.has(m):
				mat_counts[m] += 1
			else:
				mat_counts[m] = 1

	# Hae body_count physics_worldista
	body_count = 0
	if physics_world == null and pixel_world != null:
		physics_world = pixel_world.get("physics_world")
	if physics_world != null:
		var bodies = physics_world.get("bodies")
		if bodies != null:
			body_count = bodies.size()


func _draw() -> void:
	if not visible_overlay:
		return

	# Laske rivimäärä: 3 perustietoriviä + materiaalit (vain ei-nollat)
	var non_empty_mats: Array = []
	for mat_id in mat_counts:
		if mat_id != 0 and mat_counts[mat_id] > 0:
			non_empty_mats.append(mat_id)
	non_empty_mats.sort()

	var row_count := 4 + non_empty_mats.size()  # fps, frame, bodies, tyhjä, materiaalit
	var panel_h := PANEL_MARGIN.y * 2 + row_count * LINE_HEIGHT + 4.0

	# Taustasuorakulmio — puoliläpinäkyvä musta
	var rect := Rect2(PANEL_MARGIN, Vector2(PANEL_W, panel_h))
	draw_rect(rect, Color(0, 0, 0, 0.75))
	draw_rect(rect, Color(0.4, 1.0, 0.4, 0.6), false)  # vihreä reunus

	var tx := PANEL_MARGIN.x + 6.0
	var ty := PANEL_MARGIN.y + LINE_HEIGHT

	# FPS
	var fps_color := Color(0.3, 1.0, 0.3) if fps >= 55 else (Color(1.0, 0.8, 0.0) if fps >= 30 else Color(1.0, 0.3, 0.3))
	draw_string(ThemeDB.fallback_font, Vector2(tx, ty), "FPS: %.0f" % fps, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, fps_color)
	ty += LINE_HEIGHT

	# Frame
	draw_string(ThemeDB.fallback_font, Vector2(tx, ty), "Frame: %d" % frame_count, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.9, 0.9, 0.9))
	ty += LINE_HEIGHT

	# Kappaleet
	draw_string(ThemeDB.fallback_font, Vector2(tx, ty), "Kappaleet: %d" % body_count, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(1.0, 0.7, 0.3))
	ty += LINE_HEIGHT + 4.0

	# Otsikko materiaaleille
	draw_string(ThemeDB.fallback_font, Vector2(tx, ty), "Materiaalit:", HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.7, 0.7, 0.7))
	ty += LINE_HEIGHT

	# Materiaalirivillä värilliset nimet ja pikselimäärä
	for mat_id in non_empty_mats:
		var count: int = mat_counts.get(mat_id, 0)
		var name_str: String = MAT_NAMES.get(mat_id, "MAT%d" % mat_id)
		var col: Color = MAT_COLORS.get(mat_id, Color(1, 0, 1))

		# Pienet väripisteet
		draw_rect(Rect2(Vector2(tx, ty - 10.0), Vector2(10.0, 10.0)), col)
		draw_string(ThemeDB.fallback_font, Vector2(tx + 14.0, ty), "%s: %d" % [name_str, count], HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, Color(0.9, 0.9, 0.9))
		ty += LINE_HEIGHT
