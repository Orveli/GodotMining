extends Control
# Debug-menu — säätää kaikkia pelin parametreja lennossa
# Avaa/sulje: F4
# Rakenne: koko ruudun levyinen yläpalkki (~280px), ei harmaata taustaa koko ruudulla

var pixel_world: Node

var _info_label: Label

var _worldgen_preview_texture: ImageTexture
var _worldgen_preview_rect: TextureRect
var _worldgen_depth_texture: ImageTexture
var _worldgen_depth_rect: TextureRect

const BAR_H := 420.0


func _ready() -> void:
	# DebugMenu on UI CanvasLayerin lapsi → PixelWorld on kaksi tasoa ylempänä
	pixel_world = get_node_or_null("../../PixelWorld")

	visible = false
	# Aloitetaan game UI -palkin (50px) alapuolelta jotta yläpalkit eivät peitä toisiaan
	set_anchors_preset(Control.PRESET_TOP_WIDE)
	offset_top = 50.0
	offset_bottom = 50.0 + BAR_H
	custom_minimum_size = Vector2(0, BAR_H)
	mouse_filter = Control.MOUSE_FILTER_PASS
	z_index = 10  # Päälle muista UI-elementeistä samalla layerilla

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
		elif event.keycode == KEY_P:
			# Paletinvaihto: DEFAULT ↔ DEEP
			if pixel_world == null:
				return
			if pixel_world.current_palette == pixel_world.PALETTE_DEFAULT:
				pixel_world.set_palette(pixel_world.PALETTE_DEEP)
				print("Paletti: DEEP")
			else:
				pixel_world.set_palette(pixel_world.PALETTE_DEFAULT)
				print("Paletti: DEFAULT")
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
	var conv_arr = pixel_world.get("conveyors")
	var furn_arr = pixel_world.get("furnaces")
	var mine_arr = pixel_world.get("sand_mines")
	var laun_arr = pixel_world.get("launchers")
	var fly_arr = pixel_world.get("flying_pixels")
	_info_label.text = (
		"FPS: %d   GPU: %.1fms   Kappaleet: %d   "
		+ "Hihnoja: %d   Uuneja: %d   Kaivoksia: %d   Linkoja: %d   Lentäviä: %d"
	) % [
		fps, gpu_t, bodies,
		conv_arr.size() if conv_arr != null else 0,
		furn_arr.size() if furn_arr != null else 0,
		mine_arr.size() if mine_arr != null else 0,
		laun_arr.size() if laun_arr != null else 0,
		fly_arr.size() if fly_arr != null else 0,
	]


func _build_ui() -> void:
	# PanelContainer — tumma yläpalkki, syö hiiri-inputin palkin alueella
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.10, 0.97)
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.7, 1.0, 0.9)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 6
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	panel.add_child(outer)

	# ── Ylärivi: DEBUG | infoteksti | F4/ESC | ✕ ──
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 8)
	top_row.custom_minimum_size = Vector2(0, 26)
	outer.add_child(top_row)

	var debug_lbl := Label.new()
	debug_lbl.text = "DEBUG"
	debug_lbl.add_theme_font_size_override("font_size", 14)
	debug_lbl.add_theme_color_override("font_color", Color(0.3, 0.85, 1.0))
	debug_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(debug_lbl)

	var sep_lbl := Label.new()
	sep_lbl.text = "|"
	sep_lbl.add_theme_font_size_override("font_size", 14)
	sep_lbl.add_theme_color_override("font_color", Color(0.4, 0.4, 0.5))
	sep_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(sep_lbl)

	_info_label = Label.new()
	_info_label.text = "..."
	_info_label.add_theme_font_size_override("font_size", 12)
	_info_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.7))
	_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_info_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_info_label.clip_text = true
	top_row.add_child(_info_label)

	var hint_lbl := Label.new()
	hint_lbl.text = "F4 / ESC"
	hint_lbl.add_theme_font_size_override("font_size", 11)
	hint_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top_row.add_child(hint_lbl)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(28, 0)
	close_btn.add_theme_font_size_override("font_size", 13)
	close_btn.pressed.connect(func(): visible = false)
	top_row.add_child(close_btn)

	outer.add_child(HSeparator.new())

	# ── TabContainer joka täyttää loppukorkeuden ──
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_theme_font_size_override("font_size", 12)
	outer.add_child(tabs)

	_tab_simulaatio(tabs)
	_tab_physics(tabs)
	_tab_launcher(tabs)
	_tab_worldgen(tabs)
	_tab_game(tabs)


