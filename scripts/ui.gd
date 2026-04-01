extends PanelContainer

@onready var pixel_world: TextureRect = get_node("../../PixelWorld")
@onready var brush_label: Label = $VBox/BrushLabel
@onready var brush_slider: HSlider = $VBox/BrushSlider
@onready var fps_label: Label = $VBox/FPSLabel

# Rakennusnapit (luodaan ohjelmallisesti)
var build_section: VBoxContainer
var btn_spawner: Button
var btn_conveyor: Button
var btn_sling: Button
var btn_wall: Button

# Speed-napit
var speed_buttons: Array[Button] = []
const SPEED_VALUES: Array[float] = [1.0, 4.0, 8.0, 16.0]
const SPEED_LABELS: Array[String] = ["1x", "4x", "8x", "16x"]

# Asenapit
var weapon_buttons: Array[Button] = []
const WEAPON_LABELS: Array[String] = ["Hakku", "Megapora", "Laseri", "Raketti", "GravGun"]


func _ready() -> void:
	# UI-esto: anna pixel_world viittaus tähän paneeliin (rektitarkistus)
	pixel_world.ui_panel = self

	# Poista focus kaikista napeista — muuten ne kaappaavat näppäimet
	for btn in [$VBox/BtnSand, $VBox/BtnWater, $VBox/BtnStone, $VBox/BtnStoneDynamic,
			$VBox/BtnWood, $VBox/BtnFire, $VBox/BtnOil, $VBox/BtnErase, $VBox/BtnClear, $VBox/BtnReset]:
		btn.focus_mode = Control.FOCUS_NONE
	brush_slider.focus_mode = Control.FOCUS_NONE

	$VBox/BtnSand.pressed.connect(_on_material.bind(1))  # Mat.SAND
	$VBox/BtnWater.pressed.connect(_on_material.bind(2))  # Mat.WATER
	$VBox/BtnStone.pressed.connect(_on_stone_static)   # Staattinen kivi
	$VBox/BtnStoneDynamic.pressed.connect(_on_stone_dynamic)
	$VBox/BtnWood.pressed.connect(_on_material.bind(4))   # Mat.WOOD
	$VBox/BtnFire.pressed.connect(_on_material.bind(5))   # Mat.FIRE
	$VBox/BtnOil.pressed.connect(_on_material.bind(6))    # Mat.OIL
	$VBox/BtnErase.pressed.connect(_on_material.bind(0))  # Mat.EMPTY
	$VBox/BtnClear.pressed.connect(_on_clear)
	$VBox/BtnReset.pressed.connect(_on_reset)
	brush_slider.value_changed.connect(_on_brush_changed)

	# Tallennus / lataus
	var sep_save := HSeparator.new()
	$VBox.add_child(sep_save)

	var save_row := HBoxContainer.new()
	save_row.alignment = BoxContainer.ALIGNMENT_CENTER
	$VBox.add_child(save_row)

	var btn_save := Button.new()
	btn_save.text = "Tallenna [F5]"
	btn_save.focus_mode = Control.FOCUS_NONE
	btn_save.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_save.add_theme_font_size_override("font_size", 13)
	btn_save.pressed.connect(func(): pixel_world.save_world())
	save_row.add_child(btn_save)

	var btn_load := Button.new()
	btn_load.text = "Lataa [F9]"
	btn_load.focus_mode = Control.FOCUS_NONE
	btn_load.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_load.add_theme_font_size_override("font_size", 13)
	btn_load.pressed.connect(func(): pixel_world.load_world())
	save_row.add_child(btn_load)

	# Ajan nopeus -osio
	var sep_speed := HSeparator.new()
	$VBox.add_child(sep_speed)

	var speed_title := Label.new()
	speed_title.text = "Aika"
	speed_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	speed_title.add_theme_font_size_override("font_size", 16)
	$VBox.add_child(speed_title)

	var speed_row := HBoxContainer.new()
	speed_row.alignment = BoxContainer.ALIGNMENT_CENTER
	$VBox.add_child(speed_row)

	for i in SPEED_VALUES.size():
		var btn := Button.new()
		btn.text = SPEED_LABELS[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(36, 0)
		btn.add_theme_font_size_override("font_size", 13)
		btn.pressed.connect(_on_speed.bind(SPEED_VALUES[i]))
		speed_row.add_child(btn)
		speed_buttons.append(btn)

	# Rakennusvalikko — toggle-nappi + sisältö
	var sep_build := HSeparator.new()
	$VBox.add_child(sep_build)

	var btn_build_toggle := Button.new()
	btn_build_toggle.text = "Rakennukset [B]"
	btn_build_toggle.toggle_mode = true
	btn_build_toggle.focus_mode = Control.FOCUS_NONE
	btn_build_toggle.add_theme_font_size_override("font_size", 16)
	btn_build_toggle.toggled.connect(_on_build_toggle)
	$VBox.add_child(btn_build_toggle)

	build_section = VBoxContainer.new()
	build_section.visible = false
	$VBox.add_child(build_section)

	btn_spawner = Button.new()
	btn_spawner.text = "Spawner [1]"
	btn_spawner.add_theme_font_size_override("font_size", 14)
	btn_spawner.focus_mode = Control.FOCUS_NONE
	btn_spawner.pressed.connect(_on_build_spawner)
	build_section.add_child(btn_spawner)

	btn_conveyor = Button.new()
	btn_conveyor.text = "Hihna [2]"
	btn_conveyor.add_theme_font_size_override("font_size", 14)
	btn_conveyor.focus_mode = Control.FOCUS_NONE
	btn_conveyor.pressed.connect(_on_build_conveyor)
	build_section.add_child(btn_conveyor)

	var btn_sand_mine := Button.new()
	btn_sand_mine.text = "Kaivos [3]"
	btn_sand_mine.add_theme_font_size_override("font_size", 14)
	btn_sand_mine.focus_mode = Control.FOCUS_NONE
	btn_sand_mine.pressed.connect(_on_build_sand_mine)
	build_section.add_child(btn_sand_mine)

	var btn_furnace := Button.new()
	btn_furnace.text = "Uuni [4]"
	btn_furnace.add_theme_font_size_override("font_size", 14)
	btn_furnace.focus_mode = Control.FOCUS_NONE
	btn_furnace.pressed.connect(_on_build_furnace)
	build_section.add_child(btn_furnace)

	btn_sling = Button.new()
	btn_sling.text = "Linko [5]"
	btn_sling.add_theme_font_size_override("font_size", 14)
	btn_sling.focus_mode = Control.FOCUS_NONE
	btn_sling.pressed.connect(_on_build_sling)
	build_section.add_child(btn_sling)

	btn_wall = Button.new()
	btn_wall.text = "Seinä [W]"
	btn_wall.add_theme_font_size_override("font_size", 14)
	btn_wall.focus_mode = Control.FOCUS_NONE
	btn_wall.pressed.connect(_on_build_wall)
	build_section.add_child(btn_wall)

	# Ase-osio
	var sep_weapon := HSeparator.new()
	$VBox.add_child(sep_weapon)

	var weapon_title := Label.new()
	weapon_title.text = "Ase [Q]"
	weapon_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	weapon_title.add_theme_font_size_override("font_size", 16)
	$VBox.add_child(weapon_title)

	for i in WEAPON_LABELS.size():
		var btn := Button.new()
		btn.text = WEAPON_LABELS[i]
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 14)
		btn.pressed.connect(func(): pixel_world.current_weapon = i)
		$VBox.add_child(btn)
		weapon_buttons.append(btn)

	# Tallenna toggle-nappi jotta voidaan synkronoida B-näppäimen kanssa
	set_meta("build_toggle_btn", btn_build_toggle)


