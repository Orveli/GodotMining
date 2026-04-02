extends PanelContainer

@onready var pixel_world: TextureRect = get_node("../../PixelWorld")

# Materiaalit-napit — tallennetaan viitteiksi korostusta varten
var btn_stone: Button
var btn_stone_dynamic: Button

# Pensseli
var brush_slider: HSlider
var brush_label: Label

# FPS-teksti
var fps_label: Label

# Rakennusnapit (luodaan ohjelmallisesti)
var build_panel: PanelContainer      # erillinen paneeli palkin alla
var btn_spawner: Button
var btn_conveyor: Button
var btn_sling: Button
var btn_wall: Button
var btn_sand_mine_build: Button
var btn_furnace_build: Button
var btn_money_exit_build: Button
var btn_crusher_build: Button
var build_buttons: Array[Button] = []  # kaikki rakennus-napit korostusta varten

# Raha-näyttö
var money_label: Label

# Speed-napit
var speed_buttons: Array[Button] = []
const SPEED_VALUES: Array[float] = [1.0, 4.0, 8.0, 16.0]
const SPEED_LABELS: Array[String] = ["1x", "4x", "8x", "16x"]

# Materiaaliskanneri — oikea alakulma
var scanner_panel: PanelContainer
var scanner_label: RichTextLabel
var _scanner_frame: int = 0
const SCANNER_INTERVAL: int = 6  # Päivitetään joka 6. frame (~10 Hz 60fps:llä)
const SCANNER_RADIUS: int = 50

# Materiaalinimi- ja värikartat skannerille
const MAT_NAMES: Dictionary = {
	0: "",          # EMPTY ei näytetä
	1: "Hiekka",
	2: "Vesi",
	3: "Kivi",
	4: "Puu",
	5: "Tuli",
	6: "Öljy",
	7: "Höyry",
	8: "Tuhka",
	9: "Puu↓",
	10: "Lasi",
	11: "Multa",
	12: "Rautamalmi",
	13: "Kultamalmi",
	14: "Rauta",
	15: "Kulta",
	16: "Hiili",
	18: "Sora",
	19: "Pohjakivi",
}
const MAT_COLORS: Dictionary = {
	1: "#dcc874",   # SAND
	2: "#6699dd",   # WATER
	3: "#8c8c85",   # STONE
	4: "#7a4820",   # WOOD
	5: "#ff8020",   # FIRE
	6: "#3a2a1a",   # OIL
	7: "#ccd8e6",   # STEAM
	8: "#5a5450",   # ASH
	9: "#7a4820",   # WOOD_FALLING
	10: "#a6e0d6",  # GLASS
	11: "#7a5230",  # DIRT
	12: "#8c6b60",  # IRON_ORE
	13: "#b8a640",  # GOLD_ORE
	14: "#adadb8",  # IRON
	15: "#e6c732",  # GOLD
	16: "#2e2b36",  # COAL
	18: "#6b6055",  # GRAVEL
	19: "#2d2830",  # BEDROCK
}


# Apufunktio: luo VSeparator
func _sep() -> VSeparator:
	var s := VSeparator.new()
	return s


# Apufunktio: luo nappi vakioasetuksilla
func _make_btn(label: String, font_size: int = 12) -> Button:
	var btn := Button.new()
	btn.text = label
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", font_size)
	return btn