# Apufunktio: luo ScrollContainer + VBoxContainer tabi-sisällöksi
func _make_tab_scroll(tabs: TabContainer, title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	tabs.add_child(scroll)
	return vbox


# Alaotsikko ilman erillistä HSeparatoria
func _subheader(parent: VBoxContainer, text: String) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
	parent.add_child(lbl)


func _tab_simulaatio(tabs: TabContainer) -> void:
	var p := _make_tab_scroll(tabs, "Simulaatio")
	_subheader(p, "GPU & ajoitus")
	_slider_row(p, "GPU passit", 2, 12, 1,
		func(): return float(pixel_world.get("gpu_passes")) if pixel_world != null else 4.0,
		func(v: float): pixel_world.set("gpu_passes", int(v)))
	_slider_row(p, "Logiikkaväli (frame)", 1, 10, 1,
		func(): return float(pixel_world.get("logic_frame_interval")) if pixel_world != null else 4.0,
		func(v: float): pixel_world.set("logic_frame_interval", int(v)))
	_slider_row(p, "Zoom smooth", 1.0, 20.0, 0.5,
		func(): return float(pixel_world.get("zoom_smooth")) if pixel_world != null else 8.0,
		func(v: float): pixel_world.set("zoom_smooth", v))


func _tab_physics(tabs: TabContainer) -> void:
	var p := _make_tab_scroll(tabs, "Fysiikka")
	_subheader(p, "Lentävät pikselit")
	_slider_row(p, "Lentävien painovoima (px/s²)", 20.0, 600.0, 5.0,
		func(): return float(pixel_world.get("flying_gravity")) if pixel_world != null else 140.0,
		func(v: float): pixel_world.set("flying_gravity", v))
	_slider_row(p, "Lentävien max määrä", 50, 2000, 50,
		func(): return float(pixel_world.get("flying_max_count")) if pixel_world != null else 300.0,
		func(v: float): pixel_world.set("flying_max_count", int(v)))
	_subheader(p, "GravGun")
	_slider_row(p, "GravGun säde (px)", 10, 150, 5,
		func(): return float(pixel_world.get("grav_gun_radius")) if pixel_world != null else 40.0,
		func(v: float): pixel_world.set("grav_gun_radius", int(v)))
	_slider_row(p, "GravGun vakuumi säde (px)", 20, 250, 10,
		func(): return float(pixel_world.get("grav_gun_vacuum_radius")) if pixel_world != null else 80.0,
		func(v: float): pixel_world.set("grav_gun_vacuum_radius", int(v)))
	_slider_row(p, "GravGun kappalevoima", 0.5, 15.0, 0.5,
		func(): return float(pixel_world.get("grav_gun_body_strength")) if pixel_world != null else 3.0,
		func(v: float): pixel_world.set("grav_gun_body_strength", v))


func _tab_launcher(tabs: TabContainer) -> void:
	var p := _make_tab_scroll(tabs, "Linko")
	_subheader(p, "Laukaisuasetukset")
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


func _tab_worldgen(tabs: TabContainer) -> void:
	var p := _make_tab_scroll(tabs, "Maailmangenerointi")

	# ── Preview-alue ──
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 6)
	p.add_child(preview_row)

	_worldgen_preview_rect = TextureRect.new()
	_worldgen_preview_rect.custom_minimum_size = Vector2(320, 90)
	_worldgen_preview_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_worldgen_preview_rect.stretch_mode = TextureRect.STRETCH_SCALE
	preview_row.add_child(_worldgen_preview_rect)

	_worldgen_depth_rect = TextureRect.new()
	_worldgen_depth_rect.custom_minimum_size = Vector2(50, 90)
	_worldgen_depth_rect.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_worldgen_depth_rect.stretch_mode = TextureRect.STRETCH_SCALE
	preview_row.add_child(_worldgen_depth_rect)

	# Legenda
	var legend_vbox := VBoxContainer.new()
	legend_vbox.add_theme_constant_override("separation", 2)
	legend_vbox.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	preview_row.add_child(legend_vbox)
	var legend_items := [
		["■ Hiili", Color(0.12, 0.12, 0.14)],
		["■ Rauta", Color(0.70, 0.38, 0.22)],
		["■ Kulta", Color(0.86, 0.70, 0.10)],
		["■ Öljy",  Color(0.15, 0.11, 0.04)],
		["■ Hiekka",Color(0.90, 0.78, 0.38)],
		["── Pinta",Color(0.3, 0.85, 0.3)],
	]
	for item in legend_items:
		var lbl := Label.new()
		lbl.text = item[0]
		lbl.add_theme_font_size_override("font_size", 11)
		lbl.add_theme_color_override("font_color", item[1])
		legend_vbox.add_child(lbl)

	# Napit
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)
	p.add_child(btn_row)

	var preview_btn := Button.new()
	preview_btn.text = "Päivitä preview"
	preview_btn.focus_mode = Control.FOCUS_NONE
	preview_btn.add_theme_font_size_override("font_size", 12)
	preview_btn.pressed.connect(_render_worldgen_preview)
	btn_row.add_child(preview_btn)

	var regen_btn := Button.new()
	regen_btn.text = "Generoi uudelleen näillä asetuksilla"
	regen_btn.focus_mode = Control.FOCUS_NONE
	regen_btn.add_theme_font_size_override("font_size", 12)
	regen_btn.pressed.connect(func():
		if pixel_world != null and pixel_world.has_method("regenerate_world"):
			pixel_world.regenerate_world())
	btn_row.add_child(regen_btn)

	# ── Pintakerros ──
	_subheader(p, "Pintakerros")
	_slider_row(p, "Pinnan korkeus (suhde)", 0.25, 0.65, 0.01,
		func(): return WorldGen.surface_height_ratio,
		func(v: float): WorldGen.surface_height_ratio = v)
	_slider_row(p, "Multakerros paksuus (px)", 1.0, 20.0, 1.0,
		func(): return float(WorldGen.dirt_thickness),
		func(v: float): WorldGen.dirt_thickness = int(v))

	# ── Hiekkadyynit ──
	_subheader(p, "Hiekkadyynit")
	_slider_row(p, "Dyynikynnys (pienempi = enemmän)", 0.1, 0.85, 0.01,
		func(): return WorldGen.dune_threshold,
		func(v: float): WorldGen.dune_threshold = v)
	_slider_row(p, "Dyynin max korkeus (px)", 1.0, 15.0, 1.0,
		func(): return float(WorldGen.dune_max_height),
		func(v: float): WorldGen.dune_max_height = int(v))
	_slider_row(p, "Hiekkataskunkirja (kpl)", 1, 12, 1,
		func(): return float(WorldGen.sand_count),
		func(v: float): WorldGen.sand_count = int(v))
	_slider_row(p, "Hiekkatasku syvyys min", 0.0, 0.4, 0.01,
		func(): return WorldGen.sand_depth,
		func(v: float): WorldGen.sand_depth = v)
	_slider_row(p, "Hiekkatasku syvyys max", 0.1, 0.6, 0.01,
		func(): return WorldGen.sand_depth_max,
		func(v: float): WorldGen.sand_depth_max = v)

	# ── Järvet ──
	_subheader(p, "Järvet")
	_slider_row(p, "Järvien määrä", 0.0, 8.0, 1.0,
		func(): return float(WorldGen.lake_count),
		func(v: float): WorldGen.lake_count = int(v))
	_slider_row(p, "Leveys min (px)", 20.0, 150.0, 5.0,
		func(): return float(WorldGen.lake_w_min),
		func(v: float): WorldGen.lake_w_min = int(v))
	_slider_row(p, "Leveys max (px)", 60.0, 250.0, 5.0,
		func(): return float(WorldGen.lake_w_max),
		func(v: float): WorldGen.lake_w_max = int(v))
	_slider_row(p, "Syvyys min (px)", 5.0, 60.0, 5.0,
		func(): return float(WorldGen.lake_d_min),
		func(v: float): WorldGen.lake_d_min = int(v))
	_slider_row(p, "Syvyys max (px)", 15.0, 100.0, 5.0,
		func(): return float(WorldGen.lake_d_max),
		func(v: float): WorldGen.lake_d_max = int(v))

	# ── Kerrosrakenne ──
	_subheader(p, "Kerrosrakenne — syvyys min → max (0=pinta, 1=pohja)")
	_slider_row(p, "Hiili min", 0.0, 0.5, 0.01,
		func(): return WorldGen.coal_depth,
		func(v: float): WorldGen.coal_depth = v)
	_slider_row(p, "Hiili max", 0.1, 1.0, 0.01,
		func(): return WorldGen.coal_depth_max,
		func(v: float): WorldGen.coal_depth_max = v)
	_slider_row(p, "Rauta min", 0.0, 0.7, 0.01,
		func(): return WorldGen.iron_depth,
		func(v: float): WorldGen.iron_depth = v)
	_slider_row(p, "Rauta max", 0.1, 1.0, 0.01,
		func(): return WorldGen.iron_depth_max,
		func(v: float): WorldGen.iron_depth_max = v)
	_slider_row(p, "Kulta min", 0.1, 0.9, 0.01,
		func(): return WorldGen.gold_depth,
		func(v: float): WorldGen.gold_depth = v)
	_slider_row(p, "Kulta max", 0.2, 1.0, 0.01,
		func(): return WorldGen.gold_depth_max,
		func(v: float): WorldGen.gold_depth_max = v)
	_slider_row(p, "Öljy min", 0.2, 0.9, 0.01,
		func(): return WorldGen.oil_depth,
		func(v: float): WorldGen.oil_depth = v)
	_slider_row(p, "Öljy max", 0.3, 1.0, 0.01,
		func(): return WorldGen.oil_depth_max,
		func(v: float): WorldGen.oil_depth_max = v)

	# ── Kertymien lukumäärä ──
	_subheader(p, "Kertymien lukumäärä")
	_slider_row(p, "Hiili (kpl)", 1, 16, 1,
		func(): return float(WorldGen.coal_count),
		func(v: float): WorldGen.coal_count = int(v))
	_slider_row(p, "Rauta (kpl)", 1, 12, 1,
		func(): return float(WorldGen.iron_count),
		func(v: float): WorldGen.iron_count = int(v))
	_slider_row(p, "Kulta (kpl)", 1, 10, 1,
		func(): return float(WorldGen.gold_count),
		func(v: float): WorldGen.gold_count = int(v))
	_slider_row(p, "Öljy (kpl)", 1, 10, 1,
		func(): return float(WorldGen.oil_count),
		func(v: float): WorldGen.oil_count = int(v))

	# ── Kertymien koko ──
	_subheader(p, "Kertymien säde pinta → syvä (px)")
	_slider_row(p, "Hiili pinta r", 2.0, 20.0, 1.0,
		func(): return WorldGen.coal_r_min,
		func(v: float): WorldGen.coal_r_min = v)
	_slider_row(p, "Hiili syvä r", 5.0, 40.0, 1.0,
		func(): return WorldGen.coal_r_max,
		func(v: float): WorldGen.coal_r_max = v)
	_slider_row(p, "Rauta pinta r", 2.0, 18.0, 1.0,
		func(): return WorldGen.iron_r_min,
		func(v: float): WorldGen.iron_r_min = v)
	_slider_row(p, "Rauta syvä r", 5.0, 35.0, 1.0,
		func(): return WorldGen.iron_r_max,
		func(v: float): WorldGen.iron_r_max = v)
	_slider_row(p, "Kulta pinta r", 2.0, 14.0, 1.0,
		func(): return WorldGen.gold_r_min,
		func(v: float): WorldGen.gold_r_min = v)
	_slider_row(p, "Kulta syvä r", 3.0, 28.0, 1.0,
		func(): return WorldGen.gold_r_max,
		func(v: float): WorldGen.gold_r_max = v)
	_slider_row(p, "Kokovaihtelu (±%)", 0.0, 0.8, 0.05,
		func(): return WorldGen.size_variance,
		func(v: float): WorldGen.size_variance = v)
	_slider_row(p, "Reunaepäsäännöllisyys", 0.0, 0.8, 0.05,
		func(): return WorldGen.perturb_strength,
		func(v: float): WorldGen.perturb_strength = v)
	_slider_row(p, "Puutodennäköisyys", 0.0, 0.5, 0.01,
		func(): return WorldGen.tree_chance,
		func(v: float): WorldGen.tree_chance = v)

	# ── Luolastot ──
	_subheader(p, "Luolastot (domain-warped noise)")
	_slider_row(p, "Threshold pinta (pienempi=vähemmän)", 0.01, 0.20, 0.005,
		func(): return WorldGen.cave_threshold_min,
		func(v: float): WorldGen.cave_threshold_min = v)
	_slider_row(p, "Threshold pohja (pienempi=vähemmän)", 0.01, 0.30, 0.005,
		func(): return WorldGen.cave_threshold_max,
		func(v: float): WorldGen.cave_threshold_max = v)
	_slider_row(p, "Warp-voima (isompi=enemmän mutkia)", 5.0, 100.0, 1.0,
		func(): return WorldGen.cave_warp_str,
		func(v: float): WorldGen.cave_warp_str = v)