func _process(_delta: float) -> void:
	# Synkronoi build-toggle-nappi B-näppäimen tilaan
	var btn_build: Button = get_meta("build_toggle_btn")
	if btn_build.button_pressed != pixel_world.build_menu_visible:
		btn_build.set_pressed_no_signal(pixel_world.build_menu_visible)
	build_section.visible = pixel_world.build_menu_visible

	# Korosta aktiivinen nopeus
	for i in speed_buttons.size():
		speed_buttons[i].modulate = Color(1.5, 1.5, 0.5) if SPEED_VALUES[i] == pixel_world.sim_speed else Color.WHITE

	# Korosta aktiivinen ase
	for i in weapon_buttons.size():
		weapon_buttons[i].modulate = Color(0.5, 1.5, 0.5) if i == pixel_world.current_weapon else Color.WHITE

	# Tila-teksti
	var mode_str := ""
	if pixel_world.build_menu_visible:
		mode_str = " | RAKENNA: [1] Spawner [2] Hihna [3] Kaivos [4] Uuni [5] Linko [6] Seinä | MAT: [7] Multa [8] RautaMalmi [9] KultaMalmi"
	elif pixel_world.build_mode == pixel_world.BUILD_SPAWNER:
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
	elif pixel_world.grav_gun_mode > 0:
		mode_str = " | GRAVITY GUN"
	elif pixel_world.laser_mode:
		if pixel_world.laser_dragging:
			mode_str = " | LASERI [vedä]"
		else:
			mode_str = " | LASERI [L]"
	var explosion_names: Array[String] = ["Pieni", "Keski", "Iso", "Mega"]
	var exp_str := explosion_names[pixel_world.explosion_size]
	var chicken_count: int = pixel_world.get_chicken_count()
	var chicken_str := " | Kanoja: %d" % chicken_count if chicken_count > 0 else ""
	var belt_str := " | Hihnoja: %d" % pixel_world.conveyors.size() if not pixel_world.conveyors.is_empty() else ""
	var furnace_str := " | Uuneja: %d" % pixel_world.furnaces.size() if not pixel_world.furnaces.is_empty() else ""
	var mine_str := " | Kaivoksia: %d" % pixel_world.sand_mines.size() if not pixel_world.sand_mines.is_empty() else ""
	var sling_str := " | Linkoja: %d" % pixel_world.launchers.size() if not pixel_world.launchers.is_empty() else ""
	var speed_str := " | %dx" % int(pixel_world.sim_speed) if pixel_world.sim_speed > 1.0 else ""
	fps_label.text = "FPS: %d | %s%s%s%s%s%s%s%s" % [Engine.get_frames_per_second(), exp_str, chicken_str, belt_str, furnace_str, mine_str, sling_str, speed_str, mode_str]