func _ready() -> void:
	# UI-esto: anna pixel_world viittaus tähän paneeliin (rektitarkistus)
	pixel_world.ui_panel = self

	# Pääcontainer: yksi vaakariivi koko palkin leveydeltä
	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 4)
	add_child(hbox)

	# ── Materiaalit-ryhmä ──────────────────────────────────────────────────
	var mat_box := HBoxContainer.new()
	mat_box.add_theme_constant_override("separation", 2)
	hbox.add_child(mat_box)

	var mat_label := Label.new()
	mat_label.text = "Mat:"
	mat_label.add_theme_font_size_override("font_size", 12)
	mat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mat_box.add_child(mat_label)

	var btn_sand := _make_btn("Hiekka")
	btn_sand.pressed.connect(_on_material.bind(1))
	mat_box.add_child(btn_sand)

	var btn_water := _make_btn("Vesi")
	btn_water.pressed.connect(_on_material.bind(2))
	mat_box.add_child(btn_water)

	btn_stone = _make_btn("Kivi")
	btn_stone.pressed.connect(_on_stone_static)
	mat_box.add_child(btn_stone)

	btn_stone_dynamic = _make_btn("Kivi~")
	btn_stone_dynamic.pressed.connect(_on_stone_dynamic)
	mat_box.add_child(btn_stone_dynamic)

	var btn_wood := _make_btn("Puu")
	btn_wood.pressed.connect(_on_material.bind(4))
	mat_box.add_child(btn_wood)

	var btn_fire := _make_btn("Tuli")
	btn_fire.pressed.connect(_on_material.bind(5))
	mat_box.add_child(btn_fire)

	var btn_oil := _make_btn("Öljy")
	btn_oil.pressed.connect(_on_material.bind(6))
	mat_box.add_child(btn_oil)

	var btn_erase := _make_btn("Kumita")
	btn_erase.pressed.connect(_on_material.bind(0))
	mat_box.add_child(btn_erase)

	var btn_clear := _make_btn("Tyhjennä")
	btn_clear.pressed.connect(_on_clear)
	mat_box.add_child(btn_clear)

	var btn_reset := _make_btn("Uusi [R]")
	btn_reset.pressed.connect(_on_reset)
	mat_box.add_child(btn_reset)

	# ── Pensseli-ryhmä ─────────────────────────────────────────────────────
	hbox.add_child(_sep())

	var pen_box := HBoxContainer.new()
	pen_box.add_theme_constant_override("separation", 4)
	hbox.add_child(pen_box)

	brush_label = Label.new()
	brush_label.text = "Pen: 5"
	brush_label.add_theme_font_size_override("font_size", 12)
	brush_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pen_box.add_child(brush_label)

	brush_slider = HSlider.new()
	brush_slider.min_value = 1.0
	brush_slider.max_value = 20.0
	brush_slider.step = 1.0
	brush_slider.value = 5.0
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_slider.custom_minimum_size = Vector2(80.0, 0.0)
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.value_changed.connect(_on_brush_changed)
	pen_box.add_child(brush_slider)

	# ── Nopeus-ryhmä ───────────────────────────────────────────────────────
	hbox.add_child(_sep())

	var speed_box := HBoxContainer.new()
	speed_box.add_theme_constant_override("separation", 2)
	hbox.add_child(speed_box)

	for i in SPEED_VALUES.size():
		var btn := _make_btn(SPEED_LABELS[i])
		btn.custom_minimum_size = Vector2(32.0, 0.0)
		btn.pressed.connect(_on_speed.bind(SPEED_VALUES[i]))
		speed_box.add_child(btn)
		speed_buttons.append(btn)

	# ── Tallennus-ryhmä ────────────────────────────────────────────────────
	hbox.add_child(_sep())

	var save_box := HBoxContainer.new()
	save_box.add_theme_constant_override("separation", 2)
	hbox.add_child(save_box)

	var btn_save := _make_btn("F5")
	btn_save.pressed.connect(func(): pixel_world.save_world())
	save_box.add_child(btn_save)

	var btn_load := _make_btn("F9")
	btn_load.pressed.connect(func(): pixel_world.load_world())
	save_box.add_child(btn_load)

	# ── Raha-label ─────────────────────────────────────────────────────────
	hbox.add_child(_sep())

	money_label = Label.new()
	money_label.text = "$0"
	money_label.add_theme_font_size_override("font_size", 14)
	money_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(money_label)
	hbox.add_child(_sep())

	# ── FPS-label oikealle ─────────────────────────────────────────────────

	fps_label = Label.new()
	fps_label.text = "FPS: 0"
	fps_label.add_theme_font_size_override("font_size", 12)
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fps_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	hbox.add_child(fps_label)

	# ── Rakennus-dropdown-paneeli (toinen rivi, palkin alla) ────────────────
	_build_dropdown_panel()

	# ── Materiaaliskanneri (oikea alakulma) ────────────────────────────────
	_build_scanner_panel()


