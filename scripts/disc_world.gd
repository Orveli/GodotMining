class_name DiscWorld
extends Node2D

# Kiekkoplaneetta-prototyypin world-skripti (docs/SPEC_disc_planet.md, Vaihe 3).
# Lean, EI riippuvuutta pixel_world.gd:hen — patterneja on kopioitu sielta (RD-pipeline,
# push constant -pakkaus, dispatch-silmukka), mutta tama on itsenainen scene.
#
# Ydinpointti: EI SubViewport-koko-maailman-komposiittia. Grid piirretaan Sprite2D:hen
# ja kameratransformi (pan/zoom) hoitaa nayton -> renderkustannus skaalautuu RUUDUN
# (ei maailman) mukaan.
#
# Renderointi kayttaa shaders/pixel_render.gdshader:ia SELLAISENAAN:
#   - materiaali luetaan TEXTURE.r:sta. Syotamme RGBA8-tekstuurin joka rakennetaan
#     suoraan grid-int32-puskurin tavuista (little-endian byte0 = materiaalitavu -> R).
#     Nain per-frame-paivitys on O(1) memcpy (ei GDScript-solusilmukkaa).
#   - seed luetaan erillisesta seed_tex.r:sta (staattinen, rakennetaan kerran).
#   - light_tex asetetaan valkoiseksi (ei fog of war -prototyypissa).
#
# Sim:
#   - GPU (ikkunallinen, Vulkan): simulation_disc.glsl, GPU_PASSES passia/frame.
#   - Headless / ei-Vulkan: DiscCpuCa (deterministinen CPU-referenssi).
# Headless-boottaus: create_local_rendering_device() == null -> gpu_ready=false -> CPU.

const Geom = preload("res://scripts/disc_geom.gd")
const WorldGenScript = preload("res://scripts/disc_world_gen.gd")
const CpuCaScript = preload("res://scripts/disc_cpu_ca.gd")

# Margolus vaatii passimaaran joka on 4:n monikerta (nelivaihe-checkerboard).
const GPU_PASSES := 12
const DEFAULT_SEED := 20260718

# Kamera-tuning.
const PAN_SPEED := 600.0        # px/s ruudulla (jaetaan zoomilla -> maailmanopeus)
const ZOOM_STEP := 1.15         # rullan zoom-kerroin per pykala
const ZOOM_MIN := 0.05
const ZOOM_MAX := 8.0

# Varipaletti — kopioitu pixel_world.gd:sta (indeksit 0..21). Kaytetaan sseka
# pixel_render-shaderissa (Vector3) etta CPU-debug-PNG:ssa (Color).
const PALETTE: Array = [
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
	Vector3(0.66, 0.40, 0.26),   # 12 IRON_ORE
	Vector3(0.72, 0.65, 0.25),   # 13 GOLD_ORE
	Vector3(0.68, 0.68, 0.72),   # 14 IRON
	Vector3(0.90, 0.78, 0.20),   # 15 GOLD
	Vector3(0.18, 0.17, 0.21),   # 16 COAL
	Vector3(1.0, 0.85, 0.1),     # 17 HELD
	Vector3(0.70, 0.59, 0.45),   # 18 GRAVEL
	Vector3(0.25, 0.22, 0.30),   # 19 BEDROCK
	Vector3(0.72, 0.45, 0.28),   # 20 COPPER
	Vector3(0.35, 0.75, 0.65),   # 21 RARE_EARTH
]

const PALETTE_VAR: Array = [
	0.0, 0.06, 0.04, 0.05, 0.04, 0.2, 0.02, 0.05, 0.03, 0.04, 0.03,
	0.03, 0.08, 0.04, 0.02, 0.02, 0.05, 0.05, 0.07, 0.03, 0.04, 0.05
]

# Maalattavat materiaalit numeronappaimille 1..6 + pari malmia (Q/R).
const PAINT_KEYS := {
	KEY_1: Geom.MAT_SAND,
	KEY_2: Geom.MAT_WATER,
	KEY_3: Geom.MAT_STONE,
	KEY_4: Geom.MAT_WOOD,
	KEY_5: Geom.MAT_OIL,
	KEY_6: Geom.MAT_DIRT,
	KEY_Q: Geom.MAT_IRON_ORE,
	KEY_R: Geom.MAT_GOLD_ORE,
}

