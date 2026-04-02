extends TextureRect

const TestSceneGenerator = preload("res://scripts/test_scene_generator.gd")
const LauncherScript = preload("res://scripts/launcher.gd")
const MoneyExit = preload("res://scripts/money_exit.gd")
const Crusher = preload("res://scripts/crusher.gd")

const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_WATER := 2
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_FIRE := 5
const MAT_OIL := 6
const MAT_STEAM := 7
const MAT_ASH := 8
const MAT_WOOD_FALLING := 9
const MAT_GLASS := 10
const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13
const MAT_IRON := 14
const MAT_GOLD := 15
const MAT_COAL := 16
const MAT_HELD := 17  # Poistettu käytöstä — säilytetään yhteensopivuuden vuoksi
const MAT_GRAVEL := 18  # Sora — kiven murskautuessa syntyvä jauhe

const SIM_WIDTH := 1664
const SIM_HEIGHT := 960
const TOTAL := SIM_WIDTH * SIM_HEIGHT
const W := SIM_WIDTH

# CPU-puolen grid (maalaamista varten)
var grid: PackedByteArray
var color_seed: PackedByteArray

# GPU compute
var rd: RenderingDevice
var shader_rid: RID
var pipeline: RID
var grid_buffer: RID
var uniform_set: RID
var gpu_ready := false

# Transfer shader (GPU-purkaus/pakkaus)
var transfer_shader_rid: RID
var transfer_pipeline: RID
var mat_packed_buffer: RID
var seed_packed_buffer: RID
var transfer_uniform_set: RID
var transfer_ready := false

# Render compute shader (GPU → RGBA8-tekstuuri suoraan, ei CPU-roundtripiä)
var render_compute_shader_rid: RID
var render_compute_pipeline: RID
var render_compute_uniform_set: RID
var render_tex_rid: RID       # RGBA8 GPU-tekstuuri (local RD)
var render_tex_godot: Texture2DRD  # Godot-side wrapperi
var render_compute_ready := false

# Renderöinti (pidetään CPU-fallbackia varten, käytetään vain jos render compute ei käynnisty)
var grid_image: Image
var grid_texture: ImageTexture
var seed_image: Image
var seed_texture: ImageTexture
var shader_mat: ShaderMaterial
var darkness_mode: bool = false

# Väripaletit — runtime-vaihdettava
const PALETTE_DEFAULT: Array = [
	Vector3(0.08, 0.08, 0.12),   # 0 EMPTY
	Vector3(0.86, 0.78, 0.45),   # 1 SAND
	Vector3(0.2, 0.4, 0.85),     # 2 WATER
	Vector3(0.5, 0.5, 0.52),     # 3 STONE
	Vector3(0.45, 0.28, 0.12),   # 4 WOOD
	Vector3(1.0, 0.5, 0.1),      # 5 FIRE
	Vector3(0.2, 0.15, 0.1),     # 6 OIL
	Vector3(0.8, 0.85, 0.9),     # 7 STEAM
	Vector3(0.35, 0.33, 0.3),    # 8 ASH
	Vector3(0.45, 0.28, 0.12),   # 9 WOOD_FALLING
	Vector3(0.65, 0.88, 0.84),   # 10 GLASS
	Vector3(0.45, 0.32, 0.18),   # 11 DIRT
	Vector3(0.55, 0.42, 0.38),   # 12 IRON_ORE
	Vector3(0.72, 0.65, 0.25),   # 13 GOLD_ORE
	Vector3(0.68, 0.68, 0.72),   # 14 IRON
	Vector3(0.90, 0.78, 0.20),   # 15 GOLD
	Vector3(0.18, 0.17, 0.21),   # 16 COAL
	Vector3(1.0, 0.85, 0.1),     # 17 HELD
	Vector3(0.55, 0.50, 0.45),   # 18 GRAVEL
]

const PALETTE_DEEP: Array = [
	Vector3(0.04, 0.04, 0.08),   # 0 EMPTY (tummempi)
	Vector3(0.7, 0.6, 0.3),      # 1 SAND
	Vector3(0.1, 0.25, 0.6),     # 2 WATER (tummempi sininen)
	Vector3(0.35, 0.32, 0.38),   # 3 STONE (violettiin vivahtava)
	Vector3(0.3, 0.18, 0.08),    # 4 WOOD
	Vector3(0.9, 0.3, 0.05),     # 5 FIRE (punaisempi)
	Vector3(0.15, 0.1, 0.08),    # 6 OIL
	Vector3(0.6, 0.65, 0.75),    # 7 STEAM
	Vector3(0.25, 0.23, 0.22),   # 8 ASH
	Vector3(0.3, 0.18, 0.08),    # 9 WOOD_FALLING
	Vector3(0.45, 0.7, 0.65),    # 10 GLASS
	Vector3(0.3, 0.2, 0.12),     # 11 DIRT
	Vector3(0.45, 0.28, 0.22),   # 12 IRON_ORE
	Vector3(0.6, 0.52, 0.18),    # 13 GOLD_ORE
	Vector3(0.55, 0.55, 0.6),    # 14 IRON
	Vector3(0.85, 0.7, 0.15),    # 15 GOLD
	Vector3(0.12, 0.11, 0.14),   # 16 COAL
	Vector3(1.0, 0.85, 0.1),     # 17 HELD
	Vector3(0.42, 0.37, 0.32),   # 18 GRAVEL (tummempi syvyydessä)
]

const PALETTE_VAR_DEFAULT: Array = [
	0.0, 0.06, 0.04, 0.05, 0.04, 0.2, 0.02, 0.05, 0.03, 0.04, 0.03,
	0.03, 0.04, 0.04, 0.02, 0.02, 0.05, 0.05, 0.04
]

var current_palette: Array = PALETTE_DEFAULT

var current_material: int = MAT_SAND
var brush_size: int = 5
var frame_count: int = 0
var fps_timer: float = 0.0
var gpu_passes: int = 8  # Adaptiivinen passimäärä (4-12); Margolus vaatii min 4 passia
var sim_speed: float = 1.0  # 1=normaali, 4/8/16=nopea
var _logic_frame_counter: int = 0
var logic_frame_interval: int = 4  # CPU game logic ajetaan joka 4. frame
var ui_panel: Control  # Asetetaan ui.gd:stä — tarkistetaan rektillä
var _toast_label: Label       # Ruudulla näytettävä lyhyt ilmoitus
var _toast_timer: float = 0.0 # Kuinka kauan ilmoitus on näkyvissä
var gpu_time_ms: float = 0.0  # Edellisen framen GPU-aika
var paint_pending := false

# Kaivaustyökalut
enum Tool { HAND, SHOVEL, PICKAXE, DRILL, MEGA_DRILL }
enum Weapon { PICKAXE, MEGA_DRILL, RIFLE, ROCKET, GRAVITY_GUN }
var current_weapon: Weapon = Weapon.PICKAXE

var current_tool: Tool = Tool.HAND
const TOOL_DATA := {
	Tool.HAND:       { "radius": 3,  "speed": 1 },
	Tool.SHOVEL:     { "radius": 5,  "speed": 2 },
	Tool.PICKAXE:    { "radius": 5,  "speed": 1 },
	Tool.DRILL:      { "radius": 4,  "speed": 3 },
	Tool.MEGA_DRILL: { "radius": 14, "speed": 4 },
}

# Hakkuun cooldown — estää liian nopean kaivauksen
var pickaxe_cooldown: float = 0.0
const PICKAXE_COOLDOWN_TIME := 0.15
var mega_drill_cooldown: float = 0.0
const MEGA_DRILL_COOLDOWN_TIME := 0.05  # 20x/s riittää

# Raketinheitin
var rocket_cooldown: float = 0.0
const ROCKET_COOLDOWN_TIME := 0.5
const ROCKET_SPEED := 200.0
const ROCKET_GRAVITY := 15.0  # Pieni gravitaatio raketille
const MAX_ROCKETS := 3

# Per-faasi ajoitusmittaus
var _t_gpu: float = 0.0
var _t_download: float = 0.0
var _t_upload_render: float = 0.0
var _t_gamelogic: float = 0.0
var _perf_frame: int = 0

# Rynnäkkäkivääri
var laser_mode := false
var laser_dragging := false
var rifle_cooldown: float = 0.0
const RIFLE_COOLDOWN_TIME := 0.05

# Laseri — funktio säilytetty mutta ei käytössä (vakiot tarvitaan kääntämiseen)
var laser_beam_timer: int = 0
const LASER_BEAM_DURATION := 8
const LASER_WIDTH := 2

# Screenshake
var trauma: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO
var ca_flash: float = 0.0  # Chromatic aberration osumasta, ei heiluta ruutua

# Sky-visibility map
var visibility_image: Image
var visibility_tex: ImageTexture
var visibility_dirty: bool = true
var _vis_thread: Thread = null
var _vis_result: PackedByteArray = PackedByteArray()

# Lokaali impakti-CA
var impact_uv: Vector2 = Vector2.ZERO
var impact_intensity: float = 0.0
var impact_type_val: int = 0  # 0=luoti, 1=raketti, 2=hakku

# Räjähdykset
var explosion_size: int = 1  # 0=pieni, 1=keski, 2=iso, 3=mega
const EXPLOSION_RADII: Array[int] = [8, 15, 25, 40]
const EXPLOSION_TRAUMA: Array[float] = [0.1, 0.25, 0.4, 0.6]

# Räjähdysflash
var flash_pos: Vector2 = Vector2.ZERO
var flash_radius: float = 0.0
var flash_timer: int = 0  # Frameja jäljellä (0 = ei flashia)
const FLASH_DURATION := 6  # Frameja

# Gravity gun
var grav_gun_mode: int = 0  # 0=off, 1=pull, 2=vakuumi
var grav_gun_pos: Vector2i = Vector2i.ZERO
var grav_gun_radius: int = 40
var grav_gun_vacuum_radius: int = 80
var grav_gun_body_strength: float = 3.0
var mouse_velocity: Vector2 = Vector2.ZERO
var prev_mouse_grid: Vector2 = Vector2.ZERO

# Gravity gun — held-lista (CPU omistaa kiinnitetyt pikselit)
const GRAV_CAPTURE_RADIUS := 8       # Säde jolla pikselit nappataan (px)
const GRAV_MAX_HELD := 500           # Maksimi kiinnitettyjen pikselien määrä
var grav_held: Array[Vector3i] = []  # Elementit: (material_id, offset_x, offset_y)
var grav_held_written: Array[int] = []  # Edellisellä framella kirjoitetut grid-indeksit

# Fysiikkamoottori
var physics_world: PhysicsWorld
var physics_initialized := false  # Onko kivi-kappaleet skannattu
var is_painting_stone := false  # Maalataan kiveä parhaillaan — fysiikka tauolla
var stroke_stone_pixels: Dictionary = {}  # Tämän vedon kivipikselit (deduplikoitu)
var stone_dynamic := false  # Tosi = maalattu kivi on irrallinen fysiikkakappale

# Rakennukset — lapsisolmut
var building_layer: Node2D

# Rakentaminen
const BUILD_NONE := 0
const BUILD_SPAWNER := 1
const BUILD_CONVEYOR_START := 2
const BUILD_CONVEYOR_END := 3
const BUILD_SAND_MINE := 4
const BUILD_FURNACE := 5
const BUILD_SLING := 6
const BUILD_WALL_START := 7
const BUILD_WALL_END := 8
const BUILD_MONEY_EXIT := 9
const BUILD_CRUSHER := 10
const GRID_SIZE := 8  # Rakennusgridi pikseleinä
var build_mode: int = BUILD_NONE
var build_menu_visible := false
var conveyor_start_pos: Vector2 = Vector2.ZERO
var wall_start_pos: Vector2 = Vector2.ZERO
var conveyors: Array = []
var furnaces: Array = []
var sand_mines: Array = []
var launchers: Array = []
var money_exits: Array = []
var crushers: Array = []
var money: int = 0
var building_pixels: Dictionary = {}  # idx -> true, kaikki rakennusten pikselit
var launcher_phase: int = 0    # 0=ei aktiivinen, 1=pohja, 2=katto, 3=suunta
var launcher_start: Vector2i = Vector2i.ZERO
var launcher_end: Vector2i = Vector2i.ZERO
var flying_pixels: Array[Dictionary] = []
var flying_gravity: float = 140.0   # px/s²
const FLYING_MAX_AGE := 4.0
var flying_max_count: int = 300

# Debug
var infinite_money: bool = false
var debug_menu_visible: bool = false

# Linko-oletusasetukset (debug-menu synkronoi kaikki launchers näihin)
var launcher_launch_speed: float = 120.0
var launcher_launch_angle: float = -45.0
var launcher_shaft_speed: float = 180.0
var launcher_intake_cooldown: float = 0.08

var build_preview: BuildPreview
var prev_left_pressed := false
var prev_right_pressed := false
var block_paint := false
var _gpu_upload_buf := PackedByteArray()
const SNAP_DISTANCE := 6.0

const PlayerScript := preload("res://scripts/player.gd")
var player: RefCounted
var god_mode: bool = false

# Kamera / zoom
var zoom_index: int = 0  # Yhteensopivuus
var zoom_level: float = 1.0
var target_zoom: float = 1.0
var camera_offset: Vector2 = Vector2.ZERO
var cam_grid_pos: Vector2 = Vector2(832.0, 480.0)
var cam_vel: Vector2 = Vector2.ZERO

# === SCENARIO RUNNER ===
var _scenario_steps: Array = []
var _scenario_index: int = 0
var _scenario_frames_remaining: int = 0
var _scenario_active: bool = false
var _scenario_auto_exit: bool = false
var _scenario_failures: int = 0
var _scenario_tests: int = 0

# === SUORITUSKYKYTESTI ===
# Tallennetaan viimeiset 60 framen delta-ajat millisekunteina ring-puskuriin
const _PERF_RING_SIZE := 60
var _perf_delta_ring: PackedFloat32Array
var _perf_ring_pos: int = 0


func _ready() -> void:
	# Irroitetaan anchor-layoutista — kamera hallitsee position/size/scale
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	var vp_size := get_viewport_rect().size
	position = Vector2.ZERO
	size = vp_size

	grid = PackedByteArray()
	grid.resize(TOTAL)
	grid.fill(0)
	color_seed = PackedByteArray()
	color_seed.resize(TOTAL)

	for i in TOTAL:
		color_seed[i] = randi() % 256

	# Alusta suorituskykytestin ring-puskuri
	_perf_delta_ring = PackedFloat32Array()
	_perf_delta_ring.resize(_PERF_RING_SIZE)
	_perf_delta_ring.fill(0.0)

	print("GodotMining valmis — C = tyhjennä, R = uusi maailma, P = suorituskykytesti")

	# CPU-puolen fallback-tekstuurit (käytetään jos render compute ei käynnisty)
	grid_image = Image.create_from_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, grid)
	grid_texture = ImageTexture.create_from_image(grid_image)
	seed_image = Image.create_from_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, color_seed)
	seed_texture = ImageTexture.create_from_image(seed_image)

	texture = grid_texture
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	var shader := load("res://shaders/pixel_render.gdshader") as Shader
	shader_mat = ShaderMaterial.new()
	shader_mat.shader = shader
	shader_mat.set_shader_parameter("seed_tex", seed_texture)
	shader_mat.set_shader_parameter("frame", 0)
	shader_mat.set_shader_parameter("mat_colors", PALETTE_DEFAULT)
	shader_mat.set_shader_parameter("mat_var", PALETTE_VAR_DEFAULT)
	shader_mat.set_shader_parameter("darkness_mode", 0)  # Pois oletuksena, O-näppäin togglea
	shader_mat.set_shader_parameter("proj_count", 0)
	shader_mat.set_shader_parameter("impact_intensity", 0.0)
	shader_mat.set_shader_parameter("screen_aspect", float(W) / float(SIM_HEIGHT))

	# Sky-visibility tekstuuri — BFS-pohjainen pimeys
	visibility_image = Image.create(W, SIM_HEIGHT, false, Image.FORMAT_R8)
	visibility_tex = ImageTexture.create_from_image(visibility_image)
	shader_mat.set_shader_parameter("visibility_tex", visibility_tex)
	material = shader_mat

	# Fysiikkamoottori
	physics_world = PhysicsWorld.new()

	# Rakennuskerros (skaalataan grid → screen)
	building_layer = Node2D.new()
	building_layer.name = "BuildingLayer"
	add_child(building_layer)

	# Rakennuksen esikatselu
	build_preview = BuildPreview.new()
	build_preview.name = "BuildPreview"
	build_preview.z_index = 10
	building_layer.add_child(build_preview)

	# Pelaaja
	player = PlayerScript.new()
	player.spawn_at_surface(grid, W, SIM_HEIGHT)

	# GPU compute setup
	_setup_compute()

	# Toast-ilmoitus (I-näppäin ja muut pikailmoitukset) — lisätään scene rootiin jotta
	# näkyy kaiken päällä eikä clippaannu TextureRectin sisään
	_toast_label = Label.new()
	_toast_label.add_theme_font_size_override("font_size", 24)
	_toast_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	_toast_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_toast_label.add_theme_constant_override("shadow_offset_x", 2)
	_toast_label.add_theme_constant_override("shadow_offset_y", 2)
	_toast_label.position = Vector2(16, 48)
	_toast_label.z_index = 100
	_toast_label.visible = false
	get_tree().root.add_child(_toast_label)

	# Scenario runner — tarkista cmdline-argumentit
	var args := OS.get_cmdline_user_args()
	for arg in args:
		if arg.begins_with("--scenario="):
			_load_scenario(arg.substr(len("--scenario=")))
			break




func update_launcher_settings() -> void:
	for l in launchers:
		l.launch_speed = launcher_launch_speed
		l.launch_angle_deg = launcher_launch_angle
		l.shaft_speed = launcher_shaft_speed
		l.intake_cooldown = launcher_intake_cooldown


func _setup_compute() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		push_error("RenderingDevice ei saatavilla — vaadi Vulkan-renderer")
		return

	# Lue shader-lähdekoodi suoraan tiedostosta (ei tarvitse editor-importia)
	var glsl_source := FileAccess.get_file_as_string("res://shaders/simulation.glsl")
	if glsl_source.is_empty():
		print("ERROR: Ei voitu lukea simulation.glsl")
		return

	# Poista Godotin #[compute] marker — RDShaderSource ei tarvitse sitä
	glsl_source = glsl_source.replace("#[compute]\n", "")

	var shader_source := RDShaderSource.new()
	shader_source.source_compute = glsl_source

	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	var err_msg := spirv.compile_error_compute
	if err_msg != "":
		print("SHADER COMPILE ERROR: ", err_msg)
		return

	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		print("ERROR: Shader creation failed")
		return

	# Luo GPU-bufferi: jokainen solu = uint32 (seed << 8 | material)
	var gpu_data := PackedByteArray()
	gpu_data.resize(TOTAL * 4)
	for i in TOTAL:
		var cell_val: int = grid[i] | (color_seed[i] << 8)
		gpu_data.encode_u32(i * 4, cell_val)

	grid_buffer = rd.storage_buffer_create(gpu_data.size(), gpu_data)

	# Uniform set
	var uniform := RDUniform.new()
	uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	uniform.binding = 0
	uniform.add_id(grid_buffer)
	uniform_set = rd.uniform_set_create([uniform], shader_rid, 0)

	# Pipeline
	pipeline = rd.compute_pipeline_create(shader_rid)

	gpu_ready = true
	print("GPU compute shader valmis!")

	# Transfer shader setup
	_setup_transfer()