func _build_dropdown_panel() -> void:
	# Luo erillinen PanelContainer palkin alapuolelle (offset_top = 50)
	build_panel = PanelContainer.new()
	build_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	build_panel.anchor_right = 1.0
	build_panel.offset_top = 50.0
	build_panel.offset_bottom = 84.0
	build_panel.offset_left = 0.0
	build_panel.offset_right = 0.0
	build_panel.visible = true
	get_parent().add_child.call_deferred(build_panel)  # lisätään CanvasLayer UI:hin, ei paneliin

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 6)
	build_panel.add_child(hbox)

	# Ohjeteksti vasemmalla
	var hint_lbl := Label.new()
	hint_lbl.text = "Sijoita:"
	hint_lbl.add_theme_font_size_override("font_size", 12)
	hint_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	hint_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(hint_lbl)

	btn_spawner = _make_btn("Spawner [1]")
	btn_spawner.pressed.connect(_on_build_spawner)
	hbox.add_child(btn_spawner)
	build_buttons.append(btn_spawner)

	btn_conveyor = _make_btn("Hihna [2]")
	btn_conveyor.pressed.connect(_on_build_conveyor)
	hbox.add_child(btn_conveyor)
	build_buttons.append(btn_conveyor)

	btn_sand_mine_build = _make_btn("Kaivos [3]")
	btn_sand_mine_build.pressed.connect(_on_build_sand_mine)
	hbox.add_child(btn_sand_mine_build)
	build_buttons.append(btn_sand_mine_build)

	btn_furnace_build = _make_btn("Uuni [4]")
	btn_furnace_build.pressed.connect(_on_build_furnace)
	hbox.add_child(btn_furnace_build)
	build_buttons.append(btn_furnace_build)

	btn_sling = _make_btn("Linko [5]")
	btn_sling.pressed.connect(_on_build_sling)
	hbox.add_child(btn_sling)
	build_buttons.append(btn_sling)

	btn_wall = _make_btn("Seinä [W]")
	btn_wall.pressed.connect(_on_build_wall)
	hbox.add_child(btn_wall)
	build_buttons.append(btn_wall)

	btn_money_exit_build = _make_btn("Kassa [7]")
	btn_money_exit_build.pressed.connect(func():
		pixel_world.build_mode = pixel_world.BUILD_MONEY_EXIT
		pixel_world.block_paint = true)
	hbox.add_child(btn_money_exit_build)
	build_buttons.append(btn_money_exit_build)

	btn_crusher_build = _make_btn("Murskaaja [8]")
	btn_crusher_build.pressed.connect(func():
		pixel_world.build_mode = pixel_world.BUILD_CRUSHER
		pixel_world.block_paint = true)
	hbox.add_child(btn_crusher_build)
	build_buttons.append(btn_crusher_build)

	var btn_drill_build := _make_btn("Pora [P]")
	btn_drill_build.pressed.connect(func():
		pixel_world.build_mode = pixel_world.BUILD_DRILL
		pixel_world.block_paint = true)
	hbox.add_child(btn_drill_build)
	build_buttons.append(btn_drill_build)


func _build_scanner_panel() -> void:
	# Luo erillinen paneeli oikeaan alakulmaan — lisätään CanvasLayer UI:hin
	scanner_panel = PanelContainer.new()
	scanner_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	scanner_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	scanner_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	scanner_panel.offset_right = -8.0
	scanner_panel.offset_bottom = -8.0
	scanner_panel.offset_left = -180.0
	scanner_panel.offset_top = -200.0

	# Puoliläpinäkyvä tausta
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.72)
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.content_margin_left = 6.0
	style.content_margin_right = 6.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	scanner_panel.add_theme_stylebox_override("panel", style)

	scanner_label = RichTextLabel.new()
	scanner_label.bbcode_enabled = true
	scanner_label.fit_content = true
	scanner_label.scroll_active = false
	scanner_label.custom_minimum_size = Vector2(168.0, 0.0)
	scanner_label.add_theme_font_size_override("normal_font_size", 11)
	scanner_panel.add_child(scanner_label)

	get_parent().add_child.call_deferred(scanner_panel)


