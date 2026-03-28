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

# Screenshake
var trauma: float = 0.0
var shake_offset: Vector2 = Vector2.ZERO

# Räjähdykset
var explosion_size: int = 1  # 0=pieni, 1=keski, 2=iso, 3=mega
const EXPLOSION_RADII: Array[int] = [8, 15, 25, 40]
const EXPLOSION_TRAUMA: Array[float] = [0.2, 0.5, 0.8, 1.0]

# Räjähdysflash
var flash_pos: Vector2 = Vector2.ZERO
var flash_radius: float = 0.0
var flash_timer: int = 0  # Frameja jäljellä (0 = ei flashia)
const FLASH_DURATION := 6  # Frameja

# Gravity gun
var grav_gun_mode: int = 0  # 0=off, 1=pull, 2=push
var grav_gun_pos: Vector2i = Vector2i.ZERO
const GRAV_GUN_RADIUS := 40
const GRAV_GUN_BODY_STRENGTH := 3.0
var mouse_velocity: Vector2 = Vector2.ZERO
var prev_mouse_grid: Vector2 = Vector2.ZERO

# Fysiikkamoottori
var physics_world: PhysicsWorld
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

	# Generoi luolamaailma
	WorldGen.generate(grid, color_seed, W, SIM_HEIGHT)

	print("GodotMining valmis — C = tyhjennä, R = uusi maailma")

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

	# Screenshake
	_update_screenshake(delta)

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

		# Vaihe 2: Ei skannata kivibodeja startissa — luodaan vain räjähdyksistä
		# (scan_stone_bodies poistettiin — terraini on pelkkiä pikseleitä)

		# Vaihe 3: Rigid body -fysiikka (vain aktiivisille kappaleille)
		var grid_modified := false
		if not physics_world.bodies.is_empty():
			# Tarkista onko aktiivisia bodeja ENNEN step-kutsua
			var has_active := false
			for body_id in physics_world.bodies:
				var body: RigidBodyData = physics_world.bodies[body_id]
				if not body.is_sleeping and not body.is_static:
					has_active = true
					break
			if has_active:
				physics_world.step(grid, color_seed, W, SIM_HEIGHT)
				grid_modified = true

		# Vaihe 4: Puun tuki joka 10. frame (viive: anna maailman asettua)
		if frame_count > 60 and frame_count % 10 == 0:
			if WoodSupport.check_support(grid, W, SIM_HEIGHT):
				grid_modified = true

		# Vaihe 5: Vauriotarkistus (vain räjähdyksen jälkeen)
		if physics_world.force_damage_check and not physics_world.bodies.is_empty():
			physics_world.check_damage(grid, color_seed, W, SIM_HEIGHT)
			physics_world.force_damage_check = false
			grid_modified = true

		# Vaihe 6: Lataa CPU:n muutokset GPU:lle vain jos oikeasti muuttui
		if grid_modified:
			_upload_paint_to_gpu()

	_upload_render()


func _handle_input() -> void:
	var left_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right_pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)

	# Gravity gun — oikea hiiri
	if right_pressed:
		var coords := _mouse_to_grid()
		if coords.x >= 0:
			var current_pos := Vector2(coords)
			mouse_velocity = current_pos - prev_mouse_grid
			prev_mouse_grid = current_pos

			grav_gun_mode = 1  # Vetomoodi
			grav_gun_pos = coords

			# Rigid body -veto CPU:lla
			physics_world.apply_attraction(
				Vector2(coords), float(GRAV_GUN_RADIUS), GRAV_GUN_BODY_STRENGTH
			)
	elif grav_gun_mode == 1:
		# Oikea hiiri päästetty — heitä CPU:lla suuntaan
		if mouse_velocity.length() > 0.5:
			_throw_pixels(grav_gun_pos, GRAV_GUN_RADIUS, mouse_velocity * 4.0)
			physics_world.apply_throw(
				Vector2(grav_gun_pos), float(GRAV_GUN_RADIUS),
				mouse_velocity * 3.0
			)
		grav_gun_mode = 0
		mouse_velocity = Vector2.ZERO

	if left_pressed:
		var coords := _mouse_to_grid()
		if coords.x >= 0:
			if cut_mode:
				_cut(coords.x, coords.y)
			else:
				if current_material == MAT_STONE:
					is_painting_stone = true
				_paint(coords.x, coords.y, current_material)
	elif not right_pressed:
		# Hiiri päästetty irti — luo kappale piirtovedosta
		if is_painting_stone and not stroke_stone_pixels.is_empty():
			_create_stroke_body()
			stroke_stone_pixels.clear()
		is_painting_stone = false


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
		# Scroll vaihtaa räjähdyskokoa (Shift pohjassa)
		elif event.shift_pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			explosion_size = mini(explosion_size + 1, 3)
			print("Räjähdyskoko: %d (r=%d)" % [explosion_size, EXPLOSION_RADII[explosion_size]])
		elif event.shift_pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			explosion_size = maxi(explosion_size - 1, 0)
			print("Räjähdyskoko: %d (r=%d)" % [explosion_size, EXPLOSION_RADII[explosion_size]])


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
	for i in TOTAL:
		color_seed[i] = randi() % 256
	paint_pending = true
	# Nollaa fysiikkamaailma
	physics_world = PhysicsWorld.new()


