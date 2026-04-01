extends Control
# Debug-menu — säätää kaikkia pelin parametreja lennossa
# Avaa/sulje: F4

var pixel_world: Node

var _info_label: Label
const PANEL_W := 500.0
const PANEL_H := 620.0


func _ready() -> void:
	pixel_world = get_node_or_null("../PixelWorld")
	if pixel_world == null:
		pixel_world = get_node_or_null("../../PixelWorld")

	visible = false
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 200

	_build_ui()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			visible = false
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			visible = false
			get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F4:
			visible = not visible


func _process(_delta: float) -> void:
	if not visible or _info_label == null or pixel_world == null:
		return
	var fps := Engine.get_frames_per_second()
	var bodies := 0
	var pw_phys = pixel_world.get("physics_world")
	if pw_phys != null:
		var bods = pw_phys.get("bodies")
		if bods != null:
			bodies = bods.size()
	var gpu_t: float = 0.0
	var gpu_val = pixel_world.get("gpu_time_ms")
	if gpu_val != null:
		gpu_t = float(gpu_val)
	var chickens: int = 0
	if pixel_world.has_method("get_chicken_count"):
		chickens = pixel_world.get_chicken_count()
	var conv_arr = pixel_world.get("conveyors")
	var furn_arr = pixel_world.get("furnaces")
	var mine_arr = pixel_world.get("sand_mines")
	var laun_arr = pixel_world.get("launchers")
	var fly_arr = pixel_world.get("flying_pixels")
	_info_label.text = (
		"FPS: %d  GPU: %.1fms  Kappaleet: %d  Kanat: %d\n"
		+ "Hihnoja: %d  Uuneja: %d  Kaivoksia: %d  Linkoja: %d  Lentäviä: %d"
	) % [
		fps, gpu_t, bodies, chickens,
		conv_arr.size() if conv_arr != null else 0,
		furn_arr.size() if furn_arr != null else 0,
		mine_arr.size() if mine_arr != null else 0,
		laun_arr.size() if laun_arr != null else 0,
		fly_arr.size() if fly_arr != null else 0,
	]


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -PANEL_W * 0.5
	panel.offset_right = PANEL_W * 0.5
	panel.offset_top = -PANEL_H * 0.5
	panel.offset_bottom = PANEL_H * 0.5

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.08, 0.12, 0.97)
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.7, 1.0, 0.9)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 6)
	panel.add_child(outer)

	var title_row := HBoxContainer.new()
	outer.add_child(title_row)
	var title := Label.new()
	title.text = "DEBUG MENU"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)
	var hint := Label.new()
	hint.text = "[F4 / ESC]"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_row.add_child(hint)
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(30, 0)
	close_btn.pressed.connect(func(): visible = false)
	title_row.add_child(close_btn)

	outer.add_child(HSeparator.new())

	_info_label = Label.new()
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_info_label.text = "..."
	outer.add_child(_info_label)

	outer.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 380)
	outer.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 4)
	scroll.add_child(content)

	_section_simulaatio(content)
	_section_physics(content)
	_section_launcher(content)
	_section_worldgen(content)
	_section_game(content)

	outer.add_child(HSeparator.new())
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 8)
	outer.add_child(bottom)

	var save_btn := Button.new()
	save_btn.text = "Tallenna debug-tiedot"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.pressed.connect(_save_debug_info)
	bottom.add_child(save_btn)

	var shot_btn := Button.new()
	shot_btn.text = "Kuvakaappaus"
	shot_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	shot_btn.focus_mode = Control.FOCUS_NONE
	shot_btn.pressed.connect(_save_screenshot)
	bottom.add_child(shot_btn)