func update_material_scanner() -> void:
	# Luetaan pelaajan sijainti simulaatiokoordinaateissa
	if not is_instance_valid(pixel_world):
		return
	if pixel_world.grid.is_empty():
		return

	var px: int = int(pixel_world.cam_grid_pos.x)
	var py: int = int(pixel_world.cam_grid_pos.y)
	var w: int = pixel_world.SIM_WIDTH
	var h: int = pixel_world.SIM_HEIGHT
	var r: int = SCANNER_RADIUS
	var r2: int = r * r

	# Laske materiaalimäärät
	var counts: Dictionary = {}
	var total: int = 0

	var y_min: int = maxi(py - r, 0)
	var y_max: int = mini(py + r, h - 1)
	var x_min: int = maxi(px - r, 0)
	var x_max: int = mini(px + r, w - 1)

	for cy in range(y_min, y_max + 1):
		var dy: int = cy - py
		var dy2: int = dy * dy
		if dy2 > r2:
			continue
		var dx_max: int = int(sqrt(float(r2 - dy2)))
		var cx_min: int = maxi(px - dx_max, x_min)
		var cx_max: int = mini(px + dx_max, x_max)
		for cx in range(cx_min, cx_max + 1):
			var mat: int = pixel_world.grid[cy * w + cx]
			if mat != 0:
				counts[mat] = counts.get(mat, 0) + 1
				total += 1

	if total == 0:
		scanner_label.text = "[color=#666666]Skanneri: tyhjää[/color]"
		return

	# Järjestä laskevaan järjestykseen
	var entries: Array = []
	for mat_id: int in counts:
		entries.append([mat_id, counts[mat_id]])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])

	# Rakenna BBCode-teksti
	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#aaaaaa]Ympäristö (r=%d)[/color]" % r)
	for entry: Array in entries:
		var mat_id: int = entry[0]
		var count: int = entry[1]
		if not MAT_NAMES.has(mat_id) or MAT_NAMES[mat_id] == "":
			continue
		var pct: float = 100.0 * float(count) / float(total)
		var name_str: String = MAT_NAMES[mat_id]
		if MAT_COLORS.has(mat_id):
			lines.append("[color=%s]%s[/color]  [color=#cccccc]%.1f%%[/color]" % [MAT_COLORS[mat_id], name_str, pct])
		else:
			lines.append("%s  %.1f%%" % [name_str, pct])
	scanner_label.text = "\n".join(lines)


func _process(_delta: float) -> void:
	# Päivitä materiaaliskanneri harvakseen (performance)
	_scanner_frame += 1
	if _scanner_frame >= SCANNER_INTERVAL:
		_scanner_frame = 0
		update_material_scanner()

	# Korosta aktiivinen nopeus
	for i in speed_buttons.size():
		speed_buttons[i].modulate = Color(1.5, 1.5, 0.5) if SPEED_VALUES[i] == pixel_world.sim_speed else Color.WHITE

	# Korosta aktiivinen rakennustila
	var bm: int = pixel_world.build_mode
	var active_build_idx: int = -1
	match bm:
		pixel_world.BUILD_SPAWNER:       active_build_idx = 0
		pixel_world.BUILD_CONVEYOR_START, pixel_world.BUILD_CONVEYOR_END: active_build_idx = 1
		pixel_world.BUILD_SAND_MINE:     active_build_idx = 2
		pixel_world.BUILD_FURNACE:       active_build_idx = 3
		pixel_world.BUILD_SLING:         active_build_idx = 4
		pixel_world.BUILD_WALL_START, pixel_world.BUILD_WALL_END: active_build_idx = 5
		pixel_world.BUILD_MONEY_EXIT:    active_build_idx = 6
		pixel_world.BUILD_CRUSHER:       active_build_idx = 7
		pixel_world.BUILD_DRILL:         active_build_idx = 8
	for i in build_buttons.size():
		build_buttons[i].modulate = Color(0.5, 1.5, 0.5) if i == active_build_idx else Color.WHITE

	# Tila-teksti FPS-labelissa
	var mode_str := ""
	if pixel_world.build_mode == pixel_world.BUILD_SPAWNER:
		mode_str = " | SPAWNER [klikkaa]"
	elif pixel_world.build_mode == pixel_world.BUILD_CONVEYOR_START:
		mode_str = " | HIHNA: klikkaa alku"
	elif pixel_world.build_mode == pixel_world.BUILD_CONVEYOR_END:
		mode_str = " | HIHNA: klikkaa loppu"
	elif pixel_world.build_mode == pixel_world.BUILD_SAND_MINE:
		mode_str = " | KAIVOS [klikkaa]"
	elif pixel_world.build_mode == pixel_world.BUILD_FURNACE:
		mode_str = " | UUNI [klikkaa]"
	elif pixel_world.build_mode == pixel_world.BUILD_SLING:
		match pixel_world.launcher_phase:
			1: mode_str = " | HISSI-LINKO: klikkaa pohja"
			2: mode_str = " | HISSI-LINKO: klikkaa katto"
			3: mode_str = " | HISSI-LINKO: klikkaa suunta (vasen/oikea)"
			_: mode_str = " | HISSI-LINKO"
	elif pixel_world.build_mode == pixel_world.BUILD_WALL_START:
		mode_str = " | SEINÄ: klikkaa alku"
	elif pixel_world.build_mode == pixel_world.BUILD_WALL_END:
		mode_str = " | SEINÄ: klikkaa loppu"
	elif pixel_world.build_mode == pixel_world.BUILD_DRILL:
		mode_str = " | PORA [klikkaa]"
	elif pixel_world.grav_gun_mode > 0:
		mode_str = " | GRAVITY GUN"
	elif pixel_world.current_weapon == 2:  # Weapon.RIFLE = 2
		mode_str = " | RYNNÄKKÖ [L]"

	var explosion_names: Array[String] = ["Pieni", "Keski", "Iso", "Mega"]
	var exp_str := explosion_names[pixel_world.explosion_size]
	var belt_str := " | Hihnoja: %d" % pixel_world.conveyors.size() if not pixel_world.conveyors.is_empty() else ""
	var furnace_str := " | Uuneja: %d" % pixel_world.furnaces.size() if not pixel_world.furnaces.is_empty() else ""
	var mine_str := " | Kaivoksia: %d" % pixel_world.sand_mines.size() if not pixel_world.sand_mines.is_empty() else ""
	var sling_str := " | Linkoja: %d" % pixel_world.launchers.size() if not pixel_world.launchers.is_empty() else ""
	var drill_str := " | Poraa: %d" % pixel_world.drills.size() if not pixel_world.drills.is_empty() else ""
	var speed_str := " | %dx" % int(pixel_world.sim_speed) if pixel_world.sim_speed > 1.0 else ""
	fps_label.text = "FPS: %d | %s%s%s%s%s%s%s%s" % [Engine.get_frames_per_second(), exp_str, belt_str, furnace_str, mine_str, sling_str, drill_str, speed_str, mode_str]
	money_label.text = "$%d" % pixel_world.money


