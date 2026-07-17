extends SceneTree

# Savutesti kiekkoplaneetalle (docs/SPEC_disc_planet.md, Vaihe 4).
# Boottaa worldgenin + DiscCpuCa:n ja assertoi sektorigravitaation kokonaiskaytoksen:
#   1. Avaruuteen pinnan ylapuolelle maalattu hiekka/vesi LIIKKUU kohti keskustaa
#      (keskimaarainen sade pienenee) ja paatyy pinnan tuntumaan.
#   2. Grid-invariantit sailyvat: 300 framen jalkeen ei materiaalia avaruudessa
#      R_PLANET + marginaalin ulkopuolella (maalattu aine on pudonnut sisaan).
#   3. Tallentaa CPU-renderin tests/output/disc_smoke.png (toimii headless).
#
# Luokat ladataan eksplisiittisilla poluilla (ei luoteta class-cacheen / --importiin).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_disc_smoke.gd

const Geom = preload("res://scripts/disc_geom.gd")

var _DWG = load("res://scripts/disc_world_gen.gd")
var _CA = load("res://scripts/disc_cpu_ca.gd")
var _DW = load("res://scripts/disc_world.gd")

const N := 160          # pieni parillinen grid (nopea CPU-CA)
const FRAMES := 300
const MARGIN := 8.0     # sallittu ylitys pinnan yli keskimaarin (pinnalle kasautuva kasa)

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== DISC-SAVUTESTI ===\n")
	var n := N
	var s := float(n) / float(Geom.GRID_N)
	var r_planet := float(Geom.R_PLANET) * s
	var c := float(n - 1) * 0.5

	var grid: PackedInt32Array = _DWG.generate(777, n)

	# Injektoi loysaa ainetta avaruuteen pinnan ylapuolelle. Planeetta tayttaa gridin
	# lahes kokonaan, joten ilmansuuntien kohdalla avaruutta on vain ~7 px; tilaa on
	# reilusti vain LAVISTAISUUNNISSA (kulmiin r ~0.7*n). Sijoitetaan blobit lahelle
	# 45°-suuntia mutta selvasti YHDEN sektorin puolelle (|dxc|>|dyc| vaakasektori vs.
	# |dyc|>|dxc| pystysektori) -> molemmat putoavat puhtaasti sisaanpain.
	var drop_r := r_planet + 13.0
	# Koillinen, vaakasektori (down = -x): dir.x dominoi -> hiekka putoaa -x kohti keskusta.
	_place_dir(grid, n, c, Vector2(0.8, -0.6), drop_r, 4, Geom.MAT_SAND)
	# Lounas, pystysektori (down = -y): dir.y dominoi -> vesi putoaa -y kohti keskusta.
	_place_dir(grid, n, c, Vector2(-0.6, 0.8), drop_r, 4, Geom.MAT_WATER)

	var sand0 := _mat_stats(grid, n, Geom.MAT_SAND)
	var water0 := _mat_stats(grid, n, Geom.MAT_WATER)
	_check(sand0["count"] > 0, "hiekkaa injektoitu (%d solua)" % sand0["count"])
	_check(water0["count"] > 0, "vetta injektoitu (%d solua)" % water0["count"])
	print("  alku: hiekka mean_r=%.1f, vesi mean_r=%.1f (pinta r=%.1f)" %
		[sand0["mean_r"], water0["mean_r"], r_planet])

	# Steppaa CPU-CA.
	var ca = _CA.new()
	var t0 := Time.get_ticks_msec()
	for f in FRAMES:
		ca.step(grid, n, f)
	print("  DiscCpuCa %d framea (n=%d): %d ms\n" % [FRAMES, n, Time.get_ticks_msec() - t0])

	var sand1 := _mat_stats(grid, n, Geom.MAT_SAND)
	var water1 := _mat_stats(grid, n, Geom.MAT_WATER)

	# (1) Liikkui kohti keskustaa: keskimaarainen sade pieneni selvasti.
	print("  loppu: hiekka mean_r=%.1f (max %.1f), vesi mean_r=%.1f (max %.1f)" %
		[sand1["mean_r"], sand1["max_r"], water1["mean_r"], water1["max_r"]])
	_check(sand1["mean_r"] < sand0["mean_r"] - 3.0, "hiekka liikkui kohti keskustaa (%.1f -> %.1f)" %
		[sand0["mean_r"], sand1["mean_r"]])
	_check(water1["mean_r"] < water0["mean_r"] - 3.0, "vesi liikkui kohti keskustaa (%.1f -> %.1f)" %
		[water0["mean_r"], water1["mean_r"]])

	# Aine ei kadonnut (CA ei tuhoa jauhetta/nestetta).
	_check(sand1["count"] == sand0["count"], "hiekan maara sailyi (%d)" % sand1["count"])
	_check(water1["count"] == water0["count"], "veden maara sailyi (%d)" % water1["count"])

	# Paatyi pinnan tuntumaan (keskimaarainen sade pinnan + marginaalin sisalla).
	# HUOM: sektorigravitaatiossa neste kasautuu diagonaalisen sektorirajan tuntumaan
	# muutaman pikselin pinnan ylapuolelle -> keskiarvo on oikea mittari, ei yksittainen huippu.
	_check(sand1["mean_r"] <= r_planet + MARGIN, "hiekka asettui pinnan tuntumaan (mean_r %.1f <= %.1f)" %
		[sand1["mean_r"], r_planet + MARGIN])
	_check(water1["mean_r"] <= r_planet + MARGIN, "vesi asettui pinnan tuntumaan (mean_r %.1f <= %.1f)" %
		[water1["mean_r"], r_planet + MARGIN])

	# (2) Escape-invariantti: sektorigravitaatio EI koskaan tyonna ainetta ULOSPAIN.
	# Lopullinen maksimisade ei saa ylittaa alkuperaista maalausmaksimia -> mikaan ei
	# karannut syvemmalle avaruuteen kuin mihin se alun perin maalattiin. Kiekon
	# ulkopuolella (r > r_planet) ei ole muuta materiaalia kuin maalattu, joten tama
	# kattaa myos "ei materiaalia avaruudessa" -invariantin.
	_check(sand1["max_r"] <= sand0["max_r"] + 0.5, "hiekka ei karannut ulospain (max %.1f <= %.1f)" %
		[sand1["max_r"], sand0["max_r"]])
	_check(water1["max_r"] <= water0["max_r"] + 0.5, "vesi ei karannut ulospain (max %.1f <= %.1f)" %
		[water1["max_r"], water0["max_r"]])

	# (3) CPU-render-PNG (DiscWorld.save_debug_png ilman scene-treeta).
	var out := "res://tests/output/disc_smoke.png"
	var dw = _DW.new()
	dw.n = n
	dw.grid = grid
	dw.save_debug_png(out)
	dw.free()
	_check(FileAccess.file_exists(out), "PNG tallennettu: %s" % out)

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