func _setup_transfer() -> void:
	if rd == null:
		return

	var glsl_source := FileAccess.get_file_as_string("res://shaders/transfer.glsl")
	if glsl_source.is_empty():
		print("WARNING: Ei voitu lukea transfer.glsl — käytetään CPU-fallbackia")
		return

	glsl_source = glsl_source.replace("#[compute]\n", "")

	var shader_source := RDShaderSource.new()
	shader_source.source_compute = glsl_source

	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if spirv.compile_error_compute != "":
		print("TRANSFER SHADER ERROR: ", spirv.compile_error_compute)
		return

	transfer_shader_rid = rd.shader_create_from_spirv(spirv)
	if not transfer_shader_rid.is_valid():
		print("ERROR: Transfer shader creation failed")
		return

	# Packed-bufferit: TOTAL tavua kumpikin (pyöristetty 4:n kerrannaiseksi)
	var packed_size := ceili(float(TOTAL) / 4.0) * 4
	var zeros := PackedByteArray()
	zeros.resize(packed_size)
	zeros.fill(0)
	mat_packed_buffer = rd.storage_buffer_create(packed_size, zeros)
	seed_packed_buffer = rd.storage_buffer_create(packed_size, zeros)

	# Uniform set: binding 0 = grid, binding 1 = mat_packed, binding 2 = seed_packed
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u0.binding = 0
	u0.add_id(grid_buffer)

	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u1.binding = 1
	u1.add_id(mat_packed_buffer)

	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u2.binding = 2
	u2.add_id(seed_packed_buffer)

	transfer_uniform_set = rd.uniform_set_create([u0, u1, u2], transfer_shader_rid, 0)
	transfer_pipeline = rd.compute_pipeline_create(transfer_shader_rid)

	transfer_ready = true
	print("Transfer shader valmis!")

	# Käynnistä render compute heti kun transfer on valmis (grid_buffer on luotu)
	_setup_render_compute()


func _setup_render_compute() -> void:
	return  # Render compute ei toimi local RD:n kanssa — käytetään CPU-renderöintiä
	if rd == null or not grid_buffer.is_valid():
		return

	var glsl_source := FileAccess.get_file_as_string("res://shaders/render_compute.glsl")
	if glsl_source.is_empty():
		print("WARNING: Ei voitu lukea render_compute.glsl — käytetään CPU-renderöintiä")
		return

	glsl_source = glsl_source.replace("#[compute]\n", "")

	var shader_source := RDShaderSource.new()
	shader_source.source_compute = glsl_source

	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if spirv.compile_error_compute != "":
		print("RENDER COMPUTE SHADER ERROR: ", spirv.compile_error_compute)
		return

	render_compute_shader_rid = rd.shader_create_from_spirv(spirv)
	if not render_compute_shader_rid.is_valid():
		print("ERROR: Render compute shader creation failed")
		return

	# Luo RGBA8-renderöintitekstuurin GPU:lla
	# TEXTURE_USAGE_STORAGE_BIT: compute voi kirjoittaa
	# TEXTURE_USAGE_SAMPLING_BIT: Texture2DRD voi lukea
	var fmt := RDTextureFormat.new()
	fmt.format = RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	fmt.width = W
	fmt.height = SIM_HEIGHT
	fmt.depth = 1
	fmt.array_layers = 1
	fmt.mipmaps = 1
	fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
	fmt.usage_bits = (
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT |
		RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT |
		RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	)
	render_tex_rid = rd.texture_create(fmt, RDTextureView.new())
	if not render_tex_rid.is_valid():
		print("ERROR: Render texture creation failed")
		return

	# Tyhjennä tekstuuri aluksi (muuten roskaa)
	var clear_data := PackedByteArray()
	clear_data.resize(W * SIM_HEIGHT * 4)
	clear_data.fill(0)
	rd.texture_update(render_tex_rid, 0, clear_data)

	# Uniform set: binding 0 = grid_buffer (luku), binding 1 = rgba_image (kirjoitus)
	var u_grid := RDUniform.new()
	u_grid.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_grid.binding = 0
	u_grid.add_id(grid_buffer)

	var u_img := RDUniform.new()
	u_img.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u_img.binding = 1
	u_img.add_id(render_tex_rid)

	render_compute_uniform_set = rd.uniform_set_create(
		[u_grid, u_img], render_compute_shader_rid, 0
	)
	render_compute_pipeline = rd.compute_pipeline_create(render_compute_shader_rid)

	# render_tex_rid on nyt main RD:llä — Texture2DRD toimii suoraan ilman native handle -kiertotietä
	render_tex_godot = Texture2DRD.new()
	render_tex_godot.texture_rd_rid = render_tex_rid

	# Vaihda TextureRect GPU-tekstuurille — ei enää CPU-kopiointia
	texture = render_tex_godot
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# Materiaalivärjäys tehdään render_compute.glsl:ssä.
	# Overlay-efektit (laser, grav gun, flash, pelaaja) voidaan toteuttaa
	# erillisessä canvas_item-shaderissa myöhemmin.
	material = null

	render_compute_ready = true
	print("Render compute valmis — GPU→GPU, nolla CPU-kopiointia renderöinnissä")


func _show_toast(msg: String, duration: float = 2.5) -> void:
	_toast_label.text = msg
	_toast_label.visible = true
	_toast_timer = duration


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.visible = false

	frame_count += 1
	fps_timer += delta

	# Kirjaa frame-aika ring-bufferiin suorituskykytestausta varten
	_perf_delta_ring[_perf_ring_pos] = delta * 1000.0
	_perf_ring_pos = (_perf_ring_pos + 1) % _PERF_RING_SIZE

	if fps_timer >= 1.0:
		print("FPS:%d | gpu:%.1fms dl:%.1fms gl:%.1fms ul:%.1fms | passes:%d" % [
			Engine.get_frames_per_second(),
			_t_gpu, _t_download, _t_gamelogic, _t_upload_render,
			gpu_passes
		])
		fps_timer = 0.0

	# Screenshake
	_update_screenshake(delta)

	# Kamera: pehmeä zoom + seuraa pelaajaa
	_update_camera(delta)

	# Cooldownit
	if pickaxe_cooldown > 0.0:
		pickaxe_cooldown -= delta
	if mega_drill_cooldown > 0.0:
		mega_drill_cooldown -= delta
	if rocket_cooldown > 0.0:
		rocket_cooldown -= delta
	rifle_cooldown = maxf(rifle_cooldown - delta, 0.0)

	_handle_input(delta)

	if gpu_ready:
		# Ajan nopeus — kerrotaan gpu_passes simulaatiokertoimen mukaan
		var saved_passes := gpu_passes
		gpu_passes = max(1, gpu_passes * int(sim_speed))

		# Vaihe 0: Gravity gun — CPU-veto ja held-merkintä ENNEN GPU-passia
		# Järjestys on kriittinen: HELD-tila täytyy olla gridissä kun GPU simuloi,
		# muuten GPU siirtää pikseleitä ennen kuin CPU ehtii kiinnittää ne.
		if grav_gun_mode > 0:
			# Poista edellisen framen held-pikselit
			_grav_erase_held()
			# Nappaa pikselit held-listaan koko grav_gun_radius alueelta ja merkitse HELD
			_grav_capture()
			_grav_write_held()
			paint_pending = true

		# Vaihe 1: CA-simulaatio GPU:lla
		# Maalaukset ladataan ennen simulaatiota jos paint_pending
		if paint_pending:
			_upload_paint_to_gpu()
			paint_pending = false

		var _t0 := Time.get_ticks_usec()
		_simulate_gpu()
		_t_gpu = float(Time.get_ticks_usec() - _t0) / 1000.0
		gpu_passes = saved_passes

		# Lataa tulos takaisin CPU:lle
		_t0 = Time.get_ticks_usec()
		_download_from_gpu()
		_t_download = float(Time.get_ticks_usec() - _t0) / 1000.0

		# Vaihe 2b: Skannaa kivi-kappaleet ensimmäisellä framella (tai resetin jälkeen)
		_t0 = Time.get_ticks_usec()
		if not physics_initialized:
			physics_world.scan_stone_bodies(grid, color_seed, W, SIM_HEIGHT)
			physics_initialized = true

		# Vaihe 3: Rigid body -fysiikka (vain aktiivisille kappaleille)
		var grid_modified := false
		if not physics_world.bodies.is_empty():
			var has_active := false
			for body_id in physics_world.bodies:
				var body: RigidBodyData = physics_world.bodies[body_id]
				if not body.is_sleeping and not body.is_static:
					has_active = true
					break
			if has_active:
				physics_world.step(grid, color_seed, W, SIM_HEIGHT)
				grid_modified = true

		# Vaihe 4: Puun tuki joka 10. frame
		if frame_count > 60 and frame_count % 120 == 0:
			if WoodSupport.check_support(grid, W, SIM_HEIGHT):
				grid_modified = true

		# Vaihe 5: Vauriotarkistus (vain räjähdyksen jälkeen)
		if physics_world.force_damage_check and not physics_world.bodies.is_empty():
			physics_world.check_damage(grid, color_seed, W, SIM_HEIGHT)
			physics_world.force_damage_check = false
			grid_modified = true

		# Vaihe 5b: Jatka jonotettuja splittauksia myös seuraavilla frameilla
		if physics_world.process_damage_queue(grid, color_seed, W, SIM_HEIGHT):
			grid_modified = true

		# Vaihe 5.5: Liukuhihnat (skaalautuu ajan nopeuden mukaan)
		if _update_conveyors(delta * sim_speed):
			grid_modified = true

		# Vaihe 5.6: Uunit ja kaivokset
		if _update_furnaces(delta * sim_speed):
			grid_modified = true
		if _update_sand_mines(delta * sim_speed):
			grid_modified = true

		# Vaihe 5.65: Money exitit ja murskaajat
		if _update_money_exits(delta * sim_speed):
			grid_modified = true
		if _update_crushers(delta * sim_speed):
			grid_modified = true

		# Vaihe 5.7: Hissilinkot + lentävät pikselit
		if not launchers.is_empty() or not flying_pixels.is_empty():
			if _update_launchers_and_flying(delta * sim_speed):
				grid_modified = true
		# Projektiilivalaistus — päivitetään jokainen frame
		_update_proj_lights()

		# Visibility: käynnistä uusi laskenta kun dirty, hae valmis tulos threadista
		if visibility_dirty:
			visibility_dirty = false
			_update_visibility_map()
		elif _vis_thread != null and not _vis_thread.is_alive():
			_update_visibility_map()  # Hakee tuloksen ja mahdollisesti käynnistää seuraavan

		_t_gamelogic = float(Time.get_ticks_usec() - _t0) / 1000.0

		# Vaihe 6: Lataa CPU:n muutokset GPU:lle — yhdistetty lataus
		# paint_pending voi asettua uudelleen logiikan aikana (esim. explode())
		# grid_modified = fysiikka/logiikka muutti gridiä
		# → ladataan kerran kattaen molemmat, ei koskaan kahdesti per frame
		if grid_modified or paint_pending:
			_upload_paint_to_gpu()
			paint_pending = false

	# Pelaajan päivitys (vain player modessa)
	if not god_mode:
		player.update(grid, W, SIM_HEIGHT)

	# Scenario runner — ajetaan ennen renderöintiä jotta fill_rect näkyy heti
	if _scenario_active:
		_scenario_tick()

	var _t0_ul := Time.get_ticks_usec()
	_upload_render()
	_t_upload_render = float(Time.get_ticks_usec() - _t0_ul) / 1000.0

	# Vaihe 7: Rakennuksen esikatselu
	_update_build_preview()

	# Päivitä rakennuskerroksen skaalaus (grid → screen)
	if building_layer and size.x > 0:
		building_layer.scale = Vector2(size.x / float(W), size.y / float(SIM_HEIGHT))


func _handle_input(delta: float) -> void:
	# Estä toiminnot kun hiiri on UI-paneelin päällä
	if ui_panel and ui_panel.get_global_rect().has_point(get_viewport().get_mouse_position()):
		prev_left_pressed = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		grav_gun_mode = 0
		return
	var left_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var left_just := left_pressed and not prev_left_pressed
	var right_just := right_pressed and not prev_right_pressed

	# Nollaa grav_gun jos vaihdettu pois Gravity Gun -aseesta
	if current_weapon != Weapon.GRAVITY_GUN and grav_gun_mode > 0:
		grav_gun_mode = 0
		grav_held.clear()
		grav_held_written.clear()

	# Oikea hiiri — käytä valittua asetta AINA
	if true:
		var coords := _mouse_to_grid()
		match current_weapon:
			Weapon.PICKAXE:
				if right_pressed and coords.x >= 0:
					current_tool = Tool.PICKAXE
					var dig_pos := _player_adjacent_dig_pos(coords, 3)
					_cut(dig_pos.x, dig_pos.y)
			Weapon.MEGA_DRILL:
				if right_pressed and coords.x >= 0 and mega_drill_cooldown <= 0.0:
					current_tool = Tool.MEGA_DRILL
					var dig_pos := _player_adjacent_dig_pos(coords, 4)
					_cut(dig_pos.x, dig_pos.y)
					mega_drill_cooldown = MEGA_DRILL_COOLDOWN_TIME
			Weapon.RIFLE:
				if right_pressed and coords.x >= 0 and rifle_cooldown <= 0.0:
					var origin := cam_grid_pos if god_mode else Vector2(player.get_grid_pos()) + Vector2(2.0, 3.0)
					var dir := (Vector2(coords) - origin).normalized()
					if dir.length_squared() < 0.01:
						dir = Vector2(1, 0)
					var spawn_pos := origin + dir * 5.0
					if flying_pixels.size() < flying_max_count:
						flying_pixels.append({
							"pos": spawn_pos,
							"vel": dir * 420.0,
							"mat": MAT_STONE,
							"seed": randi() % 256,
							"age": 0.0,
							"type": "bullet"
						})
					add_trauma(0.18)  # Recoil
					rifle_cooldown = RIFLE_COOLDOWN_TIME
			Weapon.ROCKET:
				if right_pressed:
					_fire_rocket_at_cursor()
			Weapon.GRAVITY_GUN:
				if right_pressed and coords.x >= 0:
					var current_pos := Vector2(coords)
					mouse_velocity = current_pos - prev_mouse_grid
					prev_mouse_grid = current_pos
					if Input.is_key_pressed(KEY_SHIFT):
						grav_gun_mode = 2
					else:
						grav_gun_mode = 1
					grav_gun_pos = coords
					var radius := float(grav_gun_vacuum_radius if grav_gun_mode == 2 else grav_gun_radius)
					var strength := grav_gun_body_strength * (2.5 if grav_gun_mode == 2 else 1.0)
					physics_world.apply_attraction(Vector2(coords), radius, strength)
				elif grav_gun_mode > 0:
					# Vapauta held-pikselit
					_grav_release()
					# Heitä jos hiiri liikkui
					if mouse_velocity.length() > 0.5:
						var was_vacuum := grav_gun_mode == 2
						var throw_mult := 6.0 if was_vacuum else 4.0
						var body_mult := 5.0 if was_vacuum else 3.0
						var radius := grav_gun_vacuum_radius if was_vacuum else grav_gun_radius
						_throw_pixels(grav_gun_pos, radius, mouse_velocity * throw_mult)
						physics_world.apply_throw(Vector2(grav_gun_pos), float(radius), mouse_velocity * body_mult)
					grav_gun_mode = 0
					mouse_velocity = Vector2.ZERO

	# laser_mode pois käytöstä (shader-efekti poistettu)
	laser_mode = false

	# Rakennustilan klikkaus — vain kun ei lukossa
	if left_just and build_mode != BUILD_NONE and not block_paint:
		var coords := _mouse_to_grid()
		if coords.x >= 0:
			var grid_pos := Vector2(coords)
			if build_mode == BUILD_CONVEYOR_START:
				conveyor_start_pos = _snap_to_belt_end(_snap_to_grid(grid_pos))
				build_mode = BUILD_CONVEYOR_END
				block_paint = true
			elif build_mode == BUILD_CONVEYOR_END:
				var end_pos := _snap_to_belt_end(_snap_to_grid(grid_pos))
				end_pos = _constrain_45(conveyor_start_pos, end_pos)
				_create_conveyor(conveyor_start_pos, end_pos)
				# Jää hihna-moodiin — valmis sijoittamaan seuraavan
				build_mode = BUILD_CONVEYOR_START
				block_paint = true
			elif build_mode == BUILD_SAND_MINE:
				_place_sand_mine(grid_pos)
				block_paint = true
			elif build_mode == BUILD_FURNACE:
				_place_furnace(grid_pos)
				block_paint = true
			elif build_mode == BUILD_SLING:
				_handle_launcher_click(Vector2(coords))
				block_paint = true
			elif build_mode == BUILD_WALL_START:
				wall_start_pos = _snap_to_grid(grid_pos)
				build_mode = BUILD_WALL_END
				block_paint = true
			elif build_mode == BUILD_WALL_END:
				var end_pos := _snap_to_grid(grid_pos)
				_create_wall(wall_start_pos, end_pos)
				# Jää seinä-moodiin — valmis piirtämään seuraavan
				build_mode = BUILD_WALL_START
				block_paint = true
			elif build_mode == BUILD_MONEY_EXIT:
				_place_money_exit(grid_pos)
				block_paint = true
			elif build_mode == BUILD_CRUSHER:
				_place_crusher(grid_pos)
				block_paint = true

	if left_pressed and not block_paint and not laser_mode and build_mode == BUILD_NONE:
		var coords := _mouse_to_grid()
		if coords.x >= 0:
			if current_material == MAT_STONE:
				is_painting_stone = true
			_paint(coords.x, coords.y, current_material)
	elif not left_pressed and not right_pressed:
		# Hiiri päästetty irti — luo kappale piirtovedosta
		if is_painting_stone and not stroke_stone_pixels.is_empty():
			_create_stroke_body()
			stroke_stone_pixels.clear()
		is_painting_stone = false
		block_paint = false

	prev_left_pressed = left_pressed
	prev_right_pressed = right_pressed


func _handle_explosion_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			var coords := _mouse_to_grid()
			if coords.x >= 0:
				var size_idx := explosion_size
				if event.shift_pressed:
					size_idx = 3  # Mega aina Shiftillä
				var radius: int = EXPLOSION_RADII[clampi(size_idx, 0, 3)]
				explode(coords.x, coords.y, radius)
		# Scroll: Shift = räjähdyskoko, normaali = zoom
		elif event.shift_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			explosion_size = mini(explosion_size + 1, 3)
			print("Räjähdyskoko: %d (r=%d)" % [explosion_size, EXPLOSION_RADII[explosion_size]])
		elif event.shift_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			explosion_size = maxi(explosion_size - 1, 0)
			print("Räjähdyskoko: %d (r=%d)" % [explosion_size, EXPLOSION_RADII[explosion_size]])
		elif not event.shift_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			target_zoom = clampf(target_zoom * 1.2, 1.0, 10.0)
		elif not event.shift_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			target_zoom = clampf(target_zoom / 1.2, 1.0, 10.0)