func _tab_game(tabs: TabContainer) -> void:
	var p := _make_tab_scroll(tabs, "Peli")
	_subheader(p, "Pelin tila")
	_toggle_row(p, "Ääretön raha",
		func(): return bool(pixel_world.get("infinite_money")) if pixel_world != null else false,
		func(v: bool): pixel_world.set("infinite_money", v))
	p.add_child(_make_btn("Poista kaikki rakennukset", _delete_all_buildings))
	p.add_child(_make_btn("Tyhjennä kenttä [C]", func():
		if pixel_world != null and pixel_world.has_method("clear_world"):
			pixel_world.clear_world()))
	p.add_child(_make_btn("Uusi maailma [R]", func():
		if pixel_world != null and pixel_world.has_method("regenerate_world"):
			pixel_world.regenerate_world()))

	_subheader(p, "Tallentaminen")
	p.add_child(_make_btn("Tallenna debug-tiedot", _save_debug_info))
	p.add_child(_make_btn("Kuvakaappaus", _save_screenshot))


func _render_worldgen_preview() -> void:
	var pw := 160
	var ph := 90
	var grid := PackedByteArray()
	grid.resize(pw * ph)
	var seeds := PackedByteArray()
	seeds.resize(pw * ph)
	WorldGen.generate(grid, seeds, pw, ph)

	# Materiaalivärit
	var mat_col: Array[Color] = []
	mat_col.resize(256)
	mat_col.fill(Color(0.6, 0.0, 0.8))  # tuntematon = magenta
	mat_col[0]  = Color(0.07, 0.06, 0.12)  # EMPTY
	mat_col[1]  = Color(0.90, 0.78, 0.38)  # SAND
	mat_col[2]  = Color(0.19, 0.47, 0.85)  # WATER
	mat_col[3]  = Color(0.46, 0.46, 0.50)  # STONE
	mat_col[4]  = Color(0.47, 0.31, 0.15)  # WOOD
	mat_col[5]  = Color(1.00, 0.39, 0.04)  # FIRE
	mat_col[6]  = Color(0.15, 0.11, 0.04)  # OIL
	mat_col[7]  = Color(0.78, 0.80, 0.86)  # STEAM
	mat_col[8]  = Color(0.24, 0.24, 0.26)  # ASH
	mat_col[9]  = Color(0.54, 0.37, 0.19)  # WOOD_FALLING
	mat_col[11] = Color(0.39, 0.25, 0.13)  # DIRT
	mat_col[12] = Color(0.70, 0.38, 0.22)  # IRON_ORE
	mat_col[13] = Color(0.86, 0.70, 0.10)  # GOLD_ORE
	mat_col[16] = Color(0.12, 0.12, 0.14)  # COAL

	var img := Image.create(pw, ph, false, Image.FORMAT_RGB8)
	for y in ph:
		for x in pw:
			var m: int = grid[y * pw + x]
			img.set_pixel(x, y, mat_col[m])

	if _worldgen_preview_texture == null:
		_worldgen_preview_texture = ImageTexture.create_from_image(img)
	else:
		_worldgen_preview_texture.update(img)
	if _worldgen_preview_rect != null:
		_worldgen_preview_rect.texture = _worldgen_preview_texture

	# Syvyysdiagrammi (50×90): näyttää kerrokset
	_render_depth_diagram()


