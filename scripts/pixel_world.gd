extends TextureRect

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

const SIM_WIDTH := 320
const SIM_HEIGHT := 180
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

# Renderöinti
var grid_image: Image
var grid_texture: ImageTexture
var seed_image: Image
var seed_texture: ImageTexture
var shader_mat: ShaderMaterial

var current_material: int = MAT_SAND
var brush_size: int = 5
var frame_count: int = 0
var fps_timer: float = 0.0
var paint_pending := false
var cut_mode := false  # Leikkaustila

# Fysiikkamoottori
var physics_world: PhysicsWorld
var physics_initialized := false
var is_painting_stone := false  # Maalataan kiveä parhaillaan — fysiikka tauolla
var stroke_stone_pixels: Dictionary = {}  # Tämän vedon kivipikselit (deduplikoitu)


func _ready() -> void:
	grid = PackedByteArray()
	grid.resize(TOTAL)
	grid.fill(0)
	color_seed = PackedByteArray()
	color_seed.resize(TOTAL)

	for i in TOTAL:
		color_seed[i] = randi() % 256

	# Pohjakerros
	for x in W:
		for y in range(SIM_HEIGHT - 3, SIM_HEIGHT):
			grid[y * W + x] = MAT_STONE

	print("GodotMining valmis — C = tyhjennä kenttä")

	# Renderöinti-tekstuurit
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
	material = shader_mat

	# Fysiikkamoottori
	physics_world = PhysicsWorld.new()

	# GPU compute setup
	_setup_compute()


func _setup_compute() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		print("ERROR: Ei voitu luoda RenderingDevice:a")
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


func _process(delta: float) -> void:
	frame_count += 1
	fps_timer += delta
	if fps_timer >= 1.0:
		print("FPS: %d | frame: %.1fms" % [Engine.get_frames_per_second(), delta * 1000.0])
		fps_timer = 0.0

	_handle_input()

	if gpu_ready:
		# Lataa mahdolliset maalaukset GPU:lle
		var needs_gpu_upload := paint_pending
		if paint_pending:
			_upload_paint_to_gpu()
			paint_pending = false

		# Vaihe 1: CA-simulaatio GPU:lla (hiekka, vesi, tuli, jne.)
		_simulate_gpu()

		# Lataa tulos takaisin CPU:lle
		_download_from_gpu()

		# Vaihe 2: Tunnista kivi-kappaleet ensimmäisellä framella
		if not physics_initialized:
			physics_world.scan_stone_bodies(grid, color_seed, W, SIM_HEIGHT)
			physics_initialized = true

		# Vaihe 3: Rigid body -fysiikka (CPU)
		var grid_modified := false
		if not physics_world.bodies.is_empty():
			physics_world.step(grid, color_seed, W, SIM_HEIGHT)
			grid_modified = true

		# Vaihe 4: Tarkista puun tuki joka 10. frame
		if frame_count % 10 == 0:
			if WoodSupport.check_support(grid, W, SIM_HEIGHT):
				grid_modified = true

		# Vaihe 5: Tarkista vauriot harvemmin (ei joka frame)
		if frame_count % 10 == 3 and not physics_world.bodies.is_empty():
			physics_world.check_damage(grid, color_seed, W, SIM_HEIGHT)

		# Vaihe 6: Lataa CPU:n muutokset takaisin GPU:lle (vain kerran)
		if grid_modified:
			_upload_paint_to_gpu()

	_upload_render()


func _handle_input() -> void:
	var left_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	if left_pressed:
		var coords := _mouse_to_grid()
		if coords.x >= 0:
			if cut_mode:
				_cut(coords.x, coords.y)
			else:
				if current_material == MAT_STONE:
					is_painting_stone = true
				_paint(coords.x, coords.y, current_material)
	elif right_pressed:
		var coords := _mouse_to_grid()
		if coords.x >= 0:
			_paint(coords.x, coords.y, MAT_EMPTY)
	else:
		# Hiiri päästetty irti — luo kappale piirtovedosta
		if is_painting_stone and not stroke_stone_pixels.is_empty():
			_create_stroke_body()
			stroke_stone_pixels.clear()
		is_painting_stone = false