func _mouse_to_grid() -> Vector2i:
	var mp := get_local_mouse_position()
	# TextureRect:n todellinen koko huomioiden stretch
	var tex_size := size
	var gx := int(mp.x / tex_size.x * W)
	var gy := int(mp.y / tex_size.y * SIM_HEIGHT)
	if gx < 0 or gx >= W or gy < 0 or gy >= SIM_HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func set_palette(palette: Array) -> void:
	# Vaihda väripaletti välittömästi
	current_palette = palette
	shader_mat.set_shader_parameter("mat_colors", palette)


func lerp_palette(from_palette: Array, to_palette: Array, t: float) -> void:
	# Interpoloi kahden paletin välillä — t: 0.0 = from, 1.0 = to
	var blended: Array = []
	for i in range(from_palette.size()):
		blended.append(from_palette[i].lerp(to_palette[i], t))
	shader_mat.set_shader_parameter("mat_colors", blended)


func clear_world() -> void:
	grid.fill(0)
	for i in TOTAL:
		color_seed[i] = randi() % 256
	paint_pending = true
	# Nollaa fysiikkamaailma
	physics_world = PhysicsWorld.new()
	physics_initialized = false
	_clear_conveyors()
	_clear_buildings()
	building_pixels.clear()
	build_mode = BUILD_NONE
	build_menu_visible = false
	player.spawn_at_surface(grid, W, SIM_HEIGHT)


# === SCREENSHAKE ===

func _update_screenshake(delta: float) -> void:
	# Fyysinen shake (recoil) — pienenee nopeasti
	if trauma > 0.0:
		trauma = maxf(trauma - delta * 4.0, 0.0)
		var shake_amount := trauma * trauma
		var max_px := 2.0
		shake_offset.x = randf_range(-1.0, 1.0) * max_px * shake_amount
		shake_offset.y = randf_range(-1.0, 1.0) * max_px * shake_amount
	else:
		shake_offset = Vector2.ZERO
	# CA flash (osumasta) — vääntyy ruutu ilman fyysistä heilumista
	if ca_flash > 0.0:
		ca_flash = maxf(ca_flash - delta * 5.0, 0.0)
	shader_mat.set_shader_parameter("shake_intensity", ca_flash)
	# Impakti-CA haipuu nopeasti
	if impact_intensity > 0.0:
		impact_intensity = maxf(impact_intensity - delta * 6.0, 0.0)
	shader_mat.set_shader_parameter("impact_intensity", impact_intensity)
	shader_mat.set_shader_parameter("impact_uv", impact_uv)
	shader_mat.set_shader_parameter("impact_type", impact_type_val)


# === KAMERA / ZOOM ===

func _update_camera(delta: float) -> void:
	var viewport_size := get_viewport_rect().size
	if viewport_size.x <= 0.0:
		return
	size = viewport_size

	if god_mode:
		# God mode — WASD liikuttaa kameraa vapaasti
		var spd := 300.0 / zoom_level
		if Input.is_key_pressed(KEY_SHIFT): spd *= 3.0
		var dir := Vector2.ZERO
		if Input.is_key_pressed(KEY_A): dir.x -= 1.0
		if Input.is_key_pressed(KEY_D): dir.x += 1.0
		if Input.is_key_pressed(KEY_W): dir.y -= 1.0
		if Input.is_key_pressed(KEY_S): dir.y += 1.0
		cam_vel = cam_vel.lerp(dir * spd, 12.0 * delta)
		cam_grid_pos += cam_vel * delta
		cam_grid_pos.x = clampf(cam_grid_pos.x, 0.0, float(W))
		cam_grid_pos.y = clampf(cam_grid_pos.y, 0.0, float(SIM_HEIGHT))
	else:
		# Player mode — kamera seuraa pelaajaa
		cam_vel = Vector2.ZERO
		cam_grid_pos = player.position

	# Portaaton zoom — lerp kohti target_zoom
	zoom_level = lerpf(zoom_level, target_zoom, 15.0 * delta)

	if zoom_level <= 1.01 and target_zoom <= 1.01:
		scale = Vector2.ONE
		position = shake_offset
		camera_offset = Vector2.ZERO
		return

	# Laske offset niin että cam_grid_pos on ruudun keskellä
	var nx: float = cam_grid_pos.x / float(W)
	var ny: float = cam_grid_pos.y / float(SIM_HEIGHT)
	var ox: float = viewport_size.x * 0.5 - nx * viewport_size.x * zoom_level
	var oy: float = viewport_size.y * 0.5 - ny * viewport_size.y * zoom_level
	ox = clampf(ox, viewport_size.x - viewport_size.x * zoom_level, 0.0)
	oy = clampf(oy, viewport_size.y - viewport_size.y * zoom_level, 0.0)
	camera_offset = Vector2(ox, oy)

	scale = Vector2(zoom_level, zoom_level)
	position = camera_offset + shake_offset * zoom_level


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)



func _update_visibility_map() -> void:
	# Jos thread vielä pyörii, älä käynnistä uutta
	if _vis_thread != null and _vis_thread.is_alive():
		return
	# Hae edellisen threadin tulos jos valmis
	if _vis_thread != null:
		_vis_thread.wait_to_finish()
		_vis_thread = null
		if _vis_result.size() == W * SIM_HEIGHT:
			visibility_image.set_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, _vis_result)
			visibility_tex.update(visibility_image)
	# Käynnistä uusi laskenta threadissa
	var grid_snapshot := grid.duplicate()
	_vis_thread = Thread.new()
	_vis_thread.start(_bfs_thread.bind(grid_snapshot))

func _bfs_thread(g: PackedByteArray) -> void:
	var dist := PackedByteArray()
	dist.resize(W * SIM_HEIGHT)
	dist.fill(255)
	var queue := PackedInt32Array()
	queue.resize(W * SIM_HEIGHT)
	var q_head := 0
	var q_tail := 0
	# Irtomateriaalit läpäisevät valoa — eivät luo täyttä varjoa
	# EMPTY=0, SAND=1, WATER=2, FIRE=5, OIL=6, STEAM=7, ASH=8, WOOD_FALLING=9
	# Siemenet: joka sarakkeessa skannaa ylhäältä alas kunnes osuu kiinteään
	# (maailma ei ala y=0:sta, pintamaa voi olla missä tahansa)
	for x in range(W):
		for y in range(SIM_HEIGHT):
			var idx := y * W + x
			var m := int(g[idx])
			if m == 0 or m == 1 or m == 2 or m == 5 or m == 6 or m == 7 or m == 8 or m == 9:
				dist[idx] = 0
				queue[q_tail] = idx
				q_tail += 1
			else:
				break  # Ensimmäinen kiinteä pikseli — lopeta tämä sarake
	# BFS läpinäkyvien pikselien läpi (tyhjät + irtomateriaalit)
	while q_head < q_tail:
		var idx := queue[q_head]
		q_head += 1
		var d := int(dist[idx])
		if d >= 250:
			continue
		var x := idx % W
		var y := idx / W
		if x > 0:
			var n := idx - 1
			var m := int(g[n])
			if dist[n] == 255 and (m == 0 or m == 1 or m == 2 or m == 5 or m == 6 or m == 7 or m == 8 or m == 9):
				dist[n] = 0
				queue[q_tail] = n
				q_tail += 1
		if x < W - 1:
			var n := idx + 1
			var m := int(g[n])
			if dist[n] == 255 and (m == 0 or m == 1 or m == 2 or m == 5 or m == 6 or m == 7 or m == 8 or m == 9):
				dist[n] = 0
				queue[q_tail] = n
				q_tail += 1
		if y > 0:
			var n := idx - W
			var m := int(g[n])
			if dist[n] == 255 and (m == 0 or m == 1 or m == 2 or m == 5 or m == 6 or m == 7 or m == 8 or m == 9):
				dist[n] = 0
				queue[q_tail] = n
				q_tail += 1
		if y < SIM_HEIGHT - 1:
			var n := idx + W
			var m := int(g[n])
			if dist[n] == 255 and (m == 0 or m == 1 or m == 2 or m == 5 or m == 6 or m == 7 or m == 8 or m == 9):
				dist[n] = 0
				queue[q_tail] = n
				q_tail += 1
	# Vaihe 2: Levitä taivasyhteydestä 25px kaikkeen (kivet + eristetyt alueet)
	const MAX_VIS := 25
	var q2 := PackedInt32Array()
	q2.resize(W * SIM_HEIGHT)
	var q2h := 0
	var q2t := 0
	for i in range(W * SIM_HEIGHT):
		if dist[i] == 0:
			q2[q2t] = i
			q2t += 1
	while q2h < q2t:
		var idx := q2[q2h]; q2h += 1
		var d := int(dist[idx])
		if d >= MAX_VIS:
			continue
		var x := idx % W
		var y := idx / W
		if x > 0 and dist[idx - 1] == 255:
			dist[idx - 1] = d + 1
			q2[q2t] = idx - 1; q2t += 1
		if x < W - 1 and dist[idx + 1] == 255:
			dist[idx + 1] = d + 1
			q2[q2t] = idx + 1; q2t += 1
		if y > 0 and dist[idx - W] == 255:
			dist[idx - W] = d + 1
			q2[q2t] = idx - W; q2t += 1
		if y < SIM_HEIGHT - 1 and dist[idx + W] == 255:
			dist[idx + W] = d + 1
			q2[q2t] = idx + W; q2t += 1
	_vis_result = dist

func add_ca_flash(amount: float) -> void:
	ca_flash = maxf(ca_flash, amount)  # Ei kumuloidu — ottaa suurimman arvon

func set_impact(world_pos: Vector2, intensity: float, itype: int) -> void:
	impact_uv = Vector2(world_pos.x / float(W), world_pos.y / float(SIM_HEIGHT))
	impact_intensity = maxf(impact_intensity, intensity)
	impact_type_val = itype


# === RÄJÄHDYKSET ===

func explode(cx: int, cy: int, radius: int) -> void:
	var r2 := radius * radius
	var inner_r2 := int(radius * 0.65) * int(radius * 0.65)  # Sisäalue = tyhjää

	for dy in range(-radius, radius + 1):
		var ny := cy + dy
		if ny < 0 or ny >= SIM_HEIGHT:
			continue
		var row := ny * W
		for dx in range(-radius, radius + 1):
			var dist2 := dx * dx + dy * dy
			if dist2 > r2:
				continue
			var nx := cx + dx
			if nx < 0 or nx >= W:
				continue
			var idx := row + nx
			var mat := grid[idx]

			if mat == MAT_EMPTY:
				continue
			# Suojatut rakennuspikselit eivät tuhoudu räjähdyksessä
			if building_pixels.has(idx):
				continue

			if dist2 <= inner_r2:
				# Sisäalue: tyhjennä kokonaan
				if mat == MAT_OIL:
					grid[idx] = MAT_FIRE  # Öljy syttyy!
				elif mat == MAT_STONE:
					# Kivi hajoaa: soraa
					grid[idx] = MAT_GRAVEL
					if physics_world.body_map.size() > idx:
						physics_world.body_map[idx] = 0
				else:
					grid[idx] = MAT_EMPTY
					# Poista body_map-merkintä
					if physics_world.body_map.size() > idx:
						physics_world.body_map[idx] = 0
			else:
				# Ulkoreuna: debris-konversio
				if mat == MAT_STONE:
					grid[idx] = MAT_GRAVEL  # Kivi → sora
					if physics_world.body_map.size() > idx:
						physics_world.body_map[idx] = 0
				elif mat == MAT_WOOD:
					grid[idx] = MAT_WOOD_FALLING  # Puu → putoava puu
				elif mat == MAT_OIL:
					grid[idx] = MAT_FIRE  # Öljy syttyy reunallakin!

	# Impulssit olemassaoleville rigid bodyille
	physics_world.apply_explosion_impulse(
		Vector2(cx, cy), float(radius), float(radius) * 0.5
	)

	# Etsi irronneet kivipalat räjähdyksen ympäriltä → luo rigid bodyt
	_detect_detached_stone(cx, cy, radius)

	# Räjähdys: CA-flash skaalautuu koon mukaan (ei fyysistä shakea)
	var ca_amount := EXPLOSION_TRAUMA[clampi(explosion_size, 0, 3)]
	add_ca_flash(ca_amount)

	# Räjähdysflash
	flash_pos = Vector2(float(cx) / float(W), float(cy) / float(SIM_HEIGHT))
	flash_radius = float(radius) / float(W) * 1.5
	flash_timer = FLASH_DURATION

	paint_pending = true


# === LASERI ===

func _player_adjacent_dig_pos(target_grid: Vector2i, reach: int) -> Vector2i:
	if god_mode:
		return target_grid
	var player_center := Vector2(player.get_grid_pos()) + Vector2(2.0, 3.0)
	var target_f := Vector2(target_grid)
	var dist := player_center.distance_to(target_f)
	if dist <= float(reach):
		return target_grid
	var dir := (target_f - player_center).normalized()
	return Vector2i(player_center + dir * float(reach))


func _bullet_impact(cx: int, cy: int) -> void:
	# Pieni tuhoalue — 2px säde
	const IMPACT_R := 2
	for dy in range(-IMPACT_R, IMPACT_R + 1):
		var ny := cy + dy
		if ny < 0 or ny >= SIM_HEIGHT:
			continue
		for dx in range(-IMPACT_R, IMPACT_R + 1):
			if dx * dx + dy * dy > IMPACT_R * IMPACT_R:
				continue
			var nx := cx + dx
			if nx < 0 or nx >= W:
				continue
			var idx := ny * W + nx
			if building_pixels.has(idx):
				continue
			var mat := grid[idx]
			if mat != MAT_EMPTY:
				if mat == MAT_STONE:
					# Kivi hajoaa luodista: soraa
					grid[idx] = MAT_GRAVEL
				else:
					grid[idx] = MAT_EMPTY
					if physics_world.body_map.size() > idx:
						physics_world.body_map[idx] = 0
	add_trauma(0.03)   # Mikroskooppinen osumashake
	add_ca_flash(0.7)
	set_impact(Vector2(cx, cy), 0.75, 0)
	paint_pending = true


func _fire_rocket_at_cursor() -> void:
	if rocket_cooldown > 0.0:
		return
	var mp := get_local_mouse_position()
	var tex_size := size
	var mouse_grid := Vector2(mp.x / tex_size.x * float(W), mp.y / tex_size.y * float(SIM_HEIGHT))
	var origin := cam_grid_pos if god_mode else Vector2(player.get_grid_pos()) + Vector2(2.0, 3.0)
	var dir := (mouse_grid - origin).normalized()
	if dir.length_squared() < 0.01:
		dir = Vector2(1, 0)
	if flying_pixels.size() < flying_max_count:
		flying_pixels.append({
			"pos": origin + dir * 8.0,
			"vel": dir * 180.0,
			"mat": MAT_STONE,
			"seed": randi() % 256,
			"age": 0.0,
			"type": "rocket"
		})
	add_trauma(0.25)
	rocket_cooldown = 0.12


func _fire_laser(start: Vector2i, end: Vector2i) -> void:
	# Bresenham-viiva paksuudella
	var points := _bresenham_line(start.x, start.y, end.x, end.y)
	var dx_line := float(end.x - start.x)
	var dy_line := float(end.y - start.y)
	var line_len := sqrt(dx_line * dx_line + dy_line * dy_line)
	if line_len < 1.0:
		return

	# Normaali (kohtisuora viivaan)
	var nx := -dy_line / line_len
	var ny := dx_line / line_len

	var has_stone := false
	var min_x := mini(start.x, end.x) - LASER_WIDTH
	var max_x := maxi(start.x, end.x) + LASER_WIDTH
	var min_y := mini(start.y, end.y) - LASER_WIDTH
	var max_y := maxi(start.y, end.y) + LASER_WIDTH

	# Tuhoa pikselit viivan varrella
	for p in points:
		for offset in range(-LASER_WIDTH / 2, LASER_WIDTH / 2 + 1):
			var px := p.x + int(nx * float(offset))
			var py := p.y + int(ny * float(offset))
			if px < 0 or px >= W or py < 0 or py >= SIM_HEIGHT:
				continue
			var idx := py * W + px
			var mat := grid[idx]
			if mat == MAT_EMPTY:
				continue
			# Suojatut rakennuspikselit eivät tuhoudu laserilla
			if building_pixels.has(idx):
				continue
			match mat:
				MAT_STONE:
					# Kivi hajoaa laserilla: soraa
					grid[idx] = MAT_GRAVEL
					has_stone = true
				MAT_WOOD, MAT_WOOD_FALLING:
					grid[idx] = MAT_FIRE
				MAT_OIL:
					grid[idx] = MAT_FIRE
				MAT_WATER:
					grid[idx] = MAT_STEAM
				MAT_SAND, MAT_ASH:
					grid[idx] = MAT_EMPTY
				MAT_FIRE, MAT_STEAM:
					pass  # Ohita

	# Kivi-split: etsi irtonaiset kappaleet
	if has_stone:
		var center_x := (start.x + end.x) / 2
		var center_y := (start.y + end.y) / 2
		var search_radius := int(line_len / 2.0) + LASER_WIDTH + 5
		_detect_detached_stone(center_x, center_y, search_radius)

	# Visuaaliset efektit
	laser_beam_timer = LASER_BEAM_DURATION
	add_trauma(0.06)  # Pieni recoil laserille

	# Flash viivan keskipisteessä
	var mid_x := float(start.x + end.x) * 0.5
	var mid_y := float(start.y + end.y) * 0.5
	flash_pos = Vector2(mid_x / float(W), mid_y / float(SIM_HEIGHT))
	flash_radius = line_len / float(W) * 0.5
	flash_timer = FLASH_DURATION

	paint_pending = true


