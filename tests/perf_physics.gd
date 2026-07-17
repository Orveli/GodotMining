extends SceneTree

# Suorituskykybenchmark rigid body -fysiikalle (perf-vaihe P4).
# Rakentaa synteettisen maailman kivipohjalla, luo joukon dynaamisia
# kivikappaleita ilmaan (eri kulmilla + pyörintä) ja ajaa physics.step() +
# check_damage() 300 framea. Mittaa kokonaisajan ja ms/frame.
#
# Deterministinen: kiinteä seed, kiinteä kappaleiden sijoittelu.
#
# Aja headless:
#   godot --headless --path . --script res://tests/perf_physics.gd

const W := 1024
const H := 512
const TOTAL := W * H
const MAT_STONE := 3
const FLOOR_ROWS := 10        # Kivipohjan paksuus (raaka maasto, ei kappale)
const FRAMES := 300           # Mitattavien framejen määrä
const WARMUP_FRAMES := 30     # Lämmittelyframet (ei mitata)

var grid: PackedByteArray
var color_seed: PackedByteArray
var _next_id := 1


func _init() -> void:
	print("=== FYSIIKAN PERF-BENCHMARK ===")
	print("Grid: %dx%d, framet: %d (+%d lämmittely)\n" % [W, H, FRAMES, WARMUP_FRAMES])

	# Aja kaksi kuormaa: normaali (~30) ja raskas (~100 = cappia kiertäen)
	_run_benchmark(30)
	_run_benchmark(100)

	print("\n=== BENCHMARK VALMIS ===")
	quit()


func _setup_world() -> void:
	grid = PackedByteArray()
	grid.resize(TOTAL)
	grid.fill(0)
	color_seed = PackedByteArray()
	color_seed.resize(TOTAL)
	# Deterministinen väri-seed (ei satunnaisuutta ilman kiinteää seediä)
	for i in TOTAL:
		color_seed[i] = (i * 37 + 11) & 0xFF
	# Kivipohja alimmille riveille (raaka maasto → törmäyskohde)
	for y in range(H - FLOOR_ROWS, H):
		var row := y * W
		for x in W:
			grid[row + x] = MAT_STONE
	_next_id = 1


# Luo dynaaminen kivikappale suoraan (kiertää MAX_DYNAMIC_BODIES-capin,
# jotta voidaan mitata raskaampia kuormia kuin moottori normaalisti sallii).
func _spawn_body(physics: PhysicsWorld, cx: int, cy: int, rw: int, rh: int, angle: float, avel: float) -> void:
	var pixels: Array[Vector2i] = []
	for dy in rh:
		for dx in rw:
			pixels.append(Vector2i(cx + dx, cy + dy))
	var seeds := PackedByteArray()
	seeds.resize(pixels.size())
	for i in pixels.size():
		var p := pixels[i]
		seeds[i] = color_seed[p.y * W + p.x]

	var body := RigidBodyData.new()
	body.body_id = _next_id
	_next_id += 1
	body.material = MAT_STONE
	body.calculate_from_world_pixels(pixels, seeds)
	body.angle = angle
	body.angular_velocity = avel
	physics.bodies[body.body_id] = body

	# Kirjoita kappaleen (kierretyt) pikselit gridiin + body_mapiin, jotta
	# ensimmäinen erase löytää ne oikein.
	for wp in body.get_world_pixels():
		if wp.x >= 0 and wp.x < W and wp.y >= 0 and wp.y < H:
			var idx := wp.y * W + wp.x
			if grid[idx] == 0:
				grid[idx] = MAT_STONE
				physics.body_map[idx] = body.body_id


func _run_benchmark(body_count: int) -> void:
	_setup_world()
	var physics := PhysicsWorld.new()
	physics._ensure_body_map(W, H)

	# Sijoittele kappaleet harvaan ruudukkoon ilmaan (ei päällekkäisyyttä).
	# 24x12 suorakaiteet, eri alkukulmilla ja pienellä pyörinnällä.
	var cols := 10
	var col_step := 48
	var row_step := 36
	var x0 := 60
	var y0 := 30
	var placed := 0
	var r := 0
	while placed < body_count:
		for c in cols:
			if placed >= body_count:
				break
			var cx := x0 + c * col_step
			var cy := y0 + r * row_step
			# Vaihteleva alkukulma ja pyörimisnopeus (deterministinen)
			var angle := float((placed * 7) % 13) * 0.09 - 0.5
			var avel := float((placed % 5) - 2) * 0.02
			_spawn_body(physics, cx, cy, 24, 12, angle, avel)
			placed += 1
		r += 1

	# Lämmittely (ei mitata) — vakauttaa alkutilan
	for _f in WARMUP_FRAMES:
		physics.step(grid, color_seed, W, H)
		physics.check_damage(grid, color_seed, W, H)

	# Mitattu ajo
	var t_start := Time.get_ticks_usec()
	for _f in FRAMES:
		physics.step(grid, color_seed, W, H)
		physics.check_damage(grid, color_seed, W, H)
		physics.process_damage_queue(grid, color_seed, W, H)
	var t_end := Time.get_ticks_usec()

	var total_ms := float(t_end - t_start) / 1000.0
	var ms_per_frame := total_ms / float(FRAMES)
	# Laske vielä montako kappaletta on aktiivisia lopussa (herätysten jälkeen)
	var alive := physics.bodies.size()
	print("--- Kuorma: %d kappaletta ---" % body_count)
	print("  Kokonaisaika: %.2f ms  (%d framea)" % [total_ms, FRAMES])
	print("  ms/frame:     %.3f" % ms_per_frame)
	print("  Kappaleita lopussa: %d  loppuhash=%d\n" % [alive, _grid_hash()])


func _grid_hash() -> int:
	# Yksinkertainen deterministinen tarkistussumma gridille
	var acc := 1469598103934665603  # FNV-tyyppinen
	for i in TOTAL:
		if grid[i] != 0:
			acc = (acc * 1099511628211 + i * 131 + grid[i]) & 0x7FFFFFFFFFFFFFFF
	return acc