func _on_material(mat: int) -> void:
	pixel_world.current_material = mat
	pixel_world.stone_dynamic = false
	pixel_world.build_mode = pixel_world.BUILD_NONE


func _on_stone_static() -> void:
	pixel_world.current_material = pixel_world.MAT_STONE
	pixel_world.stone_dynamic = false
	pixel_world.build_mode = pixel_world.BUILD_NONE
	$VBox/BtnStone.modulate = Color(1.5, 1.5, 0.5)
	$VBox/BtnStoneDynamic.modulate = Color.WHITE


func _on_stone_dynamic() -> void:
	pixel_world.current_material = pixel_world.MAT_STONE
	pixel_world.stone_dynamic = true
	pixel_world.build_mode = pixel_world.BUILD_NONE
	$VBox/BtnStone.modulate = Color.WHITE
	$VBox/BtnStoneDynamic.modulate = Color(1.5, 1.5, 0.5)


func _on_clear() -> void:
	pixel_world.clear_world()


func _on_reset() -> void:
	pixel_world.regenerate_world()


func _on_brush_changed(value: float) -> void:
	pixel_world.brush_size = int(value)
	brush_label.text = "Pensseli: %d" % int(value)


func _on_speed(speed: float) -> void:
	pixel_world.sim_speed = speed


func _on_build_toggle(pressed: bool) -> void:
	pixel_world.build_menu_visible = pressed
	if not pressed:
		pixel_world.build_mode = pixel_world.BUILD_NONE


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