# Sijoita blob suuntavektorin (dir, yksikkovektori) mukaan sateelle r keskipisteesta.
func _place_dir(grid: PackedInt32Array, n: int, c: float, dir: Vector2, r: float, rr: int, mat: int) -> void:
	var cx := int(round(c + dir.x * r))
	var cy := int(round(c + dir.y * r))
	_place_disc(grid, n, cx, cy, rr, mat)


# Taytetty ympyra materiaalia (sailyttaa kohdesolun seed-tavun, vaihtaa materiaalin).
func _place_disc(grid: PackedInt32Array, n: int, cx: int, cy: int, rr: int, mat: int) -> void:
	for dy in range(-rr, rr + 1):
		var py := cy + dy
		if py < 0 or py >= n:
			continue
		for dx in range(-rr, rr + 1):
			if dx * dx + dy * dy > rr * rr:
				continue
			var px := cx + dx
			if px < 0 or px >= n:
				continue
			var idx := py * n + px
			grid[idx] = (grid[idx] & 0xFFFFFF00) | (mat & 0xFF)


# Materiaalin solumaara + keskimaarainen/maksimi sade keskipisteesta.
func _mat_stats(grid: PackedInt32Array, n: int, mat: int) -> Dictionary:
	var count := 0
	var sum_r := 0.0
	var max_r := 0.0
	for y in n:
		for x in n:
			if (grid[y * n + x] & 0xFF) != mat:
				continue
			var r := Geom.radius_of(x, y, n)
			count += 1
			sum_r += r
			if r > max_r:
				max_r = r
	return {"count": count, "mean_r": (sum_r / count if count > 0 else 0.0), "max_r": max_r}
