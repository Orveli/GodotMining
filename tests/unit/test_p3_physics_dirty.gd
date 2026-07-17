extends SceneTree

# P3-korrektiustesti (headless, ei GPU:ta): varmistaa että fysiikkastepin dirty-rect
# (kappaleiden AABB:t ennen + jälkeen stepin, marginaalilla) kattaa JOKAISEN gridin
# solun jonka step oikeasti muutti. Tämä on P1:n _mark_grid_dirty_all()-korvauksen
# kriittinen korrektiusehto: jos muuttunut solu jää dirty-rectin ulkopuolelle, se ei
# lataudu GPU:lle ja CPU-peili eriytyy sim-tilasta.
#
# Peilaa pixel_world.gd:n _mark_body_dirty()-matematiikkaa (rot-AABB + roundi(pos) ± PAD).

const W := 320
const H := 180
const TOTAL := W * H
const MAT_STONE := 3
const MAT_WATER := 2
const BODY_DIRTY_PAD := 3  # sama kuin pixel_world.gd

var grid: PackedByteArray
var color_seed: PackedByteArray

var fail_count := 0


func _init() -> void:
	print("=== P3 FYSIIKAN DIRTY-RECT -KORREKTIUSTESTI ===\n")
	_test_falling_block_dry()
	_test_falling_block_into_water()
	_test_multiple_bodies()
	_test_edge_columns()
	if fail_count == 0:
		print("\n=== KAIKKI OK: dirty-rect kattaa kaikki fysiikkastepin kirjoitukset ===")
	else:
		print("\n=== TEST: FAIL — %d framea joissa muutos jäi dirty-rectin ulkopuolelle ===" % fail_count)
	quit()


func _setup_ground() -> void:
	grid = PackedByteArray()
	grid.resize(TOTAL)
	grid.fill(0)
	color_seed = PackedByteArray()
	color_seed.resize(TOTAL)
	for i in TOTAL:
		color_seed[i] = randi() % 256
	for x in W:
		for y in range(H - 3, H):
			grid[y * W + x] = MAT_STONE


func _place_rect(cx: int, cy: int, rw: int, rh: int, mat: int) -> void:
	for dy in rh:
		for dx in rw:
			var x := cx + dx
			var y := cy + dy
			if x >= 0 and x < W and y >= 0 and y < H:
				grid[y * W + x] = mat


# Irrota maapohjaa koskemattomat kappaleet dynaamisiksi (kuten leikkaus/räjähdys tekisi).
func _wake_floating(physics: PhysicsWorld) -> void:
	for bid in physics.bodies:
		var b: RigidBodyData = physics.bodies[bid]
		var touches_ground := false
		for wp in b.get_world_pixels():
			if wp.y >= H - 1:
				touches_ground = true
				break
		if not touches_ground:
			b.is_static = false
			b.wake_up()


# Kerää kaikkien ei-staattisten, ei-nukkuvien kappaleiden yhdistetty AABB (peilaa
# pixel_world._mark_body_dirty). Palauttaa [min_x, min_y, max_x, max_y] tai tyhjän.
func _collect_dirty(physics: PhysicsWorld, acc: Array) -> void:
	for bid in physics.bodies:
		var b: RigidBodyData = physics.bodies[bid]
		if b.is_static or b.is_sleeping:
			continue
		b._ensure_rot_cache()
		var px := roundi(b.position.x)
		var py := roundi(b.position.y)
		var x0 := b.rot_min_x + px - BODY_DIRTY_PAD
		var y0 := b.rot_min_y + py - BODY_DIRTY_PAD
		var x1 := b.rot_max_x + px + BODY_DIRTY_PAD
		var y1 := b.rot_max_y + py + BODY_DIRTY_PAD
		if acc.is_empty():
			acc.append_array([x0, y0, x1, y1])
		else:
			acc[0] = mini(acc[0], x0)
			acc[1] = mini(acc[1], y0)
			acc[2] = maxi(acc[2], x1)
			acc[3] = maxi(acc[3], y1)