func _render_depth_diagram() -> void:
	var dw := 50
	var dh := 90
	var img := Image.create(dw, dh, false, Image.FORMAT_RGB8)
	img.fill(Color(0.05, 0.05, 0.08))

	var surf_y := int(WorldGen.surface_height_ratio * float(dh))
	var depth_h := dh - surf_y

	# Resurssit: [väri, min_depth, max_depth]
	var resources := [
		[Color(0.12, 0.12, 0.14), WorldGen.coal_depth,  WorldGen.coal_depth_max],   # hiili
		[Color(0.70, 0.38, 0.22), WorldGen.iron_depth,  WorldGen.iron_depth_max],   # rauta
		[Color(0.86, 0.70, 0.10), WorldGen.gold_depth,  WorldGen.gold_depth_max],   # kulta
		[Color(0.15, 0.11, 0.04), WorldGen.oil_depth,   WorldGen.oil_depth_max],    # öljy
		[Color(0.90, 0.78, 0.38), WorldGen.sand_depth,  WorldGen.sand_depth_max],   # hiekka
	]

	var col_w := dw / resources.size()
	for i in resources.size():
		var col: Color = resources[i][0]
		var min_d: float = resources[i][1]
		var max_d: float = resources[i][2]
		var y_top := surf_y + int(min_d * float(depth_h))
		var y_bot := surf_y + int(max_d * float(depth_h))
		y_top = clampi(y_top, 0, dh - 1)
		y_bot = clampi(y_bot, 0, dh - 1)
		var x0 := i * col_w + 1
		var x1 := mini((i + 1) * col_w - 1, dw - 1)
		for y in range(y_top, y_bot + 1):
			for x in range(x0, x1 + 1):
				img.set_pixel(x, y, col)

	# Pintaviiva
	for x in dw:
		img.set_pixel(x, surf_y, Color(0.3, 0.85, 0.3))

	if _worldgen_depth_texture == null:
		_worldgen_depth_texture = ImageTexture.create_from_image(img)
	else:
		_worldgen_depth_texture.update(img)
	if _worldgen_depth_rect != null:
		_worldgen_depth_rect.texture = _worldgen_depth_texture


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
			"coal_count": WorldGen.coal_count,
			"iron_count": WorldGen.iron_count,
			"gold_count": WorldGen.gold_count,
			"oil_count": WorldGen.oil_count,
			"coal_r_max": WorldGen.coal_r_max,
			"coal_r_min": WorldGen.coal_r_min,
			"iron_r_max": WorldGen.iron_r_max,
			"iron_r_min": WorldGen.iron_r_min,
			"gold_r_max": WorldGen.gold_r_max,
			"gold_r_min": WorldGen.gold_r_min,
			"oil_r_max": WorldGen.oil_r_max,
			"oil_r_min": WorldGen.oil_r_min,
			"coal_depth": WorldGen.coal_depth,
			"iron_depth": WorldGen.iron_depth,
			"gold_depth": WorldGen.gold_depth,
			"oil_depth": WorldGen.oil_depth,
			"perturb_strength": WorldGen.perturb_strength,
			"tree_chance": WorldGen.tree_chance,
			"surface_height_ratio": WorldGen.surface_height_ratio,
			"dirt_thickness": WorldGen.dirt_thickness,
			"lake_count": WorldGen.lake_count,
			"lake_w_min": WorldGen.lake_w_min,
			"lake_w_max": WorldGen.lake_w_max,
			"lake_d_min": WorldGen.lake_d_min,
			"lake_d_max": WorldGen.lake_d_max,
			"dune_threshold": WorldGen.dune_threshold,
			"dune_max_height": WorldGen.dune_max_height,
			"coal_depth_max": WorldGen.coal_depth_max,
			"iron_depth_max": WorldGen.iron_depth_max,
			"gold_depth_max": WorldGen.gold_depth_max,
			"oil_depth_max": WorldGen.oil_depth_max,
			"sand_depth_max": WorldGen.sand_depth_max,
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