func _section_simulaatio(p: VBoxContainer) -> void:
	_header(p, "SIMULAATIO")
	_slider_row(p, "GPU passit", 2, 12, 1,
		func(): return float(pixel_world.get("gpu_passes")) if pixel_world != null else 4.0,
		func(v: float): pixel_world.set("gpu_passes", int(v)))
	_slider_row(p, "Logiikkaväli (frame)", 1, 10, 1,
		func(): return float(pixel_world.get("logic_frame_interval")) if pixel_world != null else 4.0,
		func(v: float): pixel_world.set("logic_frame_interval", int(v)))
	_slider_row(p, "Zoom smooth", 1.0, 20.0, 0.5,
		func(): return float(pixel_world.get("zoom_smooth")) if pixel_world != null else 8.0,
		func(v: float): pixel_world.set("zoom_smooth", v))


func _section_physics(p: VBoxContainer) -> void:
	_header(p, "FYSIIKKA")
	_slider_row(p, "Lentävien painovoima (px/s²)", 20.0, 600.0, 5.0,
		func(): return float(pixel_world.get("flying_gravity")) if pixel_world != null else 140.0,
		func(v: float): pixel_world.set("flying_gravity", v))
	_slider_row(p, "Lentävien max määrä", 50, 2000, 50,
		func(): return float(pixel_world.get("flying_max_count")) if pixel_world != null else 300.0,
		func(v: float): pixel_world.set("flying_max_count", int(v)))
	_slider_row(p, "GravGun säde (px)", 10, 150, 5,
		func(): return float(pixel_world.get("grav_gun_radius")) if pixel_world != null else 40.0,
		func(v: float): pixel_world.set("grav_gun_radius", int(v)))
	_slider_row(p, "GravGun vakuumi säde (px)", 20, 250, 10,
		func(): return float(pixel_world.get("grav_gun_vacuum_radius")) if pixel_world != null else 80.0,
		func(v: float): pixel_world.set("grav_gun_vacuum_radius", int(v)))
	_slider_row(p, "GravGun kappalevoima", 0.5, 15.0, 0.5,
		func(): return float(pixel_world.get("grav_gun_body_strength")) if pixel_world != null else 3.0,
		func(v: float): pixel_world.set("grav_gun_body_strength", v))


func _section_launcher(p: VBoxContainer) -> void:
	_header(p, "LINKO")
	_slider_row(p, "Ampumisnopeus (px/s)", 30.0, 500.0, 10.0,
		func(): return float(pixel_world.get("launcher_launch_speed")) if pixel_world != null else 120.0,
		func(v: float):
			pixel_world.set("launcher_launch_speed", v)
			if pixel_world.has_method("update_launcher_settings"):
				pixel_world.update_launcher_settings())
	_slider_row(p, "Ampumakulma (°)", -88.0, -5.0, 1.0,
		func(): return float(pixel_world.get("launcher_launch_angle")) if pixel_world != null else -45.0,
		func(v: float):
			pixel_world.set("launcher_launch_angle", v)
			if pixel_world.has_method("update_launcher_settings"):
				pixel_world.update_launcher_settings())
	_slider_row(p, "Kuilunopeus (px/s)", 30.0, 500.0, 10.0,
		func(): return float(pixel_world.get("launcher_shaft_speed")) if pixel_world != null else 180.0,
		func(v: float):
			pixel_world.set("launcher_shaft_speed", v)
			if pixel_world.has_method("update_launcher_settings"):
				pixel_world.update_launcher_settings())
	_slider_row(p, "Imuviive (s)", 0.01, 0.5, 0.01,
		func(): return float(pixel_world.get("launcher_intake_cooldown")) if pixel_world != null else 0.08,
		func(v: float):
			pixel_world.set("launcher_intake_cooldown", v)
			if pixel_world.has_method("update_launcher_settings"):
				pixel_world.update_launcher_settings())