# === SCREENSHAKE ===

func _update_screenshake(delta: float) -> void:
	if trauma > 0.0:
		trauma = maxf(trauma - delta * 1.5, 0.0)
		var shake_amount := trauma * trauma  # Neliöllinen — pienet iskut vaimeita, isot rajuja
		var max_px := 8.0
		shake_offset.x = randf_range(-1.0, 1.0) * max_px * shake_amount
		shake_offset.y = randf_range(-1.0, 1.0) * max_px * shake_amount
		position = shake_offset
	elif position != Vector2.ZERO:
		position = Vector2.ZERO
		shake_offset = Vector2.ZERO


func add_trauma(amount: float) -> void:
	trauma = minf(trauma + amount, 1.0)


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

			if dist2 <= inner_r2:
				# Sisäalue: tyhjennä kokonaan
				if mat == MAT_OIL:
					grid[idx] = MAT_FIRE  # Öljy syttyy!
				else:
					grid[idx] = MAT_EMPTY
					# Poista body_map-merkintä
					if physics_world.body_map.size() > idx:
						physics_world.body_map[idx] = 0
			else:
				# Ulkoreuna: debris-konversio
				if mat == MAT_STONE:
					grid[idx] = MAT_SAND  # Kivi → irtonainen hiekka
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

	# Screenshake
	var trauma_amount := EXPLOSION_TRAUMA[clampi(explosion_size, 0, 3)]
	add_trauma(trauma_amount)

	# Räjähdysflash
	flash_pos = Vector2(float(cx) / float(W), float(cy) / float(SIM_HEIGHT))
	flash_radius = float(radius) / float(W) * 1.5
	flash_timer = FLASH_DURATION

	paint_pending = true


func regenerate_world() -> void:
	grid.fill(0)
	for i in TOTAL:
		color_seed[i] = randi() % 256
	WorldGen.generate(grid, color_seed, W, SIM_HEIGHT)
	paint_pending = true
	physics_world = PhysicsWorld.new()
	print("Maailma regeneroitu!")


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


func _input(event: InputEvent) -> void:
	# Räjähdykset (keskihiiri + scroll) — _input jotta UI ei syö eventtiä
	_handle_explosion_input(event)


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
			KEY_R: regenerate_world()


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
	push.resize(48)  # Laajennettu gravity gun -kentillä
	push.encode_u32(0, W)
	push.encode_u32(4, SIM_HEIGHT)

	for pass_i in 6:
		push.encode_u32(8, frame_count * 6 + pass_i)
		push.encode_u32(12, pass_i)
		push.encode_u32(16, 0)
		# Gravity gun -tila (0=off, 1=pull, 2=push)
		push.encode_u32(20, grav_gun_pos.x if grav_gun_mode > 0 else 0)
		push.encode_u32(24, grav_gun_pos.y if grav_gun_mode > 0 else 0)
		push.encode_u32(28, grav_gun_mode)
		push.encode_u32(32, GRAV_GUN_RADIUS)
		# Padding loppu (36-47)
		push.encode_u32(36, 0)
		push.encode_u32(40, 0)
		push.encode_u32(44, 0)

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
	# Räjähdysflash
	if flash_timer > 0:
		shader_mat.set_shader_parameter("flash_uv", flash_pos)
		shader_mat.set_shader_parameter("flash_radius", flash_radius)
		shader_mat.set_shader_parameter("flash_intensity", float(flash_timer) / float(FLASH_DURATION))
		flash_timer -= 1
	else:
		shader_mat.set_shader_parameter("flash_intensity", 0.0)
	# Gravity gun -efekti renderöintishaderille
	shader_mat.set_shader_parameter("grav_gun_active", 1 if grav_gun_mode > 0 else 0)
	if grav_gun_mode > 0:
		shader_mat.set_shader_parameter("grav_gun_uv", Vector2(
			float(grav_gun_pos.x) / float(W),
			float(grav_gun_pos.y) / float(SIM_HEIGHT)
		))
		shader_mat.set_shader_parameter("grav_gun_radius", float(GRAV_GUN_RADIUS) / float(W))


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

			# Naapurit
			if px > 0 and visited[idx - 1] == 0 and grid[idx - 1] == MAT_STONE and physics_world.body_map[idx - 1] == 0:
				visited[idx - 1] = 1
				queue.append(idx - 1)
			if px < W - 1 and visited[idx + 1] == 0 and grid[idx + 1] == MAT_STONE and physics_world.body_map[idx + 1] == 0:
				visited[idx + 1] = 1
				queue.append(idx + 1)
			if py > 0 and visited[idx - W] == 0 and grid[idx - W] == MAT_STONE and physics_world.body_map[idx - W] == 0:
				visited[idx - W] = 1
				queue.append(idx - W)
			if py < SIM_HEIGHT - 1 and visited[idx + W] == 0 and grid[idx + W] == MAT_STONE and physics_world.body_map[idx + W] == 0:
				visited[idx + W] = 1
				queue.append(idx + W)

		# Irtonaiset (ei kosketa reunaa) → rigid body
		if not touches_edge and region.size() >= 4:
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


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if gpu_ready and rd != null:
			rd.free_rid(pipeline)
			rd.free_rid(uniform_set)
			rd.free_rid(grid_buffer)
			rd.free_rid(shader_rid)
			rd.free()
