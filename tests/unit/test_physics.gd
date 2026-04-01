extends SceneTree

# Automaattinen fysiikkatesti — ajaa simulaation ilman GPU:ta ja raportoi tulokset

const W := 320
const H := 180
const TOTAL := W * H
const MAT_STONE := 3

var grid: PackedByteArray
var color_seed: PackedByteArray


func _init() -> void:
	print("=== FYSIIKKATESTI ===\n")
	_test_falling_block()
	_test_bodymap_debug()
	_test_tipping()
	print("\n=== KAIKKI TESTIT VALMIS ===")
	quit()


func _setup_world() -> void:
	grid = PackedByteArray()
	grid.resize(TOTAL)
	grid.fill(0)
	color_seed = PackedByteArray()
	color_seed.resize(TOTAL)
	for i in TOTAL:
		color_seed[i] = randi() % 256
	# Maapohja: 3 pikseliä paksu
	for x in W:
		for y in range(H - 3, H):
			grid[y * W + x] = MAT_STONE


func _place_stone_rect(cx: int, cy: int, rw: int, rh: int) -> void:
	for dy in rh:
		for dx in rw:
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < W and y >= 0 and y < H:
				grid[y * W + x] = MAT_STONE


# TESTI 1: Putoaako yksittäinen kappale maahan?
func _test_falling_block() -> void:
	print("--- Testi 1: Putoava kappale ---")
	_setup_world()
	# 8x8 kivi korkealla (y=50)
	_place_stone_rect(156, 50, 8, 8)

	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)

	# Etsi ei-staattinen kappale
	var block_id := -1
	for bid in physics.bodies:
		var b: RigidBodyData = physics.bodies[bid]
		if not b.is_static:
			block_id = bid
			break

	if block_id < 0:
		print("  FAIL: Ei löytynyt putoavaa kappaletta!")
		return

	var start_y: float = physics.bodies[block_id].position.y
	print("  Alkupos: y=%.1f" % start_y)

	# Aja 200 framea
	for frame in 200:
		physics.step(grid, color_seed, W, H)

	if not physics.bodies.has(block_id):
		print("  FAIL: Kappale katosi!")
		return

	var body: RigidBodyData = physics.bodies[block_id]
	var end_y: float = body.position.y
	print("  Loppupos: y=%.1f  vel=(%.2f, %.2f)  sleeping=%s" % [end_y, body.velocity.x, body.velocity.y, body.is_sleeping])

	# Maapohja alkaa y=177. 8px korkea kappale: alin pikseli ~pos.y+4, ylä ~pos.y-4
	if end_y > start_y + 10.0 and end_y > 160.0:
		print("  OK: Kappale putosi (%.0f → %.0f)" % [start_y, end_y])
	else:
		print("  FAIL: Kappale ei pudonnut tarpeeksi (%.0f → %.0f)" % [start_y, end_y])