func _section_worldgen(p: VBoxContainer) -> void:
	_header(p, "MAAILMANGENEROINTI (vaikuttaa seuraavaan [R])")
	_slider_row(p, "Worm-taajuus", 0.003, 0.06, 0.001,
		func(): return WorldGen.worm_freq,
		func(v: float): WorldGen.worm_freq = v)
	_slider_row(p, "Worm-kynnys", 0.10, 0.70, 0.01,
		func(): return WorldGen.worm_threshold,
		func(v: float): WorldGen.worm_threshold = v)
	_slider_row(p, "Kammiotaajuus", 0.003, 0.04, 0.001,
		func(): return WorldGen.chamber_freq,
		func(v: float): WorldGen.chamber_freq = v)
	_slider_row(p, "Kammiokynnys", 0.10, 0.70, 0.01,
		func(): return WorldGen.chamber_threshold,
		func(v: float): WorldGen.chamber_threshold = v)
	_slider_row(p, "Pintataajuus", 0.003, 0.08, 0.001,
		func(): return WorldGen.surface_freq,
		func(v: float): WorldGen.surface_freq = v)
	_slider_row(p, "Puutodennäköisyys", 0.0, 0.5, 0.01,
		func(): return WorldGen.tree_chance,
		func(v: float): WorldGen.tree_chance = v)
	_slider_row(p, "Hiekka-kynnys", 0.3, 0.95, 0.01,
		func(): return WorldGen.sand_threshold,
		func(v: float): WorldGen.sand_threshold = v)
	_slider_row(p, "Vesi-kynnys", 0.3, 0.99, 0.01,
		func(): return WorldGen.water_threshold,
		func(v: float): WorldGen.water_threshold = v)
	_slider_row(p, "Öljy-kynnys", 0.4, 0.99, 0.01,
		func(): return WorldGen.oil_threshold,
		func(v: float): WorldGen.oil_threshold = v)
	_slider_row(p, "Rautamalmi-taajuus", 0.03, 0.4, 0.01,
		func(): return WorldGen.iron_freq,
		func(v: float): WorldGen.iron_freq = v)
	_slider_row(p, "Kultamalmi-taajuus", 0.03, 0.4, 0.01,
		func(): return WorldGen.gold_freq,
		func(v: float): WorldGen.gold_freq = v)
	var regen_btn := Button.new()
	regen_btn.text = "Generoi uudelleen näillä asetuksilla"
	regen_btn.focus_mode = Control.FOCUS_NONE
	regen_btn.add_theme_font_size_override("font_size", 13)
	regen_btn.pressed.connect(func():
		if pixel_world != null and pixel_world.has_method("regenerate_world"):
			pixel_world.regenerate_world())
	p.add_child(regen_btn)


func _section_game(p: VBoxContainer) -> void:
	_header(p, "PELI")
	_toggle_row(p, "Ääretön raha",
		func(): return bool(pixel_world.get("infinite_money")) if pixel_world != null else false,
		func(v: bool): pixel_world.set("infinite_money", v))
	p.add_child(_make_btn("Poista kaikki rakennukset", _delete_all_buildings))
	p.add_child(_make_btn("Tapa kaikki kanat", _kill_all_chickens))
	p.add_child(_make_btn("Tyhjennä kenttä [C]", func():
		if pixel_world != null and pixel_world.has_method("clear_world"):
			pixel_world.clear_world()))
	p.add_child(_make_btn("Uusi maailma [R]", func():
		if pixel_world != null and pixel_world.has_method("regenerate_world"):
			pixel_world.regenerate_world()))


func _header(parent: VBoxContainer, text: String) -> void:
	parent.add_child(HSeparator.new())
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	parent.add_child(lbl)