# Bresenham-viiva
func _bresenham_line(x0: int, y0: int, x1: int, y1: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var cx := x0
	var cy := y0
	while true:
		result.append(Vector2i(cx, cy))
		if cx == x1 and cy == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return result


# Lähin piste viivalla (kanatarkistukseen)
func _closest_point_on_line(point: Vector2, a: Vector2, b: Vector2) -> Vector2:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.001:
		return a
	var t := clampf((point - a).dot(ab) / len2, 0.0, 1.0)
	return a + ab * t


func regenerate_world() -> void:
	grid.fill(0)
	for i in TOTAL:
		color_seed[i] = randi() % 256
	WorldGen.generate(grid, color_seed, W, SIM_HEIGHT)
	shader_mat.set_shader_parameter("surface_y_norm", WorldGen.surface_height_ratio)
	paint_pending = true
	physics_world = PhysicsWorld.new()
	physics_initialized = false
	_clear_conveyors()
	_clear_buildings()
	build_mode = BUILD_NONE
	build_menu_visible = false
	player.spawn_at_surface(grid, W, SIM_HEIGHT)
	print("Maailma regeneroitu!")


# Suorituskykytesti: generoi maailma → odota asettumista → räjäytä 3 kertaa → mittaa frame-spiikit.
# Käynnistys: P-näppäin. Käyttää await-kutsuihin coroutinea.
func _run_perf_explosion_test() -> void:
	print("=== RÄJÄHDYSTESTI KÄYNNISTYY ===")
	print("Generoidaan maailma...")

	# Generoi uusi maailma (sama kuin R-näppäin)
	regenerate_world()

	# Odota 0.5 sekuntia jotta simulaatio asettuu
	await get_tree().create_timer(0.5).timeout

	# Maanpinta on noin y = SIM_HEIGHT * 0.45 — räjäytä sen läheltä
	var surface_y: int = int(float(SIM_HEIGHT) * 0.45)
	# Räjähdyspisteet: vasen, keski, oikea — kaikki lähellä pintaa
	var blast_points: Array[Vector2i] = [
		Vector2i(int(W * 0.25), surface_y + 5),
		Vector2i(int(W * 0.50), surface_y + 5),
		Vector2i(int(W * 0.75), surface_y + 5),
	]
	var blast_radius := 20
	# Kuinka monta framea seurataan räjähdyksen jälkeen
	const WATCH_FRAMES := 10

	print("=== RÄJÄHDYSTESTI ===")
	var results: Array[String] = []

	for i in blast_points.size():
		var bp: Vector2i = blast_points[i]

		# Nollaa ring-puskuri ennen räjähdystä jotta vanhat arvot eivät vaikuta
		_perf_delta_ring.fill(0.0)
		_perf_ring_pos = 0

		# Räjäytä
		explode(bp.x, bp.y, blast_radius)
		paint_pending = true  # Pakota GPU-lataus heti

		# Seuraa seuraavat WATCH_FRAMES framea ja kerää delta-ajat
		var worst_ms: float = 0.0
		for _f in WATCH_FRAMES:
			await get_tree().process_frame
			# Ring-puskurin viimeisin arvo vastaa juuri ajettua framea
			var last_idx: int = (_perf_ring_pos - 1 + _PERF_RING_SIZE) % _PERF_RING_SIZE
			var frame_ms: float = _perf_delta_ring[last_idx]
			if frame_ms > worst_ms:
				worst_ms = frame_ms

		# Arvioi tulos: tavoite alle 16ms (60 fps)
		var status: String = "OK" if worst_ms < 16.0 else "LIIAN HIDAS"
		var line: String = "Räjähdys %d (x=%d y=%d r=%d): max spike %.1fms (%s)" % [
			i + 1, bp.x, bp.y, blast_radius, worst_ms, status
		]
		results.append(line)
		print(line)

		# Lyhyt tauko räjähdysten välillä
		await get_tree().create_timer(0.3).timeout

	print("=====================")
	# Yhteenveto: pahin spike kaikista räjähdyksistä
	var global_worst: float = 0.0
	for line in results:
		# Etsi numero ennen "ms" merkkijonosta
		var ms_idx: int = line.find("ms")
		if ms_idx > 0:
			var num_start: int = line.rfind(" ", ms_idx - 1) + 1
			var val: float = float(line.substr(num_start, ms_idx - num_start))
			if val > global_worst:
				global_worst = val
	print("Pahin spike: %.1fms — tavoite <16ms" % global_worst)
	print("=== TESTI VALMIS ===")


# Luo kappale piirtovedosta — jokainen vedos on oma kappaleensa
func _create_stroke_body() -> void:
	# Kerää uniikit pikselit
	var pixels: Array[Vector2i] = []
	for p in stroke_stone_pixels:
		pixels.append(p)

	if pixels.size() < 4:
		return  # Liian pieni

	# CCL: etsi yhtenäiset komponentit (jos vedos on epäyhtenäinen)
	var components := CCL.check_connectivity(pixels)

	for component in components:
		var comp_pixels: Array[Vector2i] = component
		if comp_pixels.size() < 4:
			continue

		var seeds := PackedByteArray()
		seeds.resize(comp_pixels.size())
		for i in comp_pixels.size():
			var p: Vector2i = comp_pixels[i]
			seeds[i] = color_seed[p.y * W + p.x]

		physics_world._ensure_body_map(W, SIM_HEIGHT)
		var body := physics_world.create_body(comp_pixels, seeds, MAT_STONE)
		if body:
			body.is_static = not stone_dynamic
			body.is_sleeping = not stone_dynamic
			# Rekisteröi body_map
			for p in comp_pixels:
				physics_world.body_map[p.y * W + p.x] = body.body_id


func _input(event: InputEvent) -> void:
	# Räjähdykset (keskihiiri + scroll)
	_handle_explosion_input(event)

	# Näppäimet — _input:ssa jotta UI ei syö niitä
	if event is InputEventKey and event.pressed:
		# Rakennusvalikko auki — omat näppäimet
		if build_menu_visible:
			match event.keycode:
				KEY_1:
					build_mode = BUILD_SPAWNER
					build_menu_visible = false
					block_paint = true
					print("Rakennustila: SPAWNER — klikkaa paikkaa")
				KEY_2:
					build_mode = BUILD_CONVEYOR_START
					build_menu_visible = false
					block_paint = true
					print("Rakennustila: LIUKUHIHNA — klikkaa alkupiste")
				KEY_3:
					build_mode = BUILD_SAND_MINE
					build_menu_visible = false
					block_paint = true
				KEY_4:
					build_mode = BUILD_FURNACE
					build_menu_visible = false
					block_paint = true
				KEY_5:
					build_mode = BUILD_SLING
					launcher_phase = 1
					build_menu_visible = false
					block_paint = true
					print("Rakennustila: HISSI-LINKO — klikkaa pohja")
				KEY_6:
					build_mode = BUILD_WALL_START
					build_menu_visible = false
					block_paint = true
					print("Rakennustila: SEINÄ — klikkaa alkupiste")
				KEY_7:
					build_mode = BUILD_MONEY_EXIT
					build_menu_visible = false
					block_paint = true
					print("Rakennustila: MONEY EXIT — klikkaa paikkaa")
				KEY_8:
					build_mode = BUILD_CRUSHER
					build_menu_visible = false
					block_paint = true
					print("Rakennustila: MURSKAAJA — klikkaa paikkaa")
				KEY_ESCAPE, KEY_B:
					build_menu_visible = false
					build_mode = BUILD_NONE
					launcher_phase = 0
					print("Rakennusvalikko suljettu")
			return

		match event.keycode:
			KEY_1: current_material = MAT_SAND
			KEY_2: current_material = MAT_WATER
			KEY_3: current_material = MAT_STONE
			KEY_4: current_material = MAT_WOOD
			KEY_5: current_material = MAT_FIRE
			KEY_6: current_material = MAT_OIL
			KEY_7: current_material = MAT_DIRT
			KEY_8: current_material = MAT_IRON_ORE
			KEY_9: current_material = MAT_GOLD_ORE
			KEY_E: current_material = MAT_EMPTY
			KEY_T:
				# Vaihda kaivaustyökalu HAND→SHOVEL→PICKAXE→DRILL→MEGA_DRILL→HAND
				current_tool = (current_tool + 1) % 5 as Tool
				var tool_names: Array[String] = ["KÄSI", "LAPIO", "HAKKU", "PORA", "MEGAPORA"]
				print("Kaivaustyökalu: %s" % tool_names[current_tool])
			KEY_P:
				# Suorituskykytesti: generoi maailma → räjäytä 3 kertaa → mittaa frame-spiikit
				_run_perf_explosion_test()
			KEY_Q:
				god_mode = not god_mode
				if god_mode:
					cam_grid_pos = player.position
					cam_vel = Vector2.ZERO
					print("God mode ON — WASD liikuttaa kameraa")
				else:
					print("Player mode ON")
			KEY_X:
				current_weapon = Weapon.PICKAXE
				grav_gun_mode = 0
				laser_dragging = false
				print("Ase: Hakku")
			KEY_L:
				current_weapon = Weapon.RIFLE
				grav_gun_mode = 0
				laser_dragging = false
				print("Ase: Rynnäkkäkivääri")
			KEY_C: clear_world()
			KEY_R: regenerate_world()
			KEY_ESCAPE:
				if build_mode != BUILD_NONE:
					build_mode = BUILD_NONE
					print("Rakennustila peruttu")
			KEY_B:
				build_menu_visible = not build_menu_visible
				if build_menu_visible:
					print("=== RAKENNUSVALIKKO === 1: Spawner | 2: Liukuhihna | 3: Kaivos | 4: Uuni | 5: Linko | 6: Seinä | B/ESC: Sulje")
				else:
					print("Rakennusvalikko suljettu")
			KEY_F:
				_fire_rocket_at_cursor()
			KEY_O:
				darkness_mode = !darkness_mode
				shader_mat.set_shader_parameter("darkness_mode", int(darkness_mode))
				print("Darkness mode: %s" % ("ON" if darkness_mode else "OFF"))
			KEY_F5: save_world()
			KEY_F9: load_world()
			KEY_I: _save_ai_screenshot()


func _paint(cx: int, cy: int, mat: int) -> void:
	var r2 := brush_size * brush_size
	for dy in range(-brush_size, brush_size + 1):
		var ny := cy + dy
		if ny < 0 or ny >= SIM_HEIGHT:
			continue
		var row := ny * W
		for dx in range(-brush_size, brush_size + 1):
			if dx * dx + dy * dy <= r2:
				var nx := cx + dx
				if nx >= 0 and nx < W:
					var idx := row + nx
					# Suojatut rakennuspikselit: ei ylikirjoiteta
					if building_pixels.has(idx):
						continue
					grid[idx] = mat
					color_seed[idx] = randi() % 256
					# Kerää kivipikselit vedon aikana
					if mat == MAT_STONE and is_painting_stone:
						stroke_stone_pixels[Vector2i(nx, ny)] = true
	paint_pending = true


# Leikkaa materiaalia ohuella viivalla (1px leveys)
func _cut(cx: int, cy: int) -> void:
	# Hakku: cooldown — estää jatkuvan kaivauksen
	if current_tool == Tool.PICKAXE:
		if pickaxe_cooldown > 0.0:
			return
		pickaxe_cooldown = PICKAXE_COOLDOWN_TIME
		add_trauma(0.05)
		set_impact(Vector2(cx, cy), 0.5, 2)

	var cut_size: int = TOOL_DATA[current_tool]["radius"] / 2  # Kaivaustyökalun säde
	var changed := false
	for dy in range(-cut_size, cut_size + 1):
		var ny := cy + dy
		if ny < 0 or ny >= SIM_HEIGHT:
			continue
		var row := ny * W
		for dx in range(-cut_size, cut_size + 1):
			var nx := cx + dx
			if nx >= 0 and nx < W:
				var idx := row + nx
				# Suojatut rakennuspikselit: ei leikata
				if building_pixels.has(idx):
					continue
				var mat := grid[idx]
				# Megapora kaivaa myös mullan ja putoavan puun
				if current_tool == Tool.MEGA_DRILL:
					if mat == MAT_STONE:
						# Kivi hajoaa: soraa megaporalla
						grid[idx] = MAT_GRAVEL
						changed = true
					elif mat == MAT_DIRT or mat == MAT_IRON_ORE \
							or mat == MAT_GOLD_ORE or mat == MAT_WOOD or mat == MAT_WOOD_FALLING:
						grid[idx] = MAT_EMPTY
						changed = true
				else:
					if mat == MAT_STONE:
						# Kivi hajoaa hakulla: soraa
						grid[idx] = MAT_GRAVEL
						changed = true
					elif mat == MAT_WOOD or mat == MAT_IRON_ORE or mat == MAT_GOLD_ORE:
						grid[idx] = MAT_EMPTY
						changed = true
	if changed:
		paint_pending = true
		visibility_dirty = true
		# check_damage hoitaa kappaleiden halkeamisen automaattisesti


func _upload_paint_to_gpu() -> void:
	if transfer_ready:
		# GPU-pakkaus: lataa packed-bufferit ja aja pack-shader
		rd.buffer_update(mat_packed_buffer, 0, grid.size(), grid)
		rd.buffer_update(seed_packed_buffer, 0, color_seed.size(), color_seed)
		var total_quads := ceili(float(TOTAL) / 4.0)
		var pack_push := PackedByteArray()
		pack_push.resize(16)
		pack_push.encode_u32(0, total_quads)
		pack_push.encode_u32(4, TOTAL)
		pack_push.encode_u32(8, 1)  # mode 1 = pack
		pack_push.encode_u32(12, 0)  # padding
		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, transfer_pipeline)
		rd.compute_list_bind_uniform_set(cl, transfer_uniform_set, 0)
		rd.compute_list_set_push_constant(cl, pack_push, pack_push.size())
		rd.compute_list_dispatch(cl, ceili(float(total_quads) / 64.0), 1, 1)
		rd.compute_list_end()
		rd.submit()
		rd.sync()
	else:
		# Fallback: GDScript-looppi
		if _gpu_upload_buf.size() != TOTAL * 4:
			_gpu_upload_buf.resize(TOTAL * 4)
			_gpu_upload_buf.fill(0)
		var i := 0
		var off := 0
		while i < TOTAL:
			_gpu_upload_buf[off] = grid[i]
			_gpu_upload_buf[off + 1] = color_seed[i]
			i += 1
			off += 4
		rd.buffer_update(grid_buffer, 0, _gpu_upload_buf.size(), _gpu_upload_buf)


func _simulate_gpu() -> void:
	# Per-pikseli dispatch: jokainen pikseli = yksi thread
	var groups_x := ceili(float(W) / 16.0)
	var groups_y := ceili(float(SIM_HEIGHT) / 16.0)

	# Adaptiivinen passimäärä — vähennetään jos GPU ei pysy tahdissa
	var push := PackedByteArray()
	push.resize(48)  # Laajennettu gravity gun -kentillä
	push.encode_u32(0, W)
	push.encode_u32(4, SIM_HEIGHT)

	var t0 := Time.get_ticks_usec()

	var cl := rd.compute_list_begin()

	for pass_i in gpu_passes:
		if pass_i > 0:
			rd.compute_list_add_barrier(cl)
		push.encode_u32(8, frame_count * 4 + pass_i)
		push.encode_u32(12, pass_i)
		push.encode_u32(16, 0)
		# Gravity gun -tila (0=off, 1=normaali veto, 2=vakuumi)
		push.encode_u32(20, grav_gun_pos.x if grav_gun_mode > 0 else 0)
		push.encode_u32(24, grav_gun_pos.y if grav_gun_mode > 0 else 0)
		push.encode_u32(28, grav_gun_mode)
		push.encode_u32(32, grav_gun_vacuum_radius if grav_gun_mode == 2 else grav_gun_radius)
		push.encode_u32(36, 0)   # käyttämätön
		push.encode_u32(40, 0)   # käyttämätön
		push.encode_u32(44, 0)

		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
		rd.compute_list_set_push_constant(cl, push, push.size())
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)

	# Extraction pass: pura materiaali ja seed erillisiin pakattuhiin buffereihin
	if transfer_ready:
		rd.compute_list_add_barrier(cl)
		var total_quads := ceili(float(TOTAL) / 4.0)
		var extract_push := PackedByteArray()
		extract_push.resize(16)
		extract_push.encode_u32(0, total_quads)
		extract_push.encode_u32(4, TOTAL)
		extract_push.encode_u32(8, 0)  # mode 0 = extract
		extract_push.encode_u32(12, 0)  # padding
		rd.compute_list_bind_compute_pipeline(cl, transfer_pipeline)
		rd.compute_list_bind_uniform_set(cl, transfer_uniform_set, 0)
		rd.compute_list_set_push_constant(cl, extract_push, extract_push.size())
		rd.compute_list_dispatch(cl, ceili(float(total_quads) / 64.0), 1, 1)

	# Render compute pass: grid_buffer → RGBA8-tekstuuri suoraan GPU:lla
	if render_compute_ready:
		rd.compute_list_add_barrier(cl)
		var groups_x_r := ceili(float(W) / 16.0)
		var groups_y_r := ceili(float(SIM_HEIGHT) / 16.0)
		var render_push := PackedByteArray()
		render_push.resize(16)
		render_push.encode_u32(0, W)
		render_push.encode_u32(4, SIM_HEIGHT)
		render_push.encode_u32(8, frame_count)
		render_push.encode_u32(12, 0)
		rd.compute_list_bind_compute_pipeline(cl, render_compute_pipeline)
		rd.compute_list_bind_uniform_set(cl, render_compute_uniform_set, 0)
		rd.compute_list_set_push_constant(cl, render_push, render_push.size())
		rd.compute_list_dispatch(cl, groups_x_r, groups_y_r, 1)

	rd.compute_list_end()
	rd.submit()
	rd.sync()

	# Mittaa GPU-aika ja säädä passimäärää adaptiivisesti
	gpu_time_ms = float(Time.get_ticks_usec() - t0) / 1000.0
	if gpu_time_ms > 12.0 and gpu_passes > 4:
		gpu_passes -= 1  # Liian hidas → vähemmän passeja
	elif gpu_time_ms < 6.0 and gpu_passes < 12:
		gpu_passes += 1  # Varaa riittää → enemmän passeja


func _download_from_gpu() -> void:
	if transfer_ready:
		# GPU-purettu data: suora lataus ilman GDScript-looppia
		grid = rd.buffer_get_data(mat_packed_buffer)
		color_seed = rd.buffer_get_data(seed_packed_buffer)
		# Trimmaa jos bufferi on isompi kuin TOTAL
		if grid.size() > TOTAL:
			grid = grid.slice(0, TOTAL)
		if color_seed.size() > TOTAL:
			color_seed = color_seed.slice(0, TOTAL)
	else:
		# Fallback: GDScript-looppi
		var output := rd.buffer_get_data(grid_buffer)
		var i := 0
		var off := 0
		while i < TOTAL:
			grid[i] = output[off]
			color_seed[i] = output[off + 1]
			i += 1
			off += 4


func _upload_render() -> void:
	if render_compute_ready:
		# GPU hoitaa materiaalivärjäyksen — ei CPU-kopiointia tekstuureiksi.
		# Ylläpidetään vain flash_timer-laskuri ja muut tilamuuttujat.
		if flash_timer > 0:
			flash_timer -= 1
		# Overlay-efektit (grav gun, laser, pelaaja, flash) renderöidään canvas_item-shaderilla
		# joka lukee Texture2DRD:tä. Koska material = null, ne eivät ole käytössä tässä vaiheessa.
		return

	# CPU-fallback: päivitä tekstuurit vanhalla tavalla
	grid_image.set_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, grid)
	grid_texture.update(grid_image)
	seed_image.set_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, color_seed)
	seed_texture.update(seed_image)
	shader_mat.set_shader_parameter("frame", frame_count)
	# Räjähdysflash
	if flash_timer > 0:
		shader_mat.set_shader_parameter("flash_uv", flash_pos)
		shader_mat.set_shader_parameter("flash_radius", flash_radius)
		shader_mat.set_shader_parameter("flash_intensity", float(flash_timer) / float(FLASH_DURATION))
		flash_timer -= 1
	else:
		shader_mat.set_shader_parameter("flash_intensity", 0.0)
	# Gravity gun -efekti renderöintishaderille (moodi: 0=off, 1=normaali, 2=vakuumi)
	shader_mat.set_shader_parameter("grav_gun_active", grav_gun_mode)
	# Held-suhde: täyttöaste held-listan koon perusteella
	shader_mat.set_shader_parameter("grav_fill_ratio", clampf(float(grav_held.size()) / float(GRAV_MAX_HELD), 0.0, 1.0))
	if grav_gun_mode > 0:
		var render_radius := grav_gun_vacuum_radius if grav_gun_mode == 2 else grav_gun_radius
		shader_mat.set_shader_parameter("grav_gun_uv", Vector2(
			float(grav_gun_pos.x) / float(W),
			float(grav_gun_pos.y) / float(SIM_HEIGHT)
		))
		shader_mat.set_shader_parameter("grav_gun_radius", float(render_radius) / float(W))
	# Pelaaja-renderöinti (piilotetaan god modessa)
	if not god_mode:
		var pp: Vector2i = player.get_grid_pos()
		shader_mat.set_shader_parameter("player_pos", Vector2(
			float(pp.x) / float(W), float(pp.y) / float(SIM_HEIGHT)
		))
		shader_mat.set_shader_parameter("player_size", Vector2(
			float(PlayerScript.WIDTH) / float(W), float(PlayerScript.HEIGHT) / float(SIM_HEIGHT)
		))
		shader_mat.set_shader_parameter("player_facing_right", 1 if player.facing_right else 0)
		shader_mat.set_shader_parameter("player_in_water", 1 if player.in_water else 0)
	else:
		shader_mat.set_shader_parameter("player_size", Vector2.ZERO)

	# Laser-efekti poistettu käytöstä
	shader_mat.set_shader_parameter("laser_intensity", 0.0)


