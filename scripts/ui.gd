extends PanelContainer

@onready var pixel_world: TextureRect = get_node("../../PixelWorld")
@onready var brush_label: Label = $VBox/BrushLabel
@onready var brush_slider: HSlider = $VBox/BrushSlider
@onready var fps_label: Label = $VBox/FPSLabel


func _ready() -> void:
	$VBox/BtnSand.pressed.connect(_on_material.bind(1))  # Mat.SAND
	$VBox/BtnWater.pressed.connect(_on_material.bind(2))  # Mat.WATER
	$VBox/BtnStone.pressed.connect(_on_material.bind(3))  # Mat.STONE
	$VBox/BtnWood.pressed.connect(_on_material.bind(4))   # Mat.WOOD
	$VBox/BtnFire.pressed.connect(_on_material.bind(5))   # Mat.FIRE
	$VBox/BtnOil.pressed.connect(_on_material.bind(6))    # Mat.OIL
	$VBox/BtnErase.pressed.connect(_on_material.bind(0))  # Mat.EMPTY
	$VBox/BtnClear.pressed.connect(_on_clear)
	$VBox/BtnReset.pressed.connect(_on_reset)
	brush_slider.value_changed.connect(_on_brush_changed)


func _process(_delta: float) -> void:
	var mode_str := ""
	if pixel_world.grav_gun_mode > 0:
		mode_str = " | GRAVITY GUN"
	elif pixel_world.cut_mode:
		mode_str = " | LEIKKAUS"
	var explosion_names: Array[String] = ["Pieni", "Keski", "Iso", "Mega"]
	var exp_str := explosion_names[pixel_world.explosion_size]
	fps_label.text = "FPS: %d | Räjähdys: %s%s" % [Engine.get_frames_per_second(), exp_str, mode_str]


func _on_material(mat: int) -> void:
	pixel_world.current_material = mat


func _on_clear() -> void:
	pixel_world.clear_world()


func _on_reset() -> void:
	pixel_world.regenerate_world()


func _on_brush_changed(value: float) -> void:
	pixel_world.brush_size = int(value)
	brush_label.text = "Pensseli: %d" % int(value)