func _slider_row(parent: VBoxContainer, label: String, min_v: float, max_v: float,
		step_v: float, getter: Callable, setter: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.custom_minimum_size = Vector2(200, 0)
	lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	lbl.clip_text = true
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step_v
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.focus_mode = Control.FOCUS_NONE
	slider.value = getter.call()
	row.add_child(slider)

	var val_lbl := Label.new()
	val_lbl.add_theme_font_size_override("font_size", 12)
	val_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	val_lbl.custom_minimum_size = Vector2(52, 0)
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var fmt := "%.3f" if step_v < 0.1 else ("%.1f" if step_v < 1.0 else "%d")
	val_lbl.text = fmt % slider.value
	row.add_child(val_lbl)

	slider.value_changed.connect(func(v: float):
		setter.call(v)
		val_lbl.text = fmt % v)


func _toggle_row(parent: VBoxContainer, label: String, getter: Callable,
		setter: Callable) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var lbl := Label.new()
	lbl.text = label
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var cb := CheckBox.new()
	cb.button_pressed = getter.call()
	cb.focus_mode = Control.FOCUS_NONE
	cb.toggled.connect(func(v: bool): setter.call(v))
	row.add_child(cb)


func _make_btn(label: String, cb: Callable) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(cb)
	return btn


func _kill_all_chickens() -> void:
	if pixel_world == null:
		return
	var chk = pixel_world.get("chickens")
	if chk == null:
		return
	for c in chk.duplicate():
		if c != null and c.has_method("die"):
			c.die()
	chk.clear()


func _delete_all_buildings() -> void:
	if pixel_world == null:
		return
	var grid_data = pixel_world.get("grid")
	for arr_name in ["launchers", "conveyors", "furnaces", "sand_mines"]:
		var arr = pixel_world.get(arr_name)
		if arr == null:
			continue
		for obj in arr.duplicate():
			if obj == null:
				continue
			if obj.has_method("remove_from_world") and grid_data != null:
				obj.remove_from_world(grid_data)
			elif obj is Node:
				obj.queue_free()
		arr.clear()
	pixel_world.set("building_pixels", {})
	if pixel_world.has_method("_mark_grid_dirty"):
		pixel_world._mark_grid_dirty()


func _save_debug_info() -> void:
	if pixel_world == null:
		return
	var data := {
		"timestamp": Time.get_datetime_string_from_system(),
		"fps": Engine.get_frames_per_second(),
		"gpu_time_ms": pixel_world.get("gpu_time_ms"),
		"frame_count": pixel_world.get("frame_count"),
		"sim_speed": pixel_world.get("sim_speed"),
		"gpu_passes": pixel_world.get("gpu_passes"),
		"logic_frame_interval": pixel_world.get("logic_frame_interval"),
		"flying_gravity": pixel_world.get("flying_gravity"),
		"flying_max_count": pixel_world.get("flying_max_count"),
		"grav_gun_radius": pixel_world.get("grav_gun_radius"),
		"grav_gun_vacuum_radius": pixel_world.get("grav_gun_vacuum_radius"),
		"grav_gun_body_strength": pixel_world.get("grav_gun_body_strength"),
		"zoom_smooth": pixel_world.get("zoom_smooth"),
		"infinite_money": pixel_world.get("infinite_money"),
		"launcher_launch_speed": pixel_world.get("launcher_launch_speed"),
		"launcher_launch_angle": pixel_world.get("launcher_launch_angle"),
		"launcher_shaft_speed": pixel_world.get("launcher_shaft_speed"),
		"launcher_intake_cooldown": pixel_world.get("launcher_intake_cooldown"),
		"worldgen": {
			"worm_freq": WorldGen.worm_freq,
			"worm_threshold": WorldGen.worm_threshold,
			"chamber_freq": WorldGen.chamber_freq,
			"chamber_threshold": WorldGen.chamber_threshold,
			"surface_freq": WorldGen.surface_freq,
			"tree_chance": WorldGen.tree_chance,
			"sand_threshold": WorldGen.sand_threshold,
			"water_threshold": WorldGen.water_threshold,
			"oil_threshold": WorldGen.oil_threshold,
			"iron_freq": WorldGen.iron_freq,
			"gold_freq": WorldGen.gold_freq,
		},
	}
	var json_str := JSON.stringify(data, "  ")
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://debug_%s.json" % ts
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string(json_str)
		f.close()
		print("Debug-tiedot tallennettu: %s" % path)
	else:
		push_error("Ei voitu tallentaa: %s" % path)


func _save_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var ts := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var path := "user://screenshot_%s.png" % ts
	img.save_png(path)
	print("Kuvakaappaus tallennettu: %s" % path)