# Vedä irtonaiset pikselit kohti pistettä (CPU, ei duplikaatiota)
func _pull_pixels(cx: int, cy: int, radius: int) -> void:
	var r2 := radius * radius
	# Kerää irtonaiset pikselit ja järjestä lähimmät ensin (ne siirtyvät ensin)
	var pixels: Array[Vector3i] = []  # (idx, dx, dy)
	for dy in range(-radius, radius + 1):
		var py := cy + dy
		if py < 0 or py >= SIM_HEIGHT:
			continue
		var row := py * W
		for dx in range(-radius, radius + 1):
			var d2 := dx * dx + dy * dy
			if d2 > r2 or d2 == 0:
				continue
			var px := cx + dx
			if px < 0 or px >= W:
				continue
			var idx := row + px
			var mat := grid[idx]
			if mat == MAT_SAND or mat == MAT_WATER or mat == MAT_OIL or mat == MAT_ASH or mat == MAT_WOOD_FALLING:
				pixels.append(Vector3i(idx, dx, dy))

	# Järjestä: lähimpänä keskustaa olevat ensin
	pixels.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return (a.y * a.y + a.z * a.z) < (b.y * b.y + b.z * b.z)
	)

	# Siirrä jokainen pikseli useampi askel kohti keskustaa (voittaa painovoiman)
	for p in pixels:
		var idx: int = p.x
		var dx: int = p.y
		var dy: int = p.z
		var px: int = idx % W
		var py: int = idx / W
		var cur_idx := idx

		# 3 askelta per frame — riittää voittamaan gravitaation
		for _step in 3:
			var cdx := cx - px
			var cdy := cy - py
			if cdx == 0 and cdy == 0:
				break

			var step_x := 0
			var step_y := 0
			if absi(cdx) >= absi(cdy):
				step_x = 1 if cdx > 0 else -1
			else:
				step_y = 1 if cdy > 0 else -1

			var nx := px + step_x
			var ny := py + step_y
			if nx < 0 or nx >= W or ny < 0 or ny >= SIM_HEIGHT:
				break

			var dst_idx := ny * W + nx
			if grid[dst_idx] == MAT_EMPTY:
				grid[dst_idx] = grid[cur_idx]
				color_seed[dst_idx] = color_seed[cur_idx]
				grid[cur_idx] = MAT_EMPTY
				color_seed[cur_idx] = 0
				cur_idx = dst_idx
				px = nx
				py = ny
			else:
				break

	if not pixels.is_empty():
		paint_pending = true


# Tyhjentää edellisellä framella kirjoitetut held-pikselit gridistä
func _grav_erase_held() -> void:
	for idx in grav_held_written:
		if idx >= 0 and idx < TOTAL and grid[idx] == MAT_HELD:
			grid[idx] = MAT_EMPTY
	grav_held_written.clear()


# Bresenham-näköyhteystarkistus: palauttaa true jos polku (x0,y0)→(x1,y1) on vapaa kiinteistä
func _grav_has_los(x0: int, y0: int, x1: int, y1: int) -> bool:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var x := x0
	var y := y0
	while true:
		if x == x1 and y == y1:
			return true
		if x < 0 or x >= W or y < 0 or y >= SIM_HEIGHT:
			return false
		# Tarkista välipisteet (ei alku- eikä loppupistettä)
		if not (x == x0 and y == y0):
			var m := grid[y * W + x]
			# Vain kova rakenne estää — ei dirt/coal (maastomateriaali eikä seinä)
			if m == MAT_STONE or m == MAT_WOOD or m == MAT_GLASS or \
					m == MAT_IRON or m == MAT_GOLD or m == MAT_IRON_ORE or \
					m == MAT_GOLD_ORE:
				return false
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
	return true


# Nappaa lähellä kursoria olevat irtonaiset pikselit held-listaan
# Skannaa r+2 säteellä mutta tallentaa offsetin max r:n pinnalle —
# näin palloa vasten pysähtyneeet pikselit pääsevät mukaan eivätkä jää juuttumaan
func _grav_capture() -> void:
	if grav_held.size() >= GRAV_MAX_HELD:
		return
	var cx := grav_gun_pos.x
	var cy := grav_gun_pos.y
	# Capture-säde ~1/3 pull-säteestä: pikselit lentävät ensin GPU-vedolla,
	# CPU nappaa ne vasta kun ovat tarpeeksi lähellä → kompakti pallo, ei teleportti
	var r := (grav_gun_vacuum_radius / 3) if grav_gun_mode == 2 else (grav_gun_radius / 3)
	var scan_r := r + 2  # Skannaa hieman laajemmin — nappaa HELD-pallon ulkopuolelle juuttuneet
	for dy in range(-scan_r, scan_r + 1):
		for dx in range(-scan_r, scan_r + 1):
			var dist2 := dx * dx + dy * dy
			if dist2 > scan_r * scan_r:
				continue
			var nx := cx + dx
			var ny := cy + dy
			if nx < 0 or nx >= W or ny < 0 or ny >= SIM_HEIGHT:
				continue
			var idx := ny * W + nx
			var mat := grid[idx] & 0xFF
			# Nappaa irtonaiset materiaalit (ei kiviä, puuta tms.)
			if mat != MAT_EMPTY and mat != MAT_HELD and mat != MAT_STONE and mat != MAT_WOOD \
					and mat != MAT_GLASS and mat != MAT_IRON and mat != MAT_GOLD \
					and mat != MAT_IRON_ORE and mat != MAT_GOLD_ORE \
					and mat != MAT_COAL and mat != MAT_DIRT:
				# Näköyhteystarkistus: ei napata seinän läpi
				if not _grav_has_los(cx, cy, nx, ny):
					continue
				grid[idx] = MAT_EMPTY
				# Puristaa offsetin enintään r:n pinnalle — pallo pysyy kompaktina
				var store_dx := dx
				var store_dy := dy
				if dist2 > r * r:
					var dist := sqrt(float(dist2))
					store_dx = int(float(dx) / dist * float(r))
					store_dy = int(float(dy) / dist * float(r))
				grav_held.append(Vector3i(mat, store_dx, store_dy))
				if grav_held.size() >= GRAV_MAX_HELD:
					return


# Kirjoittaa held-pikselit palloksi kursoorin ympärille, sisältä ulospäin.
# Alkuperäinen muoto unohdetaan — pikselit tiivistetään kompaktiksi palloksi.
func _grav_write_held() -> void:
	grav_held_written.clear()  # Tyhjennä aina ensin — muuten vapautus käyttää vanhoja positioita
	var cx := grav_gun_pos.x
	var cy := grav_gun_pos.y
	var ball_r := grav_gun_vacuum_radius / 3 if grav_gun_mode == 2 else grav_gun_radius / 3

	# Luo kaikki pallonsisäiset paikat ja järjestä lähimmät ensin
	var slots: Array[Vector2i] = []
	for dy in range(-ball_r, ball_r + 1):
		for dx in range(-ball_r, ball_r + 1):
			if dx * dx + dy * dy <= ball_r * ball_r:
				slots.append(Vector2i(dx, dy))
	slots.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.x * a.x + a.y * a.y < b.x * b.x + b.y * b.y
	)

	var slot_i := 0
	for h in grav_held:
		# Etsi seuraava vapaa paikka pallossa
		while slot_i < slots.size():
			var s := slots[slot_i]
			slot_i += 1
			var nx := cx + s.x
			var ny := cy + s.y
			if nx < 0 or nx >= W or ny < 0 or ny >= SIM_HEIGHT:
				continue
			var nidx := ny * W + nx
			var target := grid[nidx] & 0xFF
			var solid := target == MAT_STONE or target == MAT_WOOD or \
					target == MAT_GLASS or target == MAT_IRON or target == MAT_GOLD or \
					target == MAT_IRON_ORE or target == MAT_GOLD_ORE or \
					target == MAT_COAL or target == MAT_DIRT
			if not solid and (target == MAT_EMPTY or target == MAT_HELD):
				grid[nidx] = MAT_HELD
				grav_held_written.append(nidx)
				break


# Vapauttaa kaikki held-pikselit gridiin (hiiren vapautus)
# Skannaa gridin suoraan MAT_HELD-solujen löytämiseksi — ei riipu grav_held_written-synkasta
func _grav_release() -> void:
	# Kerää HELD-positiot suoraan gridistä (varma tapa löytää pallon nykyiset solut)
	var held_positions: Array[int] = []
	for i in TOTAL:
		if grid[i] == MAT_HELD:
			held_positions.append(i)
			grid[i] = MAT_EMPTY
	# Kirjoita materiaalit samoihin paikkoihin
	for i in min(grav_held.size(), held_positions.size()):
		grid[held_positions[i]] = grav_held[i].x
	print("grav_release: held=%d positions=%d" % [grav_held.size(), held_positions.size()])
	grav_held.clear()
	grav_held_written.clear()
	paint_pending = true


# Heitä irtonaiset pikselit suuntaan (CPU, ei duplikaatiota)
func _throw_pixels(center: Vector2i, radius: int, velocity: Vector2) -> void:
	var r2 := radius * radius
	# Kerää ensin kaikki siirrettävät pikselit
	var moves: Array[Vector3i] = []  # (src_idx, dst_x, dst_y)
	for dy in range(-radius, radius + 1):
		var sy := center.y + dy
		if sy < 0 or sy >= SIM_HEIGHT:
			continue
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > r2:
				continue
			var sx := center.x + dx
			if sx < 0 or sx >= W:
				continue
			var src_idx := sy * W + sx
			var mat := grid[src_idx]
			# Vain irtonaiset materiaalit (hiekka, vesi, öljy, tuhka)
			if mat == MAT_SAND or mat == MAT_WATER or mat == MAT_OIL or mat == MAT_ASH:
				# Heittoetäisyys: lähempänä keskustaa = voimakkaampi
				var dist := sqrt(float(dx * dx + dy * dy))
				var strength := 1.0 - dist / float(radius)
				var tx := sx + int(velocity.x * strength)
				var ty := sy + int(velocity.y * strength)
				tx = clampi(tx, 0, W - 1)
				ty = clampi(ty, 0, SIM_HEIGHT - 1)
				moves.append(Vector3i(src_idx, tx, ty))

	# Suorita siirrot: poista ensin kaikki, sitten kirjoita uusiin paikkoihin
	var thrown: Array = []  # (mat, seed, dst_x, dst_y)
	for m in moves:
		var src_idx: int = m.x
		thrown.append([grid[src_idx], color_seed[src_idx], m.y, m.z])
		grid[src_idx] = MAT_EMPTY
		color_seed[src_idx] = 0

	for t in thrown:
		var mat: int = t[0]
		var seed_val: int = t[1]
		var tx: int = t[2]
		var ty: int = t[3]
		var dst_idx := ty * W + tx
		if grid[dst_idx] == MAT_EMPTY:
			grid[dst_idx] = mat
			color_seed[dst_idx] = seed_val

	if not moves.is_empty():
		paint_pending = true


# === SUORITUSKYKY-BENCHMARK ===
# Luo 40x40 kiviblokki gridin keskelle, räjäyttää kahdesti, mittaa ajan
# Kutsutaan näppäimellä P

func run_explosion_benchmark() -> void:
	var cx: int = W / 2
	var cy: int = SIM_HEIGHT / 2
	var block_size: int = 40

	# Tallenna FPS ennen testiä
	var fps_before: float = Engine.get_frames_per_second()

	# Luo 40x40 kiviblokki keskelle
	var bx0: int = cx - block_size / 2
	var by0: int = cy - block_size / 2
	for y in range(by0, by0 + block_size):
		if y < 0 or y >= SIM_HEIGHT:
			continue
		var row: int = y * W
		for x in range(bx0, bx0 + block_size):
			if x < 0 or x >= W:
				continue
			grid[row + x] = MAT_STONE
			color_seed[row + x] = randi() % 256
	paint_pending = true

	# Ensimmäinen räjähdys — mittaa aika
	var t0: int = Time.get_ticks_usec()
	explode(cx, cy, 25)
	var t1: int = Time.get_ticks_usec()
	var ms1: float = float(t1 - t0) / 1000.0

	# Toinen räjähdys hieman siirtymällä
	var t2: int = Time.get_ticks_usec()
	explode(cx + 10, cy, 20)
	var t3: int = Time.get_ticks_usec()
	var ms2: float = float(t3 - t2) / 1000.0

	# Tulokset
	print("=== RÄJÄHDYS-BENCHMARK ===")
	print("Räjähdys 1: %.2f ms" % ms1)
	print("Räjähdys 2: %.2f ms" % ms2)
	print("Keskiarvo:  %.2f ms" % ((ms1 + ms2) * 0.5))
	print("FPS ennen: %.1f" % fps_before)
	print("Jonossa: %d kappaletta" % physics_world.damage_check_queue.size())
	print("==========================")


# Etsi räjähdyksen jälkeen irtonaiset kivipalat ja luo niistä rigid bodyt
func _detect_detached_stone(cx: int, cy: int, radius: int) -> void:
	var scan_r := radius + 5  # Skannausalue hieman isompi kuin räjähdys
	var min_x := maxi(0, cx - scan_r)
	var max_x := mini(W - 1, cx + scan_r)
	var min_y := maxi(0, cy - scan_r)
	var max_y := mini(SIM_HEIGHT - 1, cy + scan_r)

	# Kerää kaikki kivet skannausalueella
	var stone_pixels: Array[Vector2i] = []
	for y in range(min_y, max_y + 1):
		var row := y * W
		for x in range(min_x, max_x + 1):
			if grid[row + x] == MAT_STONE:
				stone_pixels.append(Vector2i(x, y))

	if stone_pixels.is_empty():
		return

	# Flood fill jokaisesta kivestä — tarkista onko yhteydessä reunaan
	physics_world._ensure_body_map(W, SIM_HEIGHT)
	var visited := PackedByteArray()
	visited.resize(TOTAL)
	visited.fill(0)

	for start_pixel in stone_pixels:
		var si := start_pixel.y * W + start_pixel.x
		if visited[si] != 0:
			continue
		if physics_world.body_map[si] != 0:
			continue  # Jo osa rigid bodyä

		# BFS: etsi yhtenäinen kivialue
		var region: Array[Vector2i] = []
		var queue: Array[int] = [si]
		visited[si] = 1
		var touches_edge := false

		while not queue.is_empty():
			var idx: int = queue.pop_back()
			var px: int = idx % W
			var py: int = idx / W
			region.append(Vector2i(px, py))

			# Koskettaako reunaa? (vasen/oikea/ala = yhteydessä maailmaan)
			if px <= 2 or px >= W - 3 or py >= SIM_HEIGHT - 3:
				touches_edge = true

			# Naapurit — rajoitetaan skannausalueeseen suorituskyvyn vuoksi
			if px > 0 and visited[idx - 1] == 0 and grid[idx - 1] == MAT_STONE and physics_world.body_map[idx - 1] == 0:
				# Jos naapuri on skannausalueen ulkopuolella, merkitään reunakosketukseksi
				if px - 1 < min_x:
					touches_edge = true
				else:
					visited[idx - 1] = 1
					queue.append(idx - 1)
			if px < W - 1 and visited[idx + 1] == 0 and grid[idx + 1] == MAT_STONE and physics_world.body_map[idx + 1] == 0:
				if px + 1 > max_x:
					touches_edge = true
				else:
					visited[idx + 1] = 1
					queue.append(idx + 1)
			if py > 0 and visited[idx - W] == 0 and grid[idx - W] == MAT_STONE and physics_world.body_map[idx - W] == 0:
				if py - 1 < min_y:
					touches_edge = true
				else:
					visited[idx - W] = 1
					queue.append(idx - W)
			if py < SIM_HEIGHT - 1 and visited[idx + W] == 0 and grid[idx + W] == MAT_STONE and physics_world.body_map[idx + W] == 0:
				if py + 1 > max_y:
					touches_edge = true
				else:
					visited[idx + W] = 1
					queue.append(idx + W)

		# Irtonaiset (ei kosketa reunaa) → rigid body
		if not touches_edge and region.size() >= 4:
			if region.size() < 16:
				# Pieni fragmentti — tuhoa suoraan ilman rigid bodyä
				for p in region:
					grid[p.y * W + p.x] = MAT_EMPTY
				paint_pending = true
				continue
			var seeds := PackedByteArray()
			seeds.resize(region.size())
			for i in region.size():
				var p: Vector2i = region[i]
				seeds[i] = color_seed[p.y * W + p.x]

			var body := physics_world.create_body(region, seeds, MAT_STONE)
			if body:
				# Anna räjähdyksen impulssi
				var dir := body.position - Vector2(cx, cy)
				var dist := dir.length()
				if dist > 0.5:
					dir = dir.normalized()
					var strength := float(radius) * 0.3 * (1.0 - minf(dist / float(radius * 2), 1.0))
					body.velocity = dir * strength / maxf(body.mass, 1.0)
					body.angular_velocity = randf_range(-0.1, 0.1) * strength
				body.wake_up()
				for p in region:
					physics_world.body_map[p.y * W + p.x] = body.body_id


# === LIUKUHIHNAT ===

func _update_conveyors(delta: float) -> bool:
	var modified := false
	var alive: Array = []
	for belt in conveyors:
		if belt.update_belt(grid, color_seed, W, SIM_HEIGHT, delta):
			modified = true
		if belt.broken:
			_unregister_building_pixels(belt.floor_pixels)
			belt.queue_free()
		else:
			alive.append(belt)
	conveyors = alive
	return modified


func _create_conveyor(start: Vector2, end: Vector2) -> void:
	var BeltScene := preload("res://scripts/conveyor_belt.gd")
	var belt = BeltScene.new()
	belt.setup(Vector2i(start), Vector2i(end))
	belt.build_floor(grid, color_seed, W, SIM_HEIGHT)
	building_layer.add_child(belt)
	conveyors.append(belt)
	_register_building_pixels(belt.floor_pixels)
	paint_pending = true
	print("Liukuhihna luotu: ", start, " → ", end)