# --- Tila ---
var n: int = Geom.GRID_N
var grid: PackedInt32Array = PackedInt32Array()
var cpu_ca: CpuCaScript
var frame: int = 0
var world_seed: int = DEFAULT_SEED

var headless: bool = false
var _fps_accum: float = 0.0
var _fps_frames: int = 0
var _fps: float = 0.0

# --- Maalaus/input ---
var current_material: int = Geom.MAT_SAND
var brush_size: int = 4
var _mid_drag: bool = false

# --- GPU ---
var gpu_ready: bool = false
var rd: RenderingDevice
var shader_rid: RID
var grid_buffer: RID
var activity_buffer: RID
var uniform_set: RID
var pipeline: RID
var sim_frame: int = 0
var paint_pending: bool = false
var _need_upload: bool = true       # lataa CPU-grid GPU:lle ennen ensimmaista simulaatiota
var _gpu_grid_stale: bool = false   # CPU-grid ei vastaa uusinta GPU-tulosta (odottaa syncia)
var _gpu_bytes: PackedByteArray = PackedByteArray()  # uusin GPU-readback (renderin lahde)

# --- Renderointi ---
var terrain: Sprite2D
var camera: Camera2D
var info_label: Label
var mat_texture: ImageTexture
var seed_texture: ImageTexture
var white_texture: ImageTexture
var shader_mat: ShaderMaterial

# --- Cmdline-savuajo ---
var _cli_frames: int = -1
var _cli_out: String = ""


func _ready() -> void:
	_parse_cmdline()
	headless = DisplayServer.get_name() == "headless"

	# Maailma + CPU-CA aina (CPU-CA on myos headless-fallback ja cmdline-savuajo).
	grid = WorldGenScript.generate(world_seed, n)
	cpu_ca = CpuCaScript.new()
	print("DiscWorld: maailma generoitu (n=%d, seed=%d, headless=%s)" % [n, world_seed, str(headless)])

	# Cmdline-savuajo: generoi -> steppaa CPU-CA -> dumppaa PNG -> quit. Ei rendering/GPU.
	if _cli_frames >= 0:
		_run_cli_smoke()
		return

	if headless:
		# Ilman --disc-frames headless-ajolla ei ole renderointia -> ei jaada pyorimaan
		# tyhjaa _process-silmukkaa. Todistetaan pelkka boottaus (worldgen + CPU-CA valmis)
		# ja poistutaan siististi. Varsinainen headless-savuajo kaytetaan --disc-frames:lla.
		print("DiscWorld: headless-boot ok (ei --disc-frames -> quit). Savuajo: --disc-frames=N")
		call_deferred("_quit_ok")
		return

	_setup_nodes()
	_setup_render()
	_setup_gpu()
	_setup_camera()


# ============================================================
# Setup
# ============================================================

func _setup_nodes() -> void:
	terrain = get_node_or_null("Terrain") as Sprite2D
	camera = get_node_or_null("Camera") as Camera2D
	info_label = get_node_or_null("HUD/Info") as Label
	if terrain == null:
		terrain = Sprite2D.new()
		terrain.name = "Terrain"
		add_child(terrain)
	if camera == null:
		camera = Camera2D.new()
		camera.name = "Camera"
		add_child(camera)