# Aja yksi step ja tarkista dirty-rect-kattavuus. Palauttaa muuttuneiden solujen määrän.
func _step_and_verify(physics: PhysicsWorld, frame: int, label: String) -> int:
	var before := grid.duplicate()
	var acc: Array = []
	_collect_dirty(physics, acc)                 # ennen steppiä (vanha sijainti)
	physics.step(grid, color_seed, W, H)
	_collect_dirty(physics, acc)                 # jälkeen stepin (uusi sijainti + heränneet)

	# Etsi muuttuneet solut ja tarkista että ne ovat dirty-rectin sisällä.
	var changed := 0
	var outside := 0
	var first_bad := Vector2i(-1, -1)
	for i in TOTAL:
		if grid[i] == before[i]:
			continue
		changed += 1
		var cx := i % W
		var cy := i / W
		if acc.is_empty() or cx < acc[0] or cx > acc[2] or cy < acc[1] or cy > acc[3]:
			outside += 1
			if first_bad.x < 0:
				first_bad = Vector2i(cx, cy)
	if outside > 0:
		fail_count += 1
		var rect_s := "tyhjä" if acc.is_empty() else "[%d,%d..%d,%d]" % [acc[0], acc[1], acc[2], acc[3]]
		print("  FAIL %s F%d: %d/%d muutosta dirty-rectin ULKOPUOLELLA (esim %s), rect=%s"
			% [label, frame, outside, changed, str(first_bad), rect_s])
	return changed


func _run_sim(physics: PhysicsWorld, frames: int, label: String) -> void:
	var total_changed := 0
	for f in frames:
		total_changed += _step_and_verify(physics, f, label)
	print("  %s: %d framea, %d solumuutosta yhteensä, %d ulkopuolista"
		% [label, frames, total_changed, fail_count])


# TESTI 1: kuiva pudotus (erase + write, ei nestettä)
func _test_falling_block_dry() -> void:
	print("--- Testi 1: Kuiva putoava kappale ---")
	_setup_ground()
	_place_rect(156, 40, 8, 8, MAT_STONE)
	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)
	_wake_floating(physics)
	_run_sim(physics, 200, "kuiva")


# TESTI 2: pudotus veteen — nesteensyrjäytys kirjoittaa kappaleen ULKOPUOLELLE (±1 solu).
# Tämä on marginaalin kriittinen testi.
func _test_falling_block_into_water() -> void:
	print("\n--- Testi 2: Kappale putoaa veteen (nesteensyrjäytys) ---")
	_setup_ground()
	# Vesiallas pohjalle
	_place_rect(120, H - 30, 80, 27, MAT_WATER)
	# Kivi veden yläpuolelle
	_place_rect(150, 60, 10, 10, MAT_STONE)
	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)
	_wake_floating(physics)
	_run_sim(physics, 200, "vesi")


# TESTI 3: useita kappaleita eri kohdissa (törmäys + herätys)
func _test_multiple_bodies() -> void:
	print("\n--- Testi 3: Useita kappaleita ---")
	_setup_ground()
	_place_rect(80, 50, 8, 8, MAT_STONE)
	_place_rect(200, 70, 10, 6, MAT_STONE)
	_place_rect(150, 90, 6, 12, MAT_STONE)
	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)
	_wake_floating(physics)
	_run_sim(physics, 200, "monta")


# TESTI 4: kappaleet reunasarakkeissa (x≈0 ja x≈319) — clamp-käytös rajoilla.
func _test_edge_columns() -> void:
	print("\n--- Testi 4: Reunasarakkeet (x=0, x=319) ---")
	_setup_ground()
	_place_rect(0, 55, 6, 6, MAT_STONE)         # kiinni vasempaan reunaan
	_place_rect(W - 6, 65, 6, 6, MAT_STONE)     # kiinni oikeaan reunaan
	var physics := PhysicsWorld.new()
	physics.scan_stone_bodies(grid, color_seed, W, H)
	_wake_floating(physics)
	_run_sim(physics, 200, "reuna")