# TESTI 1B: Debug — katsotaan mitä body_map sanoo
func _test_bodymap_debug() -> void:
	print("\n--- Testi 1B: Body_map debug ---")
	_setup_world()
	# Kappale 1: 6x6 y=160 (lähellä maata)
	_place_stone_rect(157, 160, 6, 6)

	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)

	var block_id := -1
	for bid in physics.bodies:
		var b: RigidBodyData = physics.bodies[bid]
		if not b.is_static:
			block_id = bid
			break

	if block_id < 0:
		print("  Ei kappaletta!")
		return

	# Aja 100 framea — kappale laskeutuu
	for frame in 100:
		physics.step(grid, color_seed, W, H)

	var body: RigidBodyData = physics.bodies[block_id]
	print("  Kappale: pos=(%.1f, %.1f) sleeping=%s" % [body.position.x, body.position.y, body.is_sleeping])

	# Tarkista body_map kappaleen kohdalla
	var wp := body.get_world_pixels()
	var in_map := 0
	var in_grid := 0
	for p in wp:
		if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H:
			var idx := p.y * W + p.x
			if physics.body_map[idx] == block_id:
				in_map += 1
			if grid[idx] == MAT_STONE:
				in_grid += 1
	print("  Pikselit gridissä: %d/%d  body_mapissä: %d/%d" % [in_grid, wp.size(), in_map, wp.size()])

	# Lisää toinen kappale yläpuolelle
	_place_stone_rect(157, 100, 6, 6)
	var upper_pixels: Array[Vector2i] = []
	for dy in 6:
		for dx in 6:
			upper_pixels.append(Vector2i(157 + dx, 100 + dy))
	var seeds := PackedByteArray()
	seeds.resize(upper_pixels.size())
	for i in seeds.size():
		seeds[i] = color_seed[upper_pixels[i].y * W + upper_pixels[i].x]
	physics._ensure_body_map(W, H)
	var upper := physics.create_body(upper_pixels, seeds, MAT_STONE)
	if upper:
		for p in upper_pixels:
			physics.body_map[p.y * W + p.x] = upper.body_id

	print("  Ylempi luotu: id=%d pos=(%.1f, %.1f)" % [upper.body_id, upper.position.x, upper.position.y])

	# Aja 200 framea — seuraa ylempää
	for frame in 200:
		physics.step(grid, color_seed, W, H)
		if physics.bodies.has(upper.body_id):
			var u: RigidBodyData = physics.bodies[upper.body_id]
			if frame < 25 or frame % 30 == 0:
				# Tarkista onko alempi vielä gridissä
				var lower_in_grid := 0
				if physics.bodies.has(block_id):
					var lwp: Array[Vector2i] = physics.bodies[block_id].get_world_pixels()
					for p in lwp:
						if p.x >= 0 and p.x < W and p.y >= 0 and p.y < H:
							if grid[p.y * W + p.x] == MAT_STONE:
								lower_in_grid += 1
				print("  F%d: upper y=%.1f vy=%.2f sleep=%s | lower_grid=%d" % [frame, u.position.y, u.velocity.y, u.is_sleeping, lower_in_grid])


# TESTI 2: Pinoutuvatko kappaleet (ei mene läpi)?
func _test_stacking() -> void:
	print("\n--- Testi 2: Kappaleiden pinoaminen ---")
	_setup_world()
	# Alempi kappale: 10x5 lähellä maata (y=165)
	_place_stone_rect(155, 165, 10, 5)

	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)

	# Etsi alempi kappale
	var lower_id := -1
	for bid in physics.bodies:
		var b: RigidBodyData = physics.bodies[bid]
		if not b.is_static and b.position.y > 160:
			lower_id = bid
			break

	# Aja 60 framea — alempi laskeutuu maahan
	for frame in 60:
		physics.step(grid, color_seed, W, H)

	if lower_id >= 0 and physics.bodies.has(lower_id):
		var lower: RigidBodyData = physics.bodies[lower_id]
		print("  Alempi kappale: y=%.1f sleeping=%s" % [lower.position.y, lower.is_sleeping])

	# Lisää ylempi kappale: 8x4 korkealla (y=100)
	_place_stone_rect(156, 100, 8, 4)
	# Luo uusi kappale käsin (simuloi piirtovedosta)
	var upper_pixels: Array[Vector2i] = []
	for dy in 4:
		for dx in 8:
			upper_pixels.append(Vector2i(156 + dx, 100 + dy))
	var seeds := PackedByteArray()
	seeds.resize(upper_pixels.size())
	for i in seeds.size():
		var p: Vector2i = upper_pixels[i]
		seeds[i] = color_seed[p.y * W + p.x]
	physics._ensure_body_map(W, H)
	var upper_body := physics.create_body(upper_pixels, seeds, MAT_STONE)
	if upper_body:
		for p in upper_pixels:
			physics.body_map[p.y * W + p.x] = upper_body.body_id

	var upper_id := upper_body.body_id if upper_body else -1
	print("  Ylempi kappale luotu: id=%d y=%.1f" % [upper_id, upper_body.position.y if upper_body else -1])

	# Aja 300 framea
	for frame in 300:
		physics.step(grid, color_seed, W, H)

	if upper_id >= 0 and physics.bodies.has(upper_id):
		var upper: RigidBodyData = physics.bodies[upper_id]
		print("  Ylempi loppupos: y=%.1f sleeping=%s" % [upper.position.y, upper.is_sleeping])
		# Ylempi pitäisi olla YLEMPÄNÄ kuin maapohja (y < 170)
		if upper.position.y < 170.0 and upper.position.y > 130.0:
			print("  OK: Ylempi kappale pysähtyi oikealle korkeudelle")
		elif upper.position.y >= 170.0:
			print("  FAIL: Ylempi meni alemman läpi!")
		else:
			print("  WARN: Ylempi jäi korkealle (y=%.1f)" % upper.position.y)
	else:
		print("  FAIL: Ylempi kappale katosi!")

	if lower_id >= 0 and physics.bodies.has(lower_id):
		var lower: RigidBodyData = physics.bodies[lower_id]
		print("  Alempi loppupos: y=%.1f" % lower.position.y)