func _setup_render() -> void:
	# Materiaalitekstuuri: RGBA8, R = materiaalitavu (rakennetaan grid-tavuista O(1)).
	var mat_img := _build_mat_image(grid.to_byte_array())
	mat_texture = ImageTexture.create_from_image(mat_img)

	# Seed-tekstuuri: staattinen R8, per-solu-seedtavu grid:sta (kerran).
	var seed_bytes := PackedByteArray()
	seed_bytes.resize(n * n)
	for i in n * n:
		seed_bytes[i] = (grid[i] >> 8) & 0xFF
	var seed_img := Image.create_from_data(n, n, false, Image.FORMAT_R8, seed_bytes)
	seed_texture = ImageTexture.create_from_image(seed_img)

	# Valkoinen 1x1 light_tex (ei fog of war -prototyypissa) — muuten shaderin
	# "color *= texture(light_tex).r" mustaisi koko terrainin.
	var white := Image.create(1, 1, false, Image.FORMAT_R8)
	white.set_pixel(0, 0, Color(1, 1, 1))
	white_texture = ImageTexture.create_from_image(white)

	shader_mat = ShaderMaterial.new()
	shader_mat.shader = load("res://shaders/pixel_render.gdshader") as Shader
	shader_mat.set_shader_parameter("seed_tex", seed_texture)
	shader_mat.set_shader_parameter("light_tex", white_texture)
	shader_mat.set_shader_parameter("frame", 0)
	shader_mat.set_shader_parameter("mat_colors", PALETTE)
	shader_mat.set_shader_parameter("mat_var", PALETTE_VAR)
	shader_mat.set_shader_parameter("screen_aspect", 1.0)  # nelio-grid

	terrain.texture = mat_texture
	terrain.material = shader_mat
	terrain.centered = false          # pikseli (0,0) maailman origoon -> grid = floor(world)
	terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _setup_gpu() -> void:
	rd = RenderingServer.create_local_rendering_device()
	if rd == null:
		print("DiscWorld: RenderingDevice ei saatavilla -> CPU-CA-fallback")
		return

	var src := FileAccess.get_file_as_string("res://shaders/simulation_disc.glsl")
	if src.is_empty():
		print("DiscWorld: simulation_disc.glsl luku epaonnistui -> CPU-fallback")
		return
	# CRLF-normalisointi ENNEN markerin poistoa (Windows-checkout tuottaa CRLF:n).
	src = src.replace("\r\n", "\n").replace("#[compute]\n", "")

	var shader_source := RDShaderSource.new()
	shader_source.source_compute = src
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if spirv.compile_error_compute != "":
		print("DiscWorld: shader-kaannosvirhe: ", spirv.compile_error_compute)
		return
	shader_rid = rd.shader_create_from_spirv(spirv)
	if not shader_rid.is_valid():
		print("DiscWorld: shaderin luonti epaonnistui -> CPU-fallback")
		return

	# Grid-bufferi: n*n uint32 (koko solu, seed mukana).
	var gpu_data := grid.to_byte_array()
	grid_buffer = rd.storage_buffer_create(gpu_data.size(), gpu_data)

	# P2-aktiivisuustaulu: (n/16)*(n/16) uint32, nollat. activity_enabled=0 -> early-out
	# pois (kaikki tilet aktiivisia), mutta binding pitaa silti olla olemassa.
	var tiles_x := (n + 15) >> 4
	var tile_count := tiles_x * tiles_x
	var act_zeros := PackedByteArray()
	act_zeros.resize(tile_count * 4)
	act_zeros.fill(0)
	activity_buffer = rd.storage_buffer_create(act_zeros.size(), act_zeros)

	var u_grid := RDUniform.new()
	u_grid.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_grid.binding = 0
	u_grid.add_id(grid_buffer)
	var u_act := RDUniform.new()
	u_act.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u_act.binding = 1
	u_act.add_id(activity_buffer)
	uniform_set = rd.uniform_set_create([u_grid, u_act], shader_rid, 0)
	pipeline = rd.compute_pipeline_create(shader_rid)

	gpu_ready = true
	_need_upload = false  # grid_buffer luotiin juuri CPU-gridista
	print("DiscWorld: GPU compute valmis (simulation_disc.glsl)")