func _mouse_to_grid() -> Vector2i:
	var mp := get_local_mouse_position()
	# TextureRect:n todellinen koko huomioiden stretch
	var tex_size := size
	var gx := int(mp.x / tex_size.x * W)
	var gy := int(mp.y / tex_size.y * SIM_HEIGHT)
	if gx < 0 or gx >= W or gy < 0 or gy >= SIM_HEIGHT:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func clear_world() -> void:
	grid.fill(0)
	color_seed.fill(0)
	for i in TOTAL:
		color_seed[i] = randi() % 256
	# Pohjakerros kivestä
	for x in W:
		for y in range(SIM_HEIGHT - 3, SIM_HEIGHT):
			grid[y * W + x] = MAT_STONE
	paint_pending = true
	# Nollaa fysiikkamaailma
	physics_world = PhysicsWorld.new()
	physics_initialized = false


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
			# Rekisteröi body_map
			for p in comp_pixels:
				physics_world.body_map[p.y * W + p.x] = body.body_id


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1: current_material = MAT_SAND
			KEY_2: current_material = MAT_WATER
			KEY_3: current_material = MAT_STONE
			KEY_4: current_material = MAT_WOOD
			KEY_5: current_material = MAT_FIRE
			KEY_6: current_material = MAT_OIL
			KEY_E: current_material = MAT_EMPTY
			KEY_X:
				cut_mode = not cut_mode
				print("Leikkaustila: %s" % ("PÄÄLLÄ" if cut_mode else "POIS"))
			KEY_C: clear_world()


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
					grid[idx] = mat
					color_seed[idx] = randi() % 256
					# Kerää kivipikselit vedon aikana
					if mat == MAT_STONE and is_painting_stone:
						stroke_stone_pixels[Vector2i(nx, ny)] = true
	paint_pending = true


# Leikkaa materiaalia ohuella viivalla (1px leveys)
func _cut(cx: int, cy: int) -> void:
	var cut_size := 1  # Ohut leikkaus
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
				var mat := grid[idx]
				if mat == MAT_STONE or mat == MAT_WOOD:
					grid[idx] = MAT_EMPTY
					changed = true
	if changed:
		paint_pending = true
		# check_damage hoitaa kappaleiden halkeamisen automaattisesti


func _upload_paint_to_gpu() -> void:
	# Päivitä koko bufferi (yksinkertaisin, 230KB on nopea)
	var gpu_data := PackedByteArray()
	gpu_data.resize(TOTAL * 4)
	for i in TOTAL:
		gpu_data.encode_u32(i * 4, grid[i] | (color_seed[i] << 8))
	rd.buffer_update(grid_buffer, 0, gpu_data.size(), gpu_data)


func _simulate_gpu() -> void:
	# Per-pikseli dispatch: jokainen pikseli = yksi thread
	var groups_x := ceili(float(W) / 16.0)
	var groups_y := ceili(float(SIM_HEIGHT) / 16.0)

	# Useampi passi per frame — jokainen passi eri satunnaissiemen
	# 6 passia riittää sulavaan liikkeeseen
	var push := PackedByteArray()
	push.resize(32)
	push.encode_u32(0, W)
	push.encode_u32(4, SIM_HEIGHT)

	for pass_i in 6:
		push.encode_u32(8, frame_count * 6 + pass_i)
		push.encode_u32(12, pass_i)
		push.encode_u32(16, 0)

		var cl := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
		rd.compute_list_set_push_constant(cl, push, push.size())
		rd.compute_list_dispatch(cl, groups_x, groups_y, 1)
		rd.compute_list_end()

	rd.submit()
	rd.sync()


func _download_from_gpu() -> void:
	var output := rd.buffer_get_data(grid_buffer)
	for i in TOTAL:
		var val: int = output.decode_u32(i * 4)
		grid[i] = val & 0xFF
		color_seed[i] = (val >> 8) & 0xFF


func _upload_render() -> void:
	grid_image = Image.create_from_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, grid)
	grid_texture.update(grid_image)
	seed_image = Image.create_from_data(W, SIM_HEIGHT, false, Image.FORMAT_R8, color_seed)
	seed_texture.update(seed_image)
	shader_mat.set_shader_parameter("frame", frame_count)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if gpu_ready and rd != null:
			rd.free_rid(pipeline)
			rd.free_rid(uniform_set)
			rd.free_rid(grid_buffer)
			rd.free_rid(shader_rid)
			rd.free()