# Laskee seinän pikselipisteet: Bresenham-viiva + ±1 normaalin suuntaan (3px paksuus).
# Palauttaa deduplikoitu pikselijoukko Array[Vector2i]-muodossa.
func _wall_pixels(start: Vector2, end: Vector2) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	var seen: Dictionary = {}
	var dx_line := end.x - start.x
	var dy_line := end.y - start.y
	var line_len := sqrt(dx_line * dx_line + dy_line * dy_line)

	# Lasketaan normaali — jos viiva on täysin horisontaalinen tai vertikaalinen,
	# käytetään yksinkertaistettua normaalia
	var nx := 0.0
	var ny := 0.0
	if line_len > 0.5:
		nx = -dy_line / line_len
		ny = dx_line / line_len

	var pts := _bresenham_line(int(start.x), int(start.y), int(end.x), int(end.y))
	for p in pts:
		for off in [-1, 0, 1]:
			var px := p.x + int(round(nx * float(off)))
			var py := p.y + int(round(ny * float(off)))
			if px < 0 or px >= W or py < 0 or py >= SIM_HEIGHT:
				continue
			var key := Vector2i(px, py)
			if not seen.has(key):
				seen[key] = true
				result.append(key)
	return result


# Piirtää STONE-seinän start→end, 3px paksuus normaalin suuntaan
func _create_wall(start: Vector2, end: Vector2) -> void:
	var pixels := _wall_pixels(start, end)
	for p in pixels:
		var idx := p.y * W + p.x
		grid[idx] = MAT_STONE
		color_seed[idx] = randi() % 256
	_register_building_pixels(pixels)
	paint_pending = true
	print("Seinä rakennettu: %s → %s (%d pikseliä)" % [start, end, pixels.size()])


func _constrain_45(start: Vector2, target: Vector2) -> Vector2:
	var diff := target - start
	# Rajoita kulma max 45 asteeseen vaakatasosta
	if abs(diff.x) < 1.0:
		return target  # Pystysuora, sallitaan
	var angle: float = absf(diff.y / diff.x)
	if angle > 1.0:  # Yli 45 astetta
		diff.y = sign(diff.y) * abs(diff.x)
	return start + diff


func _snap_to_grid(pos: Vector2) -> Vector2:
	return pos.snapped(Vector2(GRID_SIZE, GRID_SIZE))


func _snap_to_belt_end(pos: Vector2) -> Vector2:
	var best_dist := SNAP_DISTANCE
	var best_pos := pos
	for belt in conveyors:
		var d_start: float = pos.distance_to(belt.start_pos)
		var d_end: float = pos.distance_to(belt.end_pos)
		if d_start < best_dist:
			best_dist = d_start
			best_pos = belt.start_pos
		if d_end < best_dist:
			best_dist = d_end
			best_pos = belt.end_pos
	return best_pos


func _register_building_pixels(pixels: Array) -> void:
	# Merkitsee pikselit suojatuiksi — maalaus ja leikkaus eivät ylikirjoita niitä
	for p in pixels:
		building_pixels[p.y * W + p.x] = true


func _unregister_building_pixels(pixels: Array) -> void:
	# Poistaa pikselit suojattujen listalta (kun rakennus poistetaan)
	for p in pixels:
		building_pixels.erase(p.y * W + p.x)


func _check_placement_valid(pixels: Array) -> bool:
	# Palauttaa tosi jos kaikki pikselit ovat rajoissa eikä osu olemassa olevaan rakennukseen
	for p in pixels:
		if p.x < 0 or p.x >= W or p.y < 0 or p.y >= SIM_HEIGHT:
			return false
		if building_pixels.has(p.y * W + p.x):
			return false
	return true


func _update_build_preview() -> void:
	if not build_preview:
		return
	build_preview.clear()
	if build_mode == BUILD_NONE:
		build_preview.queue_redraw()
		return

	var coords := _mouse_to_grid()
	if coords.x < 0:
		build_preview.queue_redraw()
		return

	var mouse_pos := Vector2(coords)

	if build_mode == BUILD_SPAWNER:
		build_preview.show_spawner = true
		build_preview.start_marker = mouse_pos
		# Spawnerilla ei rakennepikselejä — aina validi sijoituskohdalla
		build_preview.is_valid = true
	elif build_mode == BUILD_SAND_MINE:
		# Hiekkakaivos: 4×4 siluetti snap-kohtaan (vastaa SandMine.MINE_W/MINE_H = 4/4)
		const PREVIEW_MINE_W := 4
		const PREVIEW_MINE_H := 4
		var snapped := _snap_to_grid(mouse_pos)
		var center := Vector2i(int(snapped.x), int(snapped.y))
		var gp := Vector2i(center.x - PREVIEW_MINE_W / 2, center.y - PREVIEW_MINE_H / 2)
		var preview_pxs: Array[Vector2i] = []
		for dy in PREVIEW_MINE_H:
			for dx in PREVIEW_MINE_W:
				preview_pxs.append(Vector2i(gp.x + dx, gp.y + dy))
		build_preview.preview_pixels = preview_pxs
		build_preview.is_valid = _check_placement_valid(preview_pxs)
	elif build_mode == BUILD_FURNACE:
		# Uuni: siluetti snap-kohtaan (vastaa Furnace.FURNACE_W=12, FURNACE_H=10, INTAKE_W=6)
		const PREVIEW_FURNACE_W := 12
		const PREVIEW_FURNACE_H := 10
		const PREVIEW_INTAKE_W := 6
		var snapped := _snap_to_grid(mouse_pos)
		var center := Vector2i(int(snapped.x), int(snapped.y))
		var gp := Vector2i(center.x - PREVIEW_FURNACE_W / 2, center.y - PREVIEW_FURNACE_H / 2)
		var intake_start := gp.x + (PREVIEW_FURNACE_W - PREVIEW_INTAKE_W) / 2
		var output_start := gp.x + (PREVIEW_FURNACE_W - 4) / 2
		var preview_pxs: Array[Vector2i] = []
		# Rivi 0: reunat + intake-aukko auki
		for dx in PREVIEW_FURNACE_W:
			var px := gp.x + dx
			if px < intake_start or px >= intake_start + PREVIEW_INTAKE_W:
				preview_pxs.append(Vector2i(px, gp.y))
		# Rivit 1..H-2: täynnä
		for dy in range(1, PREVIEW_FURNACE_H - 1):
			for dx in PREVIEW_FURNACE_W:
				preview_pxs.append(Vector2i(gp.x + dx, gp.y + dy))
		# Rivi H-1: output-aukko auki
		for dx in PREVIEW_FURNACE_W:
			var px := gp.x + dx
			if px < output_start or px >= output_start + 4:
				preview_pxs.append(Vector2i(px, gp.y + PREVIEW_FURNACE_H - 1))
		build_preview.preview_pixels = preview_pxs
		build_preview.is_valid = _check_placement_valid(preview_pxs)
	elif build_mode == BUILD_SLING:
		# Launcher-esikatselu: kolmivaiheinen — snap käyttää grid-koordinaatteja suoraan
		build_preview.show_launcher = true
		build_preview.launcher_phase = launcher_phase
		build_preview.launcher_start = Vector2(launcher_start)
		build_preview.launcher_end = Vector2(launcher_end)
		build_preview.launcher_cursor = _snap_to_grid(mouse_pos)
		build_preview.launcher_dir = 1.0 if mouse_pos.x >= float(launcher_start.x) else -1.0
		# Validointi vaiheessa 3: tarkista kuilu- ja jalustapikselit
		if launcher_phase == 3:
			var dir := 1.0 if mouse_pos.x >= float(launcher_start.x) else -1.0
			var tmp := LauncherScript.new()
			tmp.build_structure(launcher_start, launcher_end, dir)
			var all_pxs: Array = []
			all_pxs.append_array(tmp.structure_pixels)
			all_pxs.append_array(tmp._jalusta_pixels)
			build_preview.is_valid = _check_placement_valid(all_pxs)
		else:
			build_preview.is_valid = true
	elif build_mode == BUILD_CONVEYOR_START:
		var grid_snapped := _snap_to_grid(mouse_pos)
		var snapped := _snap_to_belt_end(grid_snapped)
		build_preview.start_marker = snapped
		build_preview.show_snap = snapped != grid_snapped
		build_preview.snap_point = snapped
		build_preview.is_valid = true
	elif build_mode == BUILD_CONVEYOR_END:
		build_preview.start_marker = conveyor_start_pos
		var grid_snapped := _snap_to_grid(mouse_pos)
		var end_pos := _snap_to_belt_end(grid_snapped)
		end_pos = _constrain_45(conveyor_start_pos, end_pos)
		build_preview.end_marker = end_pos
		build_preview.show_snap = end_pos != grid_snapped
		build_preview.snap_point = end_pos
		# Esikatselu-pikselit + validointi
		var belt_pxs: Array[Vector2i] = ConveyorBelt.bresenham_line(conveyor_start_pos, end_pos)
		build_preview.preview_pixels = belt_pxs
		build_preview.is_valid = _check_placement_valid(belt_pxs)
	elif build_mode == BUILD_WALL_START:
		build_preview.is_wall = true
		build_preview.preview_color = Color(0.55, 0.55, 0.55, 0.45)
		build_preview.start_marker = _snap_to_grid(mouse_pos)
		build_preview.is_valid = true
	elif build_mode == BUILD_WALL_END:
		build_preview.is_wall = true
		build_preview.preview_color = Color(0.55, 0.55, 0.55, 0.45)
		build_preview.start_marker = wall_start_pos
		var end_pos := _snap_to_grid(mouse_pos)
		build_preview.end_marker = end_pos
		# Laske preview-pikselit: pääviiva + normaalin suuntaiset offsetit (3px paksuus)
		var wall_pxs: Array[Vector2i] = _wall_pixels(wall_start_pos, end_pos)
		build_preview.preview_pixels = wall_pxs
		build_preview.is_valid = _check_placement_valid(wall_pxs)
	elif build_mode == BUILD_MONEY_EXIT:
		# Money exit: 12×10 siluetti, intake-aukko ylhäällä, EI output-aukkoa (alarivi kiinni)
		const PREVIEW_EXIT_W := 12
		const PREVIEW_EXIT_H := 10
		const PREVIEW_EXIT_INTAKE_W := 6
		var snapped := _snap_to_grid(mouse_pos)
		var center := Vector2i(int(snapped.x), int(snapped.y))
		var gp := Vector2i(center.x - PREVIEW_EXIT_W / 2, center.y - PREVIEW_EXIT_H / 2)
		var intake_start_x := gp.x + (PREVIEW_EXIT_W - PREVIEW_EXIT_INTAKE_W) / 2
		var preview_pxs: Array[Vector2i] = []
		# Rivi 0: reunat + intake-aukko auki
		for dx in PREVIEW_EXIT_W:
			var px := gp.x + dx
			if px < intake_start_x or px >= intake_start_x + PREVIEW_EXIT_INTAKE_W:
				preview_pxs.append(Vector2i(px, gp.y))
		# Rivit 1..H-2: täynnä
		for dy in range(1, PREVIEW_EXIT_H - 1):
			for dx in PREVIEW_EXIT_W:
				preview_pxs.append(Vector2i(gp.x + dx, gp.y + dy))
		# Rivi H-1: täysin kiinni (EI output-aukkoa)
		for dx in PREVIEW_EXIT_W:
			preview_pxs.append(Vector2i(gp.x + dx, gp.y + PREVIEW_EXIT_H - 1))
		build_preview.preview_pixels = preview_pxs
		build_preview.is_valid = _check_placement_valid(preview_pxs)
	elif build_mode == BUILD_CRUSHER:
		# Murskaaja: 12×10 siluetti, intake ylhäällä, output-aukko alhaalla (sama kuin furnace)
		const PREVIEW_CRUSHER_W := 12
		const PREVIEW_CRUSHER_H := 10
		const PREVIEW_CRUSHER_INTAKE_W := 6
		var snapped := _snap_to_grid(mouse_pos)
		var center := Vector2i(int(snapped.x), int(snapped.y))
		var gp := Vector2i(center.x - PREVIEW_CRUSHER_W / 2, center.y - PREVIEW_CRUSHER_H / 2)
		var intake_start_x := gp.x + (PREVIEW_CRUSHER_W - PREVIEW_CRUSHER_INTAKE_W) / 2
		var output_start_x := gp.x + (PREVIEW_CRUSHER_W - 4) / 2
		var preview_pxs: Array[Vector2i] = []
		# Rivi 0: reunat + intake-aukko auki
		for dx in PREVIEW_CRUSHER_W:
			var px := gp.x + dx
			if px < intake_start_x or px >= intake_start_x + PREVIEW_CRUSHER_INTAKE_W:
				preview_pxs.append(Vector2i(px, gp.y))
		# Rivit 1..H-2: täynnä
		for dy in range(1, PREVIEW_CRUSHER_H - 1):
			for dx in PREVIEW_CRUSHER_W:
				preview_pxs.append(Vector2i(gp.x + dx, gp.y + dy))
		# Rivi H-1: output-aukko auki
		for dx in PREVIEW_CRUSHER_W:
			var px := gp.x + dx
			if px < output_start_x or px >= output_start_x + 4:
				preview_pxs.append(Vector2i(px, gp.y + PREVIEW_CRUSHER_H - 1))
		build_preview.preview_pixels = preview_pxs
		build_preview.is_valid = _check_placement_valid(preview_pxs)

	build_preview.queue_redraw()


func _clear_conveyors() -> void:
	for belt in conveyors:
		belt.queue_free()
	conveyors.clear()


func _place_sand_mine(pos: Vector2) -> void:
	var SandMineScript := preload("res://scripts/sand_mine.gd")
	var mine = SandMineScript.new()
	mine.setup(Vector2i(pos))
	mine.build_structure(grid, color_seed, W, SIM_HEIGHT)
	building_layer.add_child(mine)
	sand_mines.append(mine)
	_register_building_pixels(mine.structure_pixels)
	paint_pending = true
	print("Hiekkakaivos asetettu: ", pos)


func _place_furnace(pos: Vector2) -> void:
	var FurnaceScript := preload("res://scripts/furnace.gd")
	var furnace = FurnaceScript.new()
	furnace.setup(Vector2i(pos))
	furnace.build_structure(grid, color_seed, W, SIM_HEIGHT)
	building_layer.add_child(furnace)
	furnaces.append(furnace)
	_register_building_pixels(furnace.structure_pixels)
	paint_pending = true
	print("Uuni asetettu: ", pos)


func _update_furnaces(delta: float) -> bool:
	var modified := false
	var alive: Array = []
	for f in furnaces:
		if f.update_furnace(grid, color_seed, W, SIM_HEIGHT, delta):
			modified = true
		# Luo tuotos-rigid body kun uuni on valmis
		if f.glass_ready:
			f.glass_ready = false
			_spawn_smelted_body(f.glass_drop_pos, f.output_material)
			modified = true
		if f.broken:
			_unregister_building_pixels(f.structure_pixels)
			f.queue_free()
		else:
			alive.append(f)
	furnaces = alive
	return modified


func _spawn_smelted_body(drop_pos: Vector2i, mat: int) -> void:
	# 2×2 rigid body sulatusmateriaaleista — putoaa fysiikalla
	var pixels: Array[Vector2i] = []
	var seeds := PackedByteArray()
	for dy in 2:
		for dx in 2:
			var p := Vector2i(drop_pos.x + dx, drop_pos.y + dy)
			if p.x >= 0 and p.x < W and p.y >= 0 and p.y < SIM_HEIGHT:
				pixels.append(p)
				seeds.append(150 + randi() % 80)
	if pixels.size() < 2:
		return
	physics_world._ensure_body_map(W, SIM_HEIGHT)
	var body := physics_world.create_body(pixels, seeds, mat)
	if body:
		body.is_static = false
		body.is_sleeping = false
		body.angular_velocity = 0.0  # Ei pyörimistä — harkko putoaa suoraan
		# Kirjoita pikselit gridiin ja rekisteröi body_map
		for i in pixels.size():
			var p: Vector2i = pixels[i]
			grid[p.y * W + p.x] = mat
			color_seed[p.y * W + p.x] = seeds[i]
			physics_world.body_map[p.y * W + p.x] = body.body_id
	paint_pending = true


func _update_sand_mines(delta: float) -> bool:
	var modified := false
	var alive: Array = []
	for m in sand_mines:
		if m.update_mine(grid, color_seed, W, SIM_HEIGHT, delta):
			modified = true
		if m.broken:
			_unregister_building_pixels(m.structure_pixels)
			m.queue_free()
		else:
			alive.append(m)
	sand_mines = alive
	return modified


func _place_money_exit(pos: Vector2) -> void:
	var me = MoneyExit.new()
	me.setup(Vector2i(pos))
	me.build_structure(grid, color_seed, W, SIM_HEIGHT)
	building_layer.add_child(me)
	money_exits.append(me)
	_register_building_pixels(me.structure_pixels)
	paint_pending = true
	print("Money exit asetettu: ", pos)


func _update_money_exits(delta: float) -> bool:
	var modified := false
	var alive: Array = []
	for me in money_exits:
		var earned: int = me.update_exit(grid, color_seed, W, SIM_HEIGHT, delta)
		if earned > 0:
			money += earned
			modified = true
		if me.broken:
			_unregister_building_pixels(me.structure_pixels)
			me.queue_free()
		else:
			alive.append(me)
	money_exits = alive
	return modified


func _place_crusher(pos: Vector2) -> void:
	var c = Crusher.new()
	c.setup(Vector2i(pos))
	c.build_structure(grid, color_seed, W, SIM_HEIGHT)
	building_layer.add_child(c)
	crushers.append(c)
	_register_building_pixels(c.structure_pixels)
	paint_pending = true
	print("Murskaaja asetettu: ", pos)


func _update_crushers(delta: float) -> bool:
	var modified := false
	var alive: Array = []
	for c in crushers:
		if c.update_crusher(grid, color_seed, W, SIM_HEIGHT, delta):
			modified = true
		if c.output_ready:
			c.output_ready = false
			_spawn_crusher_output(c.output_drop_pos, c.output_material, c.output_amount)
			modified = true
		if c.broken:
			_unregister_building_pixels(c.structure_pixels)
			c.queue_free()
		else:
			alive.append(c)
	crushers = alive
	return modified


func _spawn_crusher_output(drop_pos: Vector2i, mat: int, amount: int) -> void:
	# Kirjoita murskaustuotos suoraan gridiin — ei rigid bodya
	for dy in amount:
		var px: int = drop_pos.x + (dy % 4)
		var py: int = drop_pos.y + (dy / 4)
		if px >= 0 and px < W and py >= 0 and py < SIM_HEIGHT:
			if grid[py * W + px] == 0:
				grid[py * W + px] = mat
				color_seed[py * W + px] = randi() % 256
	paint_pending = true


func _clear_buildings() -> void:
	for f in furnaces:
		f.queue_free()
	furnaces.clear()
	for m in sand_mines:
		m.queue_free()
	sand_mines.clear()
	for me in money_exits:
		me.queue_free()
	money_exits.clear()
	for c in crushers:
		c.queue_free()
	crushers.clear()
	_clear_launchers()


