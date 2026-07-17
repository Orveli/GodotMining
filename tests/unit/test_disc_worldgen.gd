extends SceneTree

# Yksikkotestit DiscWorldGenille (scripts/disc_world_gen.gd, SPEC Vaihe 2A).
# Todistaa kiekkomaailman kerrosrakenteen: avaruus tyhja, ydin bedrockia, pinta
# oikealla sateella (DIRT joka ilmansuunnasta), malmiosuudet jarkevat (0.5-10 %
# kivisoluista per malmi) ja determinismi (sama seed -> sama grid). Mittaa myos
# taydella 1408-gridilla generoinnin keston.
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_disc_worldgen.gd

const Geom = preload("res://scripts/disc_geom.gd")

# Uusi luokka ladataan eksplisiittisella polulla (ei luoteta class-cacheen).
var _DWG = load("res://scripts/disc_world_gen.gd")

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== DISCWORLDGEN-TESTIT ===\n")
	_test_determinism()
	# Taysikokoinen generointi kerran: ajastus + rakennetestit samalla gridilla.
	var t0 := Time.get_ticks_msec()
	var grid: PackedInt32Array = _DWG.generate(20260718, Geom.GRID_N)
	var gen_ms := Time.get_ticks_msec() - t0
	print("Taysikokoinen generointi (n=%d): %d ms\n" % [Geom.GRID_N, gen_ms])

	_test_space_empty(grid, Geom.GRID_N)
	_test_core_bedrock(grid, Geom.GRID_N)
	_test_surface_radius(grid, Geom.GRID_N)
	_test_ore_ratios(grid, Geom.GRID_N)

	print("\n=== YHTEENVETO ===")
	print("RESULT: %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		print("TEST: FAILED")
	quit(1 if _fail > 0 else 0)


# --- Apurit -----------------------------------------------------------------

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: ", name)
	else:
		_fail += 1
		print("  FAILED: ", name)


func _mat_at(grid: PackedInt32Array, x: int, y: int, n: int) -> int:
	return grid[y * n + x] & 0xFF


# Solu tietylla sateella/kulmalla (keskipiste (n-1)/2, sektorisymmetria).
func _cell_at_polar(cx: float, angle: float, r: float, n: int) -> Vector2i:
	var x := int(round(cx + cos(angle) * r))
	var y := int(round(cx + sin(angle) * r))
	return Vector2i(clampi(x, 0, n - 1), clampi(y, 0, n - 1))


# --- Testit -----------------------------------------------------------------

func _test_determinism() -> void:
	print("determinismi (n=352):")
	var a: PackedInt32Array = _DWG.generate(12345, 352)
	var b: PackedInt32Array = _DWG.generate(12345, 352)
	var c: PackedInt32Array = _DWG.generate(99999, 352)
	_check(a.size() == 352 * 352, "grid-koko = n*n")
	_check(a == b, "sama seed -> identtinen grid")
	_check(a != c, "eri seed -> eri grid")


func _test_space_empty(grid: PackedInt32Array, n: int) -> void:
	print("avaruus tyhja:")
	# Kulmat ovat selvasti r_planet:n ulkopuolella -> EMPTY.
	_check(_mat_at(grid, 0, 0, n) == Geom.MAT_EMPTY, "vasen ylakulma EMPTY")
	_check(_mat_at(grid, n - 1, 0, n) == Geom.MAT_EMPTY, "oikea ylakulma EMPTY")
	_check(_mat_at(grid, 0, n - 1, n) == Geom.MAT_EMPTY, "vasen alakulma EMPTY")
	_check(_mat_at(grid, n - 1, n - 1, n) == Geom.MAT_EMPTY, "oikea alakulma EMPTY")

	# Rengas juuri planeetan ulkopuolella (r_planet + 30 px) on tyhja joka suunnasta.
	var cx := float(n - 1) * 0.5
	var r_out := float(Geom.R_PLANET) + 30.0
	var all_empty := true
	for i in 16:
		var ang := float(i) / 16.0 * TAU
		var c := _cell_at_polar(cx, ang, r_out, n)
		if grid[c.y * n + c.x] & 0xFF != Geom.MAT_EMPTY:
			all_empty = false
	_check(all_empty, "rengas r_planet+30 tyhja joka suunnasta")


func _test_core_bedrock(grid: PackedInt32Array, n: int) -> void:
	print("ydin bedrockia:")
	# Kaikki solut selvasti r_core:n sisalla (r < r_core*0.7) ovat BEDROCKia.
	var cx := float(n - 1) * 0.5
	var r_in := float(Geom.R_CORE) * 0.7
	var all_bedrock := true
	for i in 24:
		var ang := float(i) / 24.0 * TAU
		var c := _cell_at_polar(cx, ang, r_in, n)
		if grid[c.y * n + c.x] & 0xFF != Geom.MAT_BEDROCK:
			all_bedrock = false
	# Keskisolu itse.
	var mid := int(cx)
	_check(_mat_at(grid, mid, mid, n) == Geom.MAT_BEDROCK, "keskisolu BEDROCK")
	_check(all_bedrock, "sisarengas r_core*0.7 BEDROCK joka suunnasta")


func _test_surface_radius(grid: PackedInt32Array, n: int) -> void:
	print("pinta oikealla sateella (DIRT):")
	# Joka ilmansuunnasta pitaa loytya DIRTia pinnan tuntumasta (r in
	# (r_planet - dirt, r_planet)). Skannataan radiaalinen ikkuna ja etsitaan DIRT.
	var cx := float(n - 1) * 0.5
	var dirt_t := 24.0  # DIRT_THICKNESS_FULL taydella gridilla
	var r_planet := float(Geom.R_PLANET)
	var dirs_ok := 0
	var dirs_total := 16
	for i in dirs_total:
		var ang := float(i) / float(dirs_total) * TAU
		var found_dirt := false
		# Skannaa pinnasta hieman mullan alle asti.
		var r := r_planet - 1.0
		while r > r_planet - dirt_t - 2.0:
			var c := _cell_at_polar(cx, ang, r, n)
			if grid[c.y * n + c.x] & 0xFF == Geom.MAT_DIRT:
				found_dirt = true
				break
			r -= 1.0
		if found_dirt:
			dirs_ok += 1
	_check(dirs_ok == dirs_total, "DIRT loytyy pinnalta kaikista %d suunnasta (%d/%d)" %
		[dirs_total, dirs_ok, dirs_total])


func _test_ore_ratios(grid: PackedInt32Array, n: int) -> void:
	print("malmiosuudet (0.5-10 % kivisoluista):")
	var counts := {}
	for i in grid.size():
		var m := grid[i] & 0xFF
		counts[m] = counts.get(m, 0) + 1

	var ores := [Geom.MAT_IRON_ORE, Geom.MAT_COAL, Geom.MAT_GOLD_ORE,
		Geom.MAT_COPPER, Geom.MAT_RARE_EARTH]
	var ore_names := {
		Geom.MAT_IRON_ORE: "IRON_ORE", Geom.MAT_COAL: "COAL",
		Geom.MAT_GOLD_ORE: "GOLD_ORE", Geom.MAT_COPPER: "COPPER",
		Geom.MAT_RARE_EARTH: "RARE_EARTH",
	}

	# Kivisolut = STONE + kaikki malmit (malmit korvasivat STONEa).
	var stone_total: int = int(counts.get(Geom.MAT_STONE, 0))
	for o in ores:
		stone_total += int(counts.get(o, 0))
	_check(stone_total > 0, "kivisoluja loytyy")

	print("  (kivisoluja yhteensa: %d)" % stone_total)
	for o in ores:
		var cnt: int = int(counts.get(o, 0))
		var frac := float(cnt) / float(maxi(stone_total, 1))
		var ok := frac >= 0.005 and frac <= 0.10
		_check(ok, "%s osuus %.2f%% in [0.5, 10] %% (n=%d)" %
			[ore_names[o], frac * 100.0, cnt])