func _setup_camera() -> void:
	# Keskita planeettaan ja zoomaa niin etta koko kiekko mahtuu ruutuun.
	camera.position = Vector2(float(n) * 0.5, float(n) * 0.5)
	var vp := get_viewport_rect().size
	var fit := minf(vp.x, vp.y) / (float(Geom.R_PLANET) * 2.2)
	fit = clampf(fit, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(fit, fit)
	camera.make_current()


# ============================================================
# Frame-silmukka
# ============================================================

func _process(delta: float) -> void:
	if _cli_frames >= 0:
		return  # cmdline-savuajo hoidettu _ready():ssa

	# Simulaatioaskel.
	if gpu_ready:
		_simulate_gpu()
	else:
		cpu_ca.step(grid, n, frame)
	frame += 1

	if headless:
		return  # ei renderointia/inputtia

	_handle_camera(delta)
	_handle_paint()
	_refresh_render()
	_update_hud(delta)


func _refresh_render() -> void:
	# Rakenna materiaalitekstuuri viimeisimmasta tilasta. GPU-polulla lahde on
	# readback-tavut, CPU-polulla grid:n tavut — molemmat samaa (seed<<8)|mat -muotoa.
	var bytes := _gpu_bytes if gpu_ready else grid.to_byte_array()
	if bytes.size() == n * n * 4:
		mat_texture.update(_build_mat_image(bytes))
	shader_mat.set_shader_parameter("frame", frame)


# Rakenna RGBA8-kuva 4N-tavuisesta (seed<<8)|mat -puskurista. R-kanava = materiaalitavu.
func _build_mat_image(bytes: PackedByteArray) -> Image:
	return Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, bytes)


# ============================================================
# GPU-simulaatio (yksi submit+sync per frame)
# ============================================================

func _simulate_gpu() -> void:
	# Lataa CPU:n muutokset (maalaus) GPU:lle ennen simulaatiota.
	if paint_pending or _need_upload:
		var up := grid.to_byte_array()
		rd.buffer_update(grid_buffer, 0, up.size(), up)
		paint_pending = false
		_need_upload = false

	sim_frame += 1
	var groups := (n + 15) >> 4

	var push := PackedByteArray()
	push.resize(48)
	push.encode_u32(0, n)     # width
	push.encode_u32(4, n)     # height

	var cl := rd.compute_list_begin()
	for pass_i in GPU_PASSES:
		if pass_i > 0:
			rd.compute_list_add_barrier(cl)
		push.encode_u32(8, frame * GPU_PASSES + pass_i)  # frame (per-solu-RNG)
		push.encode_u32(12, pass_i)                       # pass_id (nelivaihe % 4)
		push.encode_u32(16, 0)                            # pad0
		push.encode_u32(20, 0)                            # grav_gun_x
		push.encode_u32(24, 0)                            # grav_gun_y
		push.encode_u32(28, 0)                            # grav_gun_mode (pois)
		push.encode_u32(32, 0)                            # grav_gun_radius
		push.encode_u32(36, sim_frame)                    # sim_frame
		push.encode_u32(40, 0)                            # activity_enabled=0 (kaikki tilet aktiivisia)
		push.encode_u32(44, 0)                            # pad3
		rd.compute_list_bind_compute_pipeline(cl, pipeline)
		rd.compute_list_bind_uniform_set(cl, uniform_set, 0)
		rd.compute_list_set_push_constant(cl, push, push.size())
		rd.compute_list_dispatch(cl, groups, groups, 1)
	rd.compute_list_end()

	rd.submit()
	rd.sync()

	# Readback renderointia varten. CPU-grid merkitaan vanhentuneeksi — synkronoidaan
	# vasta jos/ kun maalataan (harvoin), ei joka frame.
	_gpu_bytes = rd.buffer_get_data(grid_buffer)
	_gpu_grid_stale = true


# Synkronoi CPU-grid uusimmasta GPU-readbackista (kutsutaan ennen maalausta GPU-tilassa).
func _sync_cpu_grid_from_gpu() -> void:
	if not _gpu_grid_stale or _gpu_bytes.size() != n * n * 4:
		return
	for i in n * n:
		grid[i] = _gpu_bytes.decode_u32(i * 4)
	_gpu_grid_stale = false


# ============================================================
# Input: kamera + maalaus
# ============================================================

func _handle_camera(delta: float) -> void:
	var mv := Vector2.ZERO
	if Input.is_key_pressed(KEY_W): mv.y -= 1.0
	if Input.is_key_pressed(KEY_S): mv.y += 1.0
	if Input.is_key_pressed(KEY_A): mv.x -= 1.0
	if Input.is_key_pressed(KEY_D): mv.x += 1.0
	if mv != Vector2.ZERO:
		# Ruutunopeus jaetaan zoomilla -> tasainen maailmanopeus zoom-tasosta riippumatta.
		camera.position += mv.normalized() * PAN_SPEED * delta / camera.zoom.x