func _clear_launchers() -> void:
	# Poistaa kaikki hissilinkot ja lentävät pikselit
	for s in launchers:
		s.queue_free()
	launchers.clear()
	flying_pixels.clear()
	launcher_phase = 0


func _handle_launcher_click(world_pos: Vector2) -> void:
	# Kolmivaiheinen hissilinkons rakentaminen: pohja → katto → suunta
	match launcher_phase:
		1:  # Vaihe 1: aseta pohja
			var snapped := _snap_to_grid(world_pos)
			launcher_start = Vector2i(int(snapped.x), int(snapped.y))
			launcher_phase = 2
			print("Launcher: pohja asetettu %s — klikkaa katto" % launcher_start)
		2:  # Vaihe 2: aseta katto (x lukittu start.x:ään)
			var snapped := _snap_to_grid(world_pos)
			launcher_end = Vector2i(launcher_start.x, int(snapped.y))
			# Varmista että katto on ylempänä kuin pohja (vähintään 16px)
			if launcher_start.y - launcher_end.y < 16:
				launcher_end.y = launcher_start.y - 16
			launcher_phase = 3
			print("Launcher: katto asetettu %s — klikkaa suunta (vasen/oikea)" % launcher_end)
		3:  # Vaihe 3: valitse suunta hiiren x-aseman mukaan
			var dir := 1.0 if world_pos.x >= float(launcher_start.x) else -1.0
			var launcher := LauncherScript.new()
			launcher.build_structure(launcher_start, launcher_end, dir)
			launcher.write_to_grid(grid, color_seed, W)
			building_layer.add_child(launcher)
			launchers.append(launcher)
			# Rekisteröi kaikki launcherin pikselit suojatuiksi
			_register_building_pixels(launcher.structure_pixels)
			_register_building_pixels(launcher._jalusta_pixels)
			paint_pending = true
			launcher_phase = 1  # Takaisin vaiheeseen 1 — voidaan sijoittaa lisää
			print("Launcher: rakennettu kohtaan %s→%s, suunta %.1f" % [launcher_start, launcher_end, dir])


func _update_launchers_and_flying(delta: float) -> bool:
	var modified := false

	# Hissilinkot: imu kuiluun + kuiluanimaatio + laukaisu
	var alive_launchers: Array = []
	for launcher in launchers:
		# Tarkista rakenne ennen päivitystä
		launcher.check_intact(grid, W)
		if launcher.broken:
			_unregister_building_pixels(launcher.structure_pixels)
			_unregister_building_pixels(launcher._jalusta_pixels)
			launcher.queue_free()
			continue
		# Imu: kerää pikselit intake-alueelta kuiluun
		launcher.update_launcher(grid, W, delta)
		# Kuilu: liikuta pikselit ylöspäin, kerää laukaistavat
		var launched: Array[Dictionary] = launcher.update_shaft(grid, W, SIM_HEIGHT, delta)
		for fp: Dictionary in launched:
			if flying_pixels.size() < flying_max_count:
				flying_pixels.append(fp)
		# Merkitse muokatuksi myös kuiluanimaation aikana (shaft liikutti pikseliä)
		if not launched.is_empty() or not launcher.shaft_pixels.is_empty():
			modified = true
		alive_launchers.append(launcher)
	launchers = alive_launchers

	# Lentävät pikselit: Euler-integraatio + törmäys
	var still_flying: Array[Dictionary] = []
	for fp: Dictionary in flying_pixels:
		fp["age"] += delta
		var is_rocket: bool = fp.get("type", "") == "rocket"

		if fp["age"] > FLYING_MAX_AGE:
			# Pakkolasku — kirjoita nykyiseen kohtaan jos vapaa
			if is_rocket:
				# Raketti vanhenee: räjähtää paikalleen
				var fx := int(fp["pos"].x)
				var fy := int(fp["pos"].y)
				explode(fx, fy, 5)
				add_ca_flash(1.0)
				set_impact(Vector2(fx, fy), 1.0, 1)
			else:
				var fx := int(fp["pos"].x)
				var fy := int(fp["pos"].y)
				_flying_land(fp, fx, fy)
			modified = true
			continue

		var old_pos: Vector2 = fp["pos"]
		var is_bullet: bool = fp.get("type", "") == "bullet"
		# Raketti: pieni gravitaatio, luoti: ei gravitaatiota, normaali pikseli: flying_gravity
		var grav_y := ROCKET_GRAVITY if is_rocket else (0.0 if is_bullet else flying_gravity)
		fp["vel"] = (fp["vel"] as Vector2) + Vector2(0.0, grav_y * delta)
		var new_pos: Vector2 = old_pos + (fp["vel"] as Vector2) * delta

		# Raketti-trail: kirjoita tulipikseli raketin taakse
		if is_rocket:
			var vel_norm: Vector2 = (fp["vel"] as Vector2).normalized()
			var trail_pos := old_pos - vel_norm * 2.0
			var tx := int(trail_pos.x)
			var ty := int(trail_pos.y)
			if tx >= 0 and tx < W and ty >= 0 and ty < SIM_HEIGHT:
				var tidx := ty * W + tx
				if grid[tidx] == MAT_EMPTY:
					grid[tidx] = MAT_FIRE
					paint_pending = true
			# Toinen trail-pikseli hieman lähempänä
			var trail_pos2 := old_pos - vel_norm * 1.0
			var tx2 := int(trail_pos2.x)
			var ty2 := int(trail_pos2.y)
			if tx2 >= 0 and tx2 < W and ty2 >= 0 and ty2 < SIM_HEIGHT:
				var tidx2 := ty2 * W + tx2
				if grid[tidx2] == MAT_EMPTY:
					grid[tidx2] = MAT_FIRE
					paint_pending = true

		# Bresenham törmäystarkistus
		var landed := false
		var pts := _bresenham(Vector2i(int(old_pos.x), int(old_pos.y)),
							  Vector2i(int(new_pos.x), int(new_pos.y)))
		var last_free := Vector2i(int(old_pos.x), int(old_pos.y))
		for pt: Vector2i in pts:
			if pt.x < 0 or pt.x >= W or pt.y >= SIM_HEIGHT:
				if is_rocket:
					# Raketti rajalla — räjähtää
					explode(last_free.x, last_free.y, 5)
					add_ca_flash(1.0)
					set_impact(Vector2(last_free.x, last_free.y), 1.0, 1)
				else:
					_flying_land(fp, last_free.x, last_free.y)
				landed = true
				modified = true
				break
			if pt.y < 0:
				last_free = pt
				continue
			var idx := pt.y * W + pt.x
			var hit_mat := grid[idx]
			# Törmätään kiinteisiin materiaaleihin (kivi, puu) — räjähdykset/luodit
			if hit_mat == MAT_STONE or hit_mat == MAT_WOOD or hit_mat == MAT_WOOD_FALLING:
				if is_rocket:
					# Raketti osui johonkin — pieni räjähdys
					explode(pt.x, pt.y, 5)
					add_ca_flash(1.0)
					set_impact(Vector2(pt.x, pt.y), 1.0, 1)
				elif is_bullet:
					# Luoti tuhoa pari pikseliä
					_bullet_impact(pt.x, pt.y)
				else:
					_flying_land(fp, last_free.x, last_free.y)
				landed = true
				modified = true
				break
			# Tavallinen lentopikeli pysähtyy myös muihin ei-tyhjiin soluihin (hiekka, vesi jne.)
			elif hit_mat != 0 and not is_bullet and not is_rocket:
				_flying_land(fp, last_free.x, last_free.y)
				landed = true
				modified = true
				break
			last_free = pt

		if not landed:
			fp["pos"] = new_pos
			still_flying.append(fp)

	flying_pixels = still_flying
	queue_redraw()
	return modified


func _update_proj_lights() -> void:
	var positions: Array[Vector2] = []
	var types: Array[float] = []
	for fp: Dictionary in flying_pixels:
		if positions.size() >= 8:
			break
		var ftype: String = fp.get("type", "")
		if ftype == "rocket" or ftype == "bullet":
			var p: Vector2 = fp["pos"]
			positions.append(Vector2(p.x / float(W), p.y / float(SIM_HEIGHT)))
			types.append(1.0 if ftype == "rocket" else 0.0)
	var count := positions.size()
	while positions.size() < 8:
		positions.append(Vector2.ZERO)
		types.append(0.0)
	shader_mat.set_shader_parameter("proj_pos", positions)
	shader_mat.set_shader_parameter("proj_type", types)
	shader_mat.set_shader_parameter("proj_count", count)


func _draw() -> void:
	if flying_pixels.is_empty():
		return
	var sz := size
	var pw := sz.x / float(W)
	var ph := sz.y / float(SIM_HEIGHT)
	for fp: Dictionary in flying_pixels:
		var pos: Vector2 = fp["pos"]
		if pos.x < 0 or pos.x >= W or pos.y < 0 or pos.y >= SIM_HEIGHT:
			continue
		# Raketti piirtyy oranssina (tulipallo)
		var col: Color
		if fp.get("type", "") == "rocket":
			col = Color(1.0, 0.5, 0.0)
		else:
			col = _mat_color(fp["mat"])
		draw_rect(Rect2(pos.x * pw, pos.y * ph, pw * 2.0, ph * 2.0), col)


func _mat_color(mat: int) -> Color:
	match mat:
		MAT_SAND:   return Color(0.76, 0.70, 0.50)
		MAT_WATER:  return Color(0.25, 0.45, 0.90, 0.85)
		MAT_STONE:  return Color(0.52, 0.52, 0.52)
		MAT_WOOD:   return Color(0.50, 0.32, 0.12)
		MAT_FIRE:   return Color(1.0, 0.45, 0.1)
		MAT_OIL:    return Color(0.25, 0.20, 0.10)
		_:          return Color(0.8, 0.8, 0.8)


func _flying_land(fp: Dictionary, x: int, y: int) -> void:
	y = clampi(y, 0, SIM_HEIGHT - 1)
	x = clampi(x, 0, W - 1)
	var idx := y * W + x
	if idx >= 0 and idx < grid.size() and not building_pixels.has(idx):
		grid[idx] = fp["mat"]
		color_seed[idx] = fp["seed"]
		paint_pending = true


func _bresenham(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var pts: Array[Vector2i] = []
	var dx := absi(b.x - a.x)
	var dy := absi(b.y - a.y)
	var sx := 1 if a.x < b.x else -1
	var sy := 1 if a.y < b.y else -1
	var err := dx - dy
	var cx := a.x
	var cy := a.y
	for _i in range(dx + dy + 1):
		pts.append(Vector2i(cx, cy))
		if cx == b.x and cy == b.y:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			cx += sx
		if e2 < dx:
			err += dx
			cy += sy
	return pts


func _sell_nearest_building(sell_pos: Vector2) -> void:
	var best_dist := 20.0
	var best_obj = null
	var best_list: Array = []
	var best_idx := -1

	# Tarkista kaikki rakennustyypit
	for i in conveyors.size():
		var belt = conveyors[i]
		var center := (Vector2(belt.start_pos) + Vector2(belt.end_pos)) * 0.5
		var d := sell_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_obj = belt
			best_list = conveyors
			best_idx = i

	for i in furnaces.size():
		var f = furnaces[i]
		var center := Vector2(f.grid_pos) + Vector2(f.FURNACE_W, f.FURNACE_H) * 0.5
		var d := sell_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_obj = f
			best_list = furnaces
			best_idx = i

	for i in sand_mines.size():
		var m = sand_mines[i]
		var center := Vector2(m.grid_pos) + Vector2(m.MINE_W, m.MINE_H) * 0.5
		var d := sell_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_obj = m
			best_list = sand_mines
			best_idx = i

	for i in launchers.size():
		var s = launchers[i]
		# Launchers: center lasketaan start_pos ja shaft-koon mukaan
		var center := Vector2(s.start_pos) + Vector2(float(LauncherScript.SHAFT_WIDTH) * 0.5, float(s.start_pos.y - s.end_pos.y) * 0.5)
		var d := sell_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_obj = s
			best_list = launchers
			best_idx = i

	for i in money_exits.size():
		var me = money_exits[i]
		var center := Vector2(me.grid_pos) + Vector2(me.EXIT_W, me.EXIT_H) * 0.5
		var d := sell_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_obj = me
			best_list = money_exits
			best_idx = i

	for i in crushers.size():
		var c = crushers[i]
		var center := Vector2(c.grid_pos) + Vector2(c.CRUSHER_W, c.CRUSHER_H) * 0.5
		var d := sell_pos.distance_to(center)
		if d < best_dist:
			best_dist = d
			best_obj = c
			best_list = crushers
			best_idx = i

	if best_obj == null or best_idx < 0:
		print("Ei rakennusta lähellä")
		return

	if best_obj.broken:
		print("Rikkinäistä rakennusta ei voi myydä")
		return

	# Poista rakenteen pikselit gridistä
	if best_obj.has_method("get_structure_pixels"):
		for sp in best_obj.get_structure_pixels():
			var p: Vector2i = sp
			if p.x >= 0 and p.x < W and p.y >= 0 and p.y < SIM_HEIGHT:
				grid[p.y * W + p.x] = 0
				color_seed[p.y * W + p.x] = randi() % 256
	elif best_obj is ConveyorBelt:
		for fp in best_obj.floor_pixels:
			var p: Vector2i = fp
			for dy in 3:
				var fy := p.y + dy
				if fy < SIM_HEIGHT and p.x >= 0 and p.x < W:
					grid[fy * W + p.x] = 0
					color_seed[fy * W + p.x] = randi() % 256

	best_list.remove_at(best_idx)
	best_obj.queue_free()
	paint_pending = true
	print("Rakennus myyty!")


func _save_debug_image(path: String) -> void:
	var img := Image.create(W, SIM_HEIGHT, false, Image.FORMAT_RGB8)
	var colors := {
		0: Color(0, 0, 0),        # EMPTY = musta
		1: Color(0.9, 0.8, 0.4),  # SAND = keltainen
		2: Color(0.2, 0.4, 0.9),  # WATER = sininen
		3: Color(0.5, 0.5, 0.5),  # STONE = harmaa
		4: Color(0.4, 0.25, 0.1), # WOOD = ruskea
		5: Color(1, 0.3, 0),      # FIRE = oranssi
		6: Color(0.15, 0.1, 0.05),# OIL = tummanruskea
		7: Color(0.8, 0.8, 0.9),  # STEAM = vaalea
		8: Color(0.3, 0.3, 0.3),  # ASH = tummaharmaa
		9: Color(0.6, 0.35, 0.15),# WOOD_FALLING = vaaleanruskea
	}
	for y in SIM_HEIGHT:
		for x in W:
			var mat := grid[y * W + x]
			var c: Color = colors.get(mat, Color(1, 0, 1))  # Magenta = tuntematon
			img.set_pixel(x, y, c)
	img.save_png(path)
	print("Debug-kuva tallennettu: ", path)


const SAVE_MAGIC := "GMINE1"
const SAVE_VERSION := 4


# Tallentaa kuvakaappauksen + pelitilan JSONin projektin juureen AI-analyysia varten (I)
func _save_ai_screenshot() -> void:
	# --- Kuvakaappaus ---
	var img := get_viewport().get_texture().get_image()
	var img_path := "res://game_view.png"
	if img.save_png(img_path) == OK:
		print("AI-kuvakaappaus tallennettu: ", ProjectSettings.globalize_path(img_path))
	else:
		push_error("AI-kuvakaappaus epäonnistui")

	# --- Pelitila ---
	var mat_names: Dictionary = {
		MAT_EMPTY: "EMPTY", MAT_SAND: "SAND", MAT_WATER: "WATER", MAT_STONE: "STONE",
		MAT_WOOD: "WOOD", MAT_FIRE: "FIRE", MAT_OIL: "OIL", MAT_STEAM: "STEAM",
		MAT_ASH: "ASH", MAT_WOOD_FALLING: "WOOD_FALLING", MAT_GLASS: "GLASS",
		MAT_DIRT: "DIRT", MAT_IRON_ORE: "IRON_ORE", MAT_GOLD_ORE: "GOLD_ORE",
		MAT_IRON: "IRON", MAT_GOLD: "GOLD", MAT_COAL: "COAL"
	}
	var weapon_names: Array[String] = ["PICKAXE", "MEGA_DRILL", "RIFLE", "ROCKET", "GRAVITY_GUN"]
	var grav_modes: Array[String] = ["off", "pull", "vacuum"]

	var state: Dictionary = {
		"timestamp": Time.get_datetime_string_from_system(),
		"fps": Engine.get_frames_per_second(),
		"sim_speed": sim_speed,
		"god_mode": god_mode,
		"player": {
			"x": int(player.position.x),
			"y": int(player.position.y),
			"vel_x": snappedf(player.velocity.x, 0.01),
			"vel_y": snappedf(player.velocity.y, 0.01),
			"on_ground": player.on_ground,
			"in_water": player.in_water,
			"facing_right": player.facing_right
		},
		"weapon": weapon_names[current_weapon],
		"material": {
			"selected": mat_names.get(current_material, str(current_material)),
			"brush_size": brush_size
		},
		"grav_gun": {
			"mode": grav_modes[grav_gun_mode],
			"pos_x": grav_gun_pos.x,
			"pos_y": grav_gun_pos.y,
			"radius": grav_gun_radius,
			"held_pixels": grav_held.size()
		},
		"build_mode": build_mode,
		"buildings": building_pixels.size(),
		"furnaces": furnaces.map(func(f) -> Dictionary: return {
			"x": f.grid_pos.x, "y": f.grid_pos.y,
			"broken": f.broken,
			"glass_ready": f.glass_ready,
			"smelt_timer": snappedf(f.smelt_timer, 0.01),
			"collected": f.collected
		}),
		"world_gen": {
			"cave_threshold_min": WorldGen.cave_threshold_min,
			"cave_threshold_max": WorldGen.cave_threshold_max,
			"cave_warp_str": WorldGen.cave_warp_str,
			"coal_count": WorldGen.coal_count,
			"iron_count": WorldGen.iron_count,
			"gold_count": WorldGen.gold_count,
			"oil_count": WorldGen.oil_count,
			"coal_r_min": WorldGen.coal_r_min,
			"coal_r_max": WorldGen.coal_r_max,
			"iron_r_min": WorldGen.iron_r_min,
			"iron_r_max": WorldGen.iron_r_max,
			"gold_r_min": WorldGen.gold_r_min,
			"gold_r_max": WorldGen.gold_r_max,
			"oil_r_min": WorldGen.oil_r_min,
			"oil_r_max": WorldGen.oil_r_max,
			"dirt_thickness": WorldGen.dirt_thickness,
			"lake_count": WorldGen.lake_count,
		}
	}

	var json_path := "res://game_state.json"
	var file := FileAccess.open(json_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state, "\t"))
		file.close()
		print("AI-pelidata tallennettu: ", ProjectSettings.globalize_path(json_path))
	else:
		push_error("AI-pelidata-tallennus epäonnistui")

	_show_toast("AI-kuvakaappaus tallennettu")