func _on_material(mat: int) -> void:
	pixel_world.current_material = mat
	pixel_world.stone_dynamic = false
	pixel_world.build_mode = pixel_world.BUILD_NONE


func _on_stone_static() -> void:
	pixel_world.current_material = pixel_world.MAT_STONE
	pixel_world.stone_dynamic = false
	pixel_world.build_mode = pixel_world.BUILD_NONE
	btn_stone.modulate = Color(1.5, 1.5, 0.5)
	btn_stone_dynamic.modulate = Color.WHITE


func _on_stone_dynamic() -> void:
	pixel_world.current_material = pixel_world.MAT_STONE
	pixel_world.stone_dynamic = true
	pixel_world.build_mode = pixel_world.BUILD_NONE
	btn_stone.modulate = Color.WHITE
	btn_stone_dynamic.modulate = Color(1.5, 1.5, 0.5)


func _on_clear() -> void:
	pixel_world.clear_world()


func _on_reset() -> void:
	pixel_world.regenerate_world()


func _on_brush_changed(value: float) -> void:
	pixel_world.brush_size = int(value)
	brush_label.text = "Pen: %d" % int(value)


func _on_speed(speed: float) -> void:
	pixel_world.sim_speed = speed


func _on_build_toggle(_pressed: bool) -> void:
	pass  # Rakennuspaneeli on aina näkyvissä


func _on_build_spawner() -> void:
	pixel_world.build_mode = pixel_world.BUILD_SPAWNER
	pixel_world.block_paint = true


func _on_build_conveyor() -> void:
	pixel_world.build_mode = pixel_world.BUILD_CONVEYOR_START
	pixel_world.block_paint = true


func _on_build_sand_mine() -> void:
	pixel_world.build_mode = pixel_world.BUILD_SAND_MINE
	pixel_world.block_paint = true


func _on_build_furnace() -> void:
	pixel_world.build_mode = pixel_world.BUILD_FURNACE
	pixel_world.block_paint = true


func _on_build_sling() -> void:
	pixel_world.build_mode = pixel_world.BUILD_SLING
	pixel_world.launcher_phase = 1
	pixel_world.block_paint = true


func _on_build_wall() -> void:
	pixel_world.build_mode = pixel_world.BUILD_WALL_START
	pixel_world.block_paint = true