# TESTI 3: Kallistuuko vaakapalkki kapealla tuella?
func _test_tipping() -> void:
	print("\n--- Testi 3: Kallistuminen ---")
	_setup_world()

	# Kapea tukipylväs (2px leveä, 10px korkea) keskellä
	# Tuki koskettaa maata → staattinen
	_place_stone_rect(159, 167, 2, 10)

	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)

	# Varmista että tuki on staattinen
	for bid in physics.bodies:
		var b: RigidBodyData = physics.bodies[bid]
		if not b.is_static:
			print("  WARN: tuki ei ole staattinen!")

	# Lisää pitkä vaakapalkki EPÄKESKEISESTI tuen päälle
	# Palkki: 20px leveä, 3px korkea, painopiste oikealla
	# Tuki on x=159-160, palkki x=150-169 → painopiste x=159.5
	# Mutta sijoitetaan niin, että palkki on enemmän oikealla:
	# palkki x=155-174 → painopiste ~x=164.5, tuki x=159-160
	# → painopiste on oikealla tuesta → kallistuu oikealle
	var beam_pixels: Array[Vector2i] = []
	for dy in 3:
		for dx in 20:
			beam_pixels.append(Vector2i(155 + dx, 164 + dy))

	var seeds := PackedByteArray()
	seeds.resize(beam_pixels.size())
	for i in seeds.size():
		var p: Vector2i = beam_pixels[i]
		seeds[i] = color_seed[p.y * W + p.x]
		grid[p.y * W + p.x] = MAT_STONE

	physics._ensure_body_map(W, H)
	var beam := physics.create_body(beam_pixels, seeds, MAT_STONE)
	if beam:
		for p in beam_pixels:
			physics.body_map[p.y * W + p.x] = beam.body_id

	var beam_id := beam.body_id if beam else -1
	print("  Palkki: pos=(%.1f, %.1f) mass=%.0f" % [beam.position.x, beam.position.y, beam.mass])
	print("  Tuki: x=159-160, palkki: x=155-174")
	print("  → Painopiste oikealla tuesta → pitäisi kallistua oikealle")

	# Aja 200 framea
	for frame in 200:
		physics.step(grid, color_seed, W, H)
		if frame < 20 or frame % 30 == 29:
			if physics.bodies.has(beam_id):
				var b: RigidBodyData = physics.bodies[beam_id]
				print("  F%d: pos=(%.1f, %.1f) angle=%.4f avel=%.5f" % [
					frame, b.position.x, b.position.y, b.angle, b.angular_velocity
				])

	if beam_id >= 0 and physics.bodies.has(beam_id):
		var b: RigidBodyData = physics.bodies[beam_id]
		if absf(b.angle) > 0.05:
			print("  OK: Palkki kallistui! (angle=%.3f)" % b.angle)
		else:
			print("  FAIL: Palkki ei kallistunut (angle=%.4f)" % b.angle)
	else:
		print("  INFO: Palkki hajosi/katosi")