func save_world() -> void:
	var file := FileAccess.open("user://save.dat", FileAccess.WRITE)
	if not file:
		push_error("Tallennus epäonnistui")
		return
	# Header
	file.store_buffer(SAVE_MAGIC.to_utf8_buffer())
	file.store_32(SAVE_VERSION)
	file.store_32(W)
	file.store_32(SIM_HEIGHT)
	# Grid + seeds
	file.store_buffer(grid)
	file.store_buffer(color_seed)
	# Conveyors
	file.store_32(conveyors.size())
	for belt in conveyors:
		file.store_32(belt.start_pos.x)
		file.store_32(belt.start_pos.y)
		file.store_32(belt.end_pos.x)
		file.store_32(belt.end_pos.y)
	# Furnaces
	file.store_32(furnaces.size())
	for f in furnaces:
		file.store_32(f.grid_pos.x + f.FURNACE_W / 2)
		file.store_32(f.grid_pos.y + f.FURNACE_H / 2)
	# Sand mines
	file.store_32(sand_mines.size())
	for m in sand_mines:
		file.store_32(m.grid_pos.x + m.MINE_W / 2)
		file.store_32(m.grid_pos.y + m.MINE_H / 2)
	# Spawners-lukumäärä — kirjoitetaan 0 taaksepäin-yhteensopivuuden vuoksi
	file.store_32(0)
	# Money exits
	file.store_32(money_exits.size())
	for me in money_exits:
		file.store_32(me.grid_pos.x + me.EXIT_W / 2)
		file.store_32(me.grid_pos.y + me.EXIT_H / 2)
	# Crushers
	file.store_32(crushers.size())
	for c in crushers:
		file.store_32(c.grid_pos.x + c.CRUSHER_W / 2)
		file.store_32(c.grid_pos.y + c.CRUSHER_H / 2)
	# Raha
	file.store_32(money)
	file.close()
	print("Tallennettu: %d hihnat, %d uunit, %d kaivokset, %d kassoja, %d murskaajia, $%d" % [
		conveyors.size(), furnaces.size(), sand_mines.size(),
		money_exits.size(), crushers.size(), money])


func load_world() -> void:
	if not FileAccess.file_exists("user://save.dat"):
		print("Tallennusta ei löydy")
		return
	var file := FileAccess.open("user://save.dat", FileAccess.READ)
	if not file:
		push_error("Lataus epäonnistui")
		return
	# Validate header
	var magic := file.get_buffer(SAVE_MAGIC.length()).get_string_from_utf8()
	if magic != SAVE_MAGIC:
		push_error("Virheellinen tallennustiedosto")
		file.close()
		return
	var version := file.get_32()
	if version != SAVE_VERSION:
		push_error("Yhteensopimaton versio: %d" % version)
		file.close()
		return
	var sw := file.get_32()
	var sh := file.get_32()
	if sw != W or sh != SIM_HEIGHT:
		push_error("Koko ei täsmää: %dx%d" % [sw, sh])
		file.close()
		return
	# Grid + seeds — suoraan bufferista
	grid = file.get_buffer(W * SIM_HEIGHT)
	color_seed = file.get_buffer(W * SIM_HEIGHT)
	paint_pending = true
	# Nollaa tila
	physics_world = PhysicsWorld.new()
	_clear_conveyors()
	_clear_buildings()
	# Conveyors — setup ilman build_floor (pikselit jo gridissä)
	var belt_count := file.get_32()
	for _i in belt_count:
		var sx := int(file.get_32())
		var sy := int(file.get_32())
		var ex := int(file.get_32())
		var ey := int(file.get_32())
		var BeltScene := preload("res://scripts/conveyor_belt.gd")
		var belt = BeltScene.new()
		belt.setup(Vector2i(sx, sy), Vector2i(ex, ey))
		building_layer.add_child(belt)
		conveyors.append(belt)
	# Furnaces — setup ilman build_structure (collected-data ei tallenneta, alkaa tyhjänä)
	var furnace_count := file.get_32()
	for _i in furnace_count:
		var cx := int(file.get_32())
		var cy := int(file.get_32())
		var FurnaceScript := preload("res://scripts/furnace.gd")
		var f = FurnaceScript.new()
		f.setup(Vector2i(cx, cy))
		building_layer.add_child(f)
		furnaces.append(f)
	# Sand mines — setup ilman build_structure
	var mine_count := file.get_32()
	for _i in mine_count:
		var cx := int(file.get_32())
		var cy := int(file.get_32())
		var SandMineScript := preload("res://scripts/sand_mine.gd")
		var m = SandMineScript.new()
		m.setup(Vector2i(cx, cy))
		building_layer.add_child(m)
		sand_mines.append(m)
	# Spawners-data ohitetaan (taaksepäin-yhteensopivuus, tallennus kirjoittaa 0)
	var spawner_count := file.get_32()
	for _i in spawner_count:
		file.get_float()
		file.get_float()
	# Money exits
	var exit_count := file.get_32()
	for _i in exit_count:
		var cx := int(file.get_32())
		var cy := int(file.get_32())
		var me = MoneyExit.new()
		me.setup(Vector2i(cx, cy))
		me.build_structure(grid, color_seed, W, SIM_HEIGHT)
		building_layer.add_child(me)
		money_exits.append(me)
	# Crushers
	var crusher_count := file.get_32()
	for _i in crusher_count:
		var cx := int(file.get_32())
		var cy := int(file.get_32())
		var c = Crusher.new()
		c.setup(Vector2i(cx, cy))
		c.build_structure(grid, color_seed, W, SIM_HEIGHT)
		building_layer.add_child(c)
		crushers.append(c)
	# Raha
	money = int(file.get_32())
	file.close()
	build_mode = BUILD_NONE
	build_menu_visible = false
	print("Ladattu: %d hihnat, %d uunit, %d kaivokset, %d kassoja, %d murskaajia, $%d" % [
		conveyors.size(), furnaces.size(), sand_mines.size(),
		money_exits.size(), crushers.size(), money])


# ============================================================
# SCENARIO RUNNER — automaattinen testaus
# Käyttö: godot --path . -- --scenario="polku/scenario.json"
# ============================================================

func _load_scenario(path: String) -> void:
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		push_error("ScenarioRunner: ei voida avata tiedostoa: " + path)
		return
	var json := JSON.new()
	var err := json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("ScenarioRunner: JSON-virhe: " + json.get_error_message())
		return
	var data: Dictionary = json.data
	_scenario_auto_exit = data.get("auto_exit", false)
	_scenario_steps = data.get("steps", [])
	_scenario_index = 0
	_scenario_frames_remaining = 0
	_scenario_failures = 0
	_scenario_tests = 0
	_scenario_active = true
	print("ScenarioRunner: ladattu %d askelta tiedostosta %s" % [_scenario_steps.size(), path])


func _scenario_tick() -> void:
	if _scenario_frames_remaining > 0:
		_scenario_frames_remaining -= 1
		return
	while _scenario_index < _scenario_steps.size():
		var step: Dictionary = _scenario_steps[_scenario_index]
		_scenario_index += 1
		var is_async := _scenario_execute_step(step)
		if is_async:
			return
	_scenario_active = false
	# Tulosta yhteenveto jos on assert-komentoja suoritettu
	var _passed := _scenario_tests - _scenario_failures
	if _scenario_tests > 0:
		print("ScenarioRunner: SUMMARY tests=%d passed=%d failed=%d" % [_scenario_tests, _passed, _scenario_failures])
	else:
		print("ScenarioRunner: kaikki askeleet suoritettu. virheitä=%d" % _scenario_failures)
	if _scenario_auto_exit:
		get_tree().quit(1 if _scenario_failures > 0 else 0)


func _scenario_execute_step(step: Dictionary) -> bool:
	var cmd: String = step.get("cmd", "")
	match cmd:
		"clear":
			clear_world()
			print("ScenarioRunner: clear")
		"fill_rect":
			var x: int = step.get("x", 0)
			var y: int = step.get("y", 0)
			var w: int = step.get("w", 1)
			var h: int = step.get("h", 1)
			var mat: int = step.get("mat", 0)
			_scenario_fill_rect(x, y, w, h, mat)
			print("ScenarioRunner: fill_rect x=%d y=%d w=%d h=%d mat=%d" % [x, y, w, h, mat])
		"run_frames":
			var n: int = step.get("n", 1)
			_scenario_frames_remaining = n
			print("ScenarioRunner: run_frames %d" % n)
			return true
		"export":
			var path: String = step.get("path", "")
			_save_debug_image(path)
			print("ScenarioRunner: export -> %s" % path)
		"assert_material":
			var ax: int = step.get("x", 0)
			var ay: int = step.get("y", 0)
			var expected: int = step.get("mat", 0)
			var label: String = step.get("label", "")
			var idx := ay * W + ax
			if idx >= 0 and idx < grid.size():
				var actual: int = grid[idx]
				if actual == expected:
					print("ScenarioRunner: PASS  [%s] (%d,%d) mat=%d" % [label, ax, ay, expected])
				else:
					print("ScenarioRunner: FAIL  [%s] (%d,%d) odotettu=%d saatiin=%d" % [label, ax, ay, expected, actual])
					_scenario_failures += 1
			else:
				print("ScenarioRunner: FAIL  [%s] koordinaatit (%d,%d) rajojen ulkopuolella" % [label, ax, ay])
				_scenario_failures += 1
			_scenario_tests += 1
		"place_building":
			var btype: String = step.get("type", "")
			var bx: int = step.get("x", 0)
			var by: int = step.get("y", 0)
			var pos := Vector2(bx, by)
			match btype:
				_: push_warning("ScenarioRunner: tuntematon rakennus '%s'" % btype)
			print("ScenarioRunner: place_building type=%s (%d,%d)" % [btype, bx, by])
		"explode":
			var ex: int = step.get("x", W / 2)
			var ey: int = step.get("y", SIM_HEIGHT / 2)
			var er: int = step.get("radius", 15)
			explode(ex, ey, er)
			print("ScenarioRunner: explode (%d,%d) r=%d" % [ex, ey, er])
		"set_sim_speed":
			sim_speed = step.get("speed", 1.0)
			print("ScenarioRunner: set_sim_speed %.1f" % sim_speed)
		"assert_rect":
			# Laske kuinka monta % annetun suorakulmion pikseleistä on haluttua materiaalia
			var rx: int = step.get("x", 0)
			var ry: int = step.get("y", 0)
			var rw: int = step.get("w", 1)
			var rh: int = step.get("h", 1)
			var rmat: int = step.get("mat", 0)
			var min_pct: float = step.get("min_pct", 0.0)
			var rlabel: String = step.get("label", "")
			var total_pixels := 0
			var mat_pixels := 0
			for dy in rh:
				var gy := ry + dy
				if gy < 0 or gy >= SIM_HEIGHT:
					continue
				for dx in rw:
					var gx := rx + dx
					if gx < 0 or gx >= W:
						continue
					total_pixels += 1
					if grid[gy * W + gx] == rmat:
						mat_pixels += 1
			var actual_pct := 0.0
			if total_pixels > 0:
				actual_pct = 100.0 * mat_pixels / total_pixels
			if actual_pct >= min_pct:
				print("ScenarioRunner: PASS  [%s] " % rlabel)
			else:
				print("ScenarioRunner: FAIL  [%s] odotettu >=%.0f%% saatiin %.1f%%" % [rlabel, min_pct, actual_pct])
				_scenario_failures += 1
			_scenario_tests += 1
		"assert_count":
			# Laske koko ruudukosta materiaalin pikselimäärä ja vertaa [min, max]-väliin
			var cmat: int = step.get("mat", 0)
			var cmin: int = step.get("min", 0)
			var cmax: int = step.get("max", 99999999)
			var clabel: String = step.get("label", "")
			var count := 0
			for i in grid.size():
				if grid[i] == cmat:
					count += 1
			if count >= cmin and count <= cmax:
				print("ScenarioRunner: PASS  [%s] " % clabel)
			else:
				print("ScenarioRunner: FAIL  [%s] mat=%d count=%d odotettu [%d, %d]" % [clabel, cmat, count, cmin, cmax])
				_scenario_failures += 1
			_scenario_tests += 1
		"dump_stats":
			# Tulosta materiaalitilastot JSON-muodossa
			var mat_counts: Dictionary = {}
			for i in grid.size():
				var m := grid[i]
				var key := str(m)
				if mat_counts.has(key):
					mat_counts[key] += 1
				else:
					mat_counts[key] = 1
			var body_count := 0
			if physics_world != null:
				body_count = physics_world.bodies.size()
			print("STATS: " + JSON.stringify({
				"frame": frame_count,
				"materials": mat_counts,
				"bodies": body_count
			}))
		"screenshot":
			# Tallenna nykyinen viewport PNG-tiedostoon
			var spath: String = step.get("path", "user://screenshot.png")
			_scenario_screenshot(spath)
		"load_scene":
			# Generoi valmiiksi tehty testiscene
			var scene_name: String = step.get("scene", "empty")
			TestSceneGenerator.generate(scene_name, self)
			print("ScenarioRunner: load_scene '%s'" % scene_name)
		"place_body":
			# Luo dynaaminen fysiikkakappale suorakulmiosta (mat=3 kivi oletuksena)
			var bx: int = step.get("x", 0)
			var by: int = step.get("y", 0)
			var bw: int = step.get("w", 10)
			var bh: int = step.get("h", 10)
			var bmat: int = step.get("mat", MAT_STONE)
			_scenario_place_body(bx, by, bw, bh, bmat)
			print("ScenarioRunner: place_body x=%d y=%d w=%d h=%d mat=%d" % [bx, by, bw, bh, bmat])
		"place_conveyor":
			# Luo liukuhihna kahdesta pisteestä. dir-kenttä tulkitaan end-koordinaateiksi:
			# Vaihtoehto A: anna x1,y1,x2,y2 (absoluuttiset pisteet)
			# Vaihtoehto B: anna x,y,w,dir jossa dir="right"/"left"/"down_right"/"down_left"
			var cx1: int = step.get("x1", step.get("x", 0))
			var cy1: int = step.get("y1", step.get("y", 0))
			var cx2: int = step.get("x2", -1)
			var cy2: int = step.get("y2", -1)
			if cx2 < 0:
				# Laske end-koordinaatti dir+w avulla
				var cw: int = step.get("w", 10)
				var cdir: String = step.get("dir", "right")
				match cdir:
					"right":
						cx2 = cx1 + cw; cy2 = cy1
					"left":
						cx2 = cx1 - cw; cy2 = cy1
					"down_right":
						cx2 = cx1 + cw; cy2 = cy1 + cw
					"down_left":
						cx2 = cx1 - cw; cy2 = cy1 + cw
					"up_right":
						cx2 = cx1 + cw; cy2 = cy1 - cw
					"up_left":
						cx2 = cx1 - cw; cy2 = cy1 - cw
					_:
						cx2 = cx1 + cw; cy2 = cy1
			_create_conveyor(Vector2(cx1, cy1), Vector2(cx2, cy2))
			print("ScenarioRunner: place_conveyor (%d,%d) → (%d,%d)" % [cx1, cy1, cx2, cy2])
		"place_launcher":
			# Luo launcher suoraan: {"cmd":"place_launcher","start_x":200,"start_y":180,"end_y":120,"dir":1}
			var lx: int = step.get("start_x", 200)
			var ly: int = step.get("start_y", 180)
			var ey: int = step.get("end_y", 120)
			var ldir: float = step.get("dir", 1.0)
			var lstart := Vector2i(_snap_to_grid(Vector2(lx, ly)))
			var lend := Vector2i(lstart.x, int(_snap_to_grid(Vector2(lx, ey)).y))
			var ln := LauncherScript.new()
			ln.build_structure(lstart, lend, ldir)
			ln.write_to_grid(grid, color_seed, W)
			launchers.append(ln)
			physics_initialized = true
			paint_pending = true
			print("ScenarioRunner: place_launcher start=%s end=%s dir=%.1f" % [lstart, lend, ldir])
		"set_grav_gun":
			# Aseta gravity gun -tila suoraan skenaariosta
			var ggx: int = step.get("x", W / 2)
			var ggy: int = step.get("y", SIM_HEIGHT / 2)
			var ggmode: int = step.get("mode", 1)
			grav_gun_mode = ggmode
			grav_gun_pos = Vector2i(ggx, ggy)
			grav_held.clear()
			grav_held_written.clear()
			print("ScenarioRunner: set_grav_gun mode=%d pos=(%d,%d)" % [ggmode, ggx, ggy])
		"clear_grav_gun":
			grav_gun_mode = 0
			grav_held.clear()
			grav_held_written.clear()
			print("ScenarioRunner: clear_grav_gun")
		_:
			push_warning("ScenarioRunner: tuntematon komento '%s'" % cmd)
	return false


func _scenario_fill_rect(x: int, y: int, w: int, h: int, mat: int) -> void:
	for dy in h:
		var gy := y + dy
		if gy < 0 or gy >= SIM_HEIGHT:
			continue
		for dx in w:
			var gx := x + dx
			if gx < 0 or gx >= W:
				continue
			var idx := gy * W + gx
			grid[idx] = mat
			color_seed[idx] = randi() % 256
	paint_pending = true


func _scenario_place_body(x: int, y: int, w: int, h: int, mat: int) -> void:
	# Kirjoita pikselit gridiin ja luo dynaaminen fysiikkakappale
	var pixels: Array[Vector2i] = []
	for dy in h:
		var gy := y + dy
		if gy < 0 or gy >= SIM_HEIGHT:
			continue
		for dx in w:
			var gx := x + dx
			if gx < 0 or gx >= W:
				continue
			var idx := gy * W + gx
			grid[idx] = mat
			color_seed[idx] = randi() % 256
			pixels.append(Vector2i(gx, gy))
	paint_pending = true

	if pixels.size() < 4:
		return

	var seeds := PackedByteArray()
	seeds.resize(pixels.size())
	for i in pixels.size():
		var p: Vector2i = pixels[i]
		seeds[i] = color_seed[p.y * W + p.x]

	physics_world._ensure_body_map(W, SIM_HEIGHT)
	var body := physics_world.create_body(pixels, seeds, mat)
	if body:
		body.is_static = false
		body.is_sleeping = false
		for p in pixels:
			physics_world.body_map[p.y * W + p.x] = body.body_id
	# Estä scan_stone_bodies ylikirjoittamasta tätä dynaamisena luotua kappaletta
	physics_initialized = true


func _scenario_screenshot(path: String) -> void:
	# Tallenna viewport kuvakaappauksena PNG-tiedostoon
	var img: Image = get_viewport().get_texture().get_image()
	if img == null:
		push_error("ScenarioRunner: viewport-tekstuuri null, screenshot epäonnistui")
		return
	var err := img.save_png(path)
	if err == OK:
		print("SCREENSHOT: ", path)
	else:
		push_error("ScenarioRunner: screenshot-tallennus epäonnistui (%d): %s" % [err, path])


func _autofill_test() -> void:
	# Täytä 25% maailmasta hiekalla mittausta varten
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in TOTAL:
		if rng.randf() < 0.25:
			grid[i] = MAT_SAND
			color_seed[i] = rng.randi_range(0, 255)
	paint_pending = true
	print("AUTOFILL: täytetty 25% maailmasta hiekalla, mitataan suorituskykyä...")


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if _vis_thread != null and _vis_thread.is_alive():
			_vis_thread.wait_to_finish()
		if gpu_ready and rd != null:
			rd.free_rid(pipeline)
			rd.free_rid(uniform_set)
			rd.free_rid(grid_buffer)
			rd.free_rid(shader_rid)
			rd.free()