func _handle_paint() -> void:
	var left := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var right := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	if not (left or right):
		return
	var g := _mouse_grid()
	if g.x < 0:
		return
	var mat := Geom.MAT_EMPTY if right else current_material
	_paint(g.x, g.y, mat)


func _mouse_grid() -> Vector2i:
	var w := get_global_mouse_position()
	var gx := int(floor(w.x))
	var gy := int(floor(w.y))
	if gx < 0 or gx >= n or gy < 0 or gy >= n:
		return Vector2i(-1, -1)
	return Vector2i(gx, gy)


func _paint(cx: int, cy: int, mat: int) -> void:
	if gpu_ready:
		_sync_cpu_grid_from_gpu()  # varmista tuore CPU-grid ennen kirjoitusta
	var r := brush_size
	var seed_hi := (grid[cy * n + cx] & 0xFFFFFF00)  # sailyta kohdesolun seed-tavu
	for dy in range(-r, r + 1):
		var py := cy + dy
		if py < 0 or py >= n:
			continue
		for dx in range(-r, r + 1):
			if dx * dx + dy * dy > r * r:
				continue
			var px := cx + dx
			if px < 0 or px >= n:
				continue
			var idx := py * n + px
			# Sailyta solun oma seed, vaihda vain materiaalitavu.
			grid[idx] = (grid[idx] & 0xFFFFFF00) | (mat & 0xFF)
	paint_pending = true


func _input(event: InputEvent) -> void:
	if headless or _cli_frames >= 0:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var kc := (event as InputEventKey).keycode
		if PAINT_KEYS.has(kc):
			current_material = PAINT_KEYS[kc]
		elif kc == KEY_E:
			current_material = Geom.MAT_EMPTY
		elif kc == KEY_PLUS or kc == KEY_EQUAL or kc == KEY_KP_ADD:
			brush_size = mini(brush_size + 1, 40)
		elif kc == KEY_MINUS or kc == KEY_KP_SUBTRACT:
			brush_size = maxi(brush_size - 1, 1)
		elif kc == KEY_F12:
			_save_screenshot()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mid_drag = mb.pressed
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, ZOOM_STEP)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 1.0 / ZOOM_STEP)
	elif event is InputEventMouseMotion and _mid_drag:
		# Keskihiiren raahaus: siirra kameraa vastakkaiseen suuntaan (maailma seuraa kursoria).
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom


# Zoomaa kursoria kohti: pida kursorin alla oleva maailmapiste paikallaan.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var vp := get_viewport_rect().size
	var before := camera.position + (screen_pos - vp * 0.5) / camera.zoom
	var z := clampf(camera.zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(z, z)
	var after := camera.position + (screen_pos - vp * 0.5) / camera.zoom
	camera.position += before - after


func _update_hud(delta: float) -> void:
	_fps_accum += delta
	_fps_frames += 1
	if _fps_accum >= 0.5:
		_fps = float(_fps_frames) / _fps_accum
		_fps_accum = 0.0
		_fps_frames = 0
	if info_label != null:
		info_label.text = "Kiekko  n=%d  %s\nFPS %.0f  frame %d\nmateriaali: %s  pensseli %d\n%s" % [
			n, ("GPU" if gpu_ready else "CPU-CA"), _fps, frame,
			_mat_name(current_material), brush_size,
			"WASD/keskihiiri: panoroi  rulla: zoom  1-6/Q/R: materiaali  E: pyyhi  +/-: pensseli  F12: kuva",
		]


func _save_screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	var path := "res://tests/output/disc_screenshot.png"
	_ensure_dir(path)
	img.save_png(path)
	print("DiscWorld: kuvakaappaus -> ", path)


# ============================================================
# Cmdline-savuajo + CPU-debug-renderi
# ============================================================

func _parse_cmdline() -> void:
	# Godot valittaa app-argumentit "--":n jalkeen get_cmdline_user_args():iin; skannataan
	# molemmat, jotta savuajo toimii riippumatta siita kummalle puolelle argumentit annetaan.
	var args := OS.get_cmdline_args()
	args.append_array(OS.get_cmdline_user_args())
	for arg in args:
		if arg.begins_with("--disc-frames="):
			_cli_frames = maxi(0, arg.get_slice("=", 1).to_int())
		elif arg.begins_with("--disc-out="):
			_cli_out = arg.get_slice("=", 1)
		elif arg.begins_with("--disc-seed="):
			world_seed = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--disc-n="):
			var v := arg.get_slice("=", 1).to_int()
			if v >= 16 and (v % 2) == 0:
				n = v


func _quit_ok() -> void:
	get_tree().quit(0)


func _run_cli_smoke() -> void:
	var out := _cli_out if not _cli_out.is_empty() else "res://tests/output/disc_cli.png"
	print("DiscWorld: cmdline-savuajo — steppaa %d framea (n=%d) CPU-CA:lla" % [_cli_frames, n])
	var t0 := Time.get_ticks_msec()
	for i in _cli_frames:
		cpu_ca.step(grid, n, frame)
		frame += 1
	print("DiscWorld: CPU-CA %d framea %d ms" % [_cli_frames, Time.get_ticks_msec() - t0])
	save_debug_png(out)
	get_tree().quit(0)


# CPU-renderi materiaaliväreillä -> PNG (toimii headless, ei GPU:ta/shaderia).
func save_debug_png(path: String) -> void:
	var pixels := PackedByteArray()
	pixels.resize(n * n * 4)
	# Esilaske paletti tavuina (0..255) per materiaali.
	var lut := PackedByteArray()
	lut.resize(PALETTE.size() * 3)
	for m in PALETTE.size():
		var c: Vector3 = PALETTE[m]
		lut[m * 3 + 0] = int(clampf(c.x, 0.0, 1.0) * 255.0)
		lut[m * 3 + 1] = int(clampf(c.y, 0.0, 1.0) * 255.0)
		lut[m * 3 + 2] = int(clampf(c.z, 0.0, 1.0) * 255.0)
	var pcount := PALETTE.size()
	for i in n * n:
		var mat: int = grid[i] & 0xFF
		if mat >= pcount:
			mat = 0
		var o := i * 4
		pixels[o + 0] = lut[mat * 3 + 0]
		pixels[o + 1] = lut[mat * 3 + 1]
		pixels[o + 2] = lut[mat * 3 + 2]
		pixels[o + 3] = 255
	var img := Image.create_from_data(n, n, false, Image.FORMAT_RGBA8, pixels)
	_ensure_dir(path)
	var err := img.save_png(path)
	print("DiscWorld: save_debug_png -> %s (%s)" % [path, "ok" if err == OK else "virhe %d" % err])


func _ensure_dir(path: String) -> void:
	var dir := path.get_base_dir()
	if dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))


# ============================================================
# Apurit
# ============================================================

func _mat_name(mat: int) -> String:
	match mat:
		Geom.MAT_EMPTY: return "TYHJA"
		Geom.MAT_SAND: return "HIEKKA"
		Geom.MAT_WATER: return "VESI"
		Geom.MAT_STONE: return "KIVI"
		Geom.MAT_WOOD: return "PUU"
		Geom.MAT_OIL: return "OLJY"
		Geom.MAT_DIRT: return "MULTA"
		Geom.MAT_IRON_ORE: return "RAUTAMALMI"
		Geom.MAT_GOLD_ORE: return "KULTAMALMI"
		_: return "mat %d" % mat


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		# Vapauta GPU-resurssit (kaanteinen luontijarjestys).
		if pipeline.is_valid(): rd.free_rid(pipeline)
		if uniform_set.is_valid(): rd.free_rid(uniform_set)
		if activity_buffer.is_valid(): rd.free_rid(activity_buffer)
		if grid_buffer.is_valid(): rd.free_rid(grid_buffer)
		if shader_rid.is_valid(): rd.free_rid(shader_rid)
		rd.free()
		rd = null
