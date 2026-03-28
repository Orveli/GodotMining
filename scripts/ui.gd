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
	brush_slider.value_changed.connect(_on_brush_changed)


func _process(_delta: float) -> void:
	fps_label.text = "FPS: %d" % Engine.get_frames_per_second()


func _on_material(mat: int) -> void:
	pixel_world.current_material = mat


func _on_clear() -> void:
	pixel_world.clear_world()


func _on_brush_changed(value: float) -> void:
	pixel_world.brush_size = int(value)
	brush_label.text = "Pensseli: %d" % int(value)
