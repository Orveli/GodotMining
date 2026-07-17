extends SceneTree

# Yksikkotestit kiekkoplaneetan sektorigravitaatiolle (docs/SPEC_disc_planet.md Vaihe 1C).
# Validoi LOGIIKAN CPU-CA:lla (disc_cpu_ca.gd) — GLSL:aa ei voi kaantaa headlessina, joten
# GLSL-kaannoksen verifioi integraattori ikkunallisessa ajossa. Testit:
#   1. down_of-yksikot: 4 sektoria, diagonaalirajat, ei koskaan nollavektori, symmetria,
#      "alas" pienentaa sateen.
#   2-3. Hiekka pudotettuna pinnan ylapuolelle 4 ilmansuunnasta + 4 diagonaalista -> lahestyy
#      keskipistetta, paatyy pinnan tuntumaan ja pysahtyy.
#   4. Vesi kaivetussa kuopassa eri sektoreissa asettuu eika karkaa.
#   5. Steam nousee poispain keskipisteesta joka sektorissa.
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_disc_gravity.gd

const N := 256           # pieni parillinen grid (1408² olisi liian hidas CPU-steppaukseen)
const R_SURF := 100      # planeetan pinnan sade
const R_CORE := 8        # bedrock-ydin

var _pass := 0
var _fail := 0
var _ca                  # DiscCpuCa-instanssi (ladataan runtimessa)


func _init() -> void:
	print("=== DISC-GRAVITY-TESTIT ===\n")
	var ca_script := load("res://scripts/disc_cpu_ca.gd")
	if ca_script == null:
		print("  FAILED: disc_cpu_ca.gd lataus epaonnistui")
		print("\nRESULT: 0 passed, 1 failed")
		print("TEST: FAILED")
		quit(1)
		return
	_ca = ca_script.new()

	_test_down_of()
	_test_sand_cardinal()
	_test_sand_diagonal()
	_test_water_pit()
	_test_steam_rises()

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


# Rakenna kiekkogridi: bedrock-ydin, kivipinta, ulkopuoli tyhjaa (avaruus).
func _make_disc(n: int, r_surf: int, r_core: int) -> PackedInt32Array:
	var g := PackedInt32Array()
	g.resize(n * n)
	for y in n:
		for x in n:
			var idx := y * n + x
			if DiscGeom.inside_radius(x, y, r_core, n):
				g[idx] = DiscGeom.MAT_BEDROCK
			elif DiscGeom.inside_radius(x, y, r_surf, n):
				g[idx] = DiscGeom.MAT_STONE
			else:
				g[idx] = DiscGeom.MAT_EMPTY
	return g


# Sijoita materiaali suunnassa dvec (yksikkovektori keskipisteesta ulos) etaisyydelle r.
func _place_at_radius(g: PackedInt32Array, n: int, dvec: Vector2, r: float, mat: int) -> int:
	var c := (n - 1) * 0.5
	var px := int(round(c + dvec.x * r))
	var py := int(round(c + dvec.y * r))
	var idx := py * n + px
	g[idx] = mat
	return idx


# Etsi ensimmainen materiaalia mat oleva solu ja palauta sen sade (-1 jos ei loydy).
func _find_mat_radius(g: PackedInt32Array, n: int, mat: int) -> float:
	for i in n * n:
		if (g[i] & 0xFF) == mat:
			return DiscGeom.radius_of(i % n, i / n, n)
	return -1.0


func _step_n(g: PackedInt32Array, n: int, frame_start: int, count: int) -> void:
	for i in count:
		_ca.step(g, n, frame_start + i)


# --- Testi 1: down_of -------------------------------------------------------

func _test_down_of() -> void:
	print("down_of (sektorigravitaatio):")
	# 4 sektoria (ita/lansi/pohjoinen/etela suhteessa keskipisteeseen).
	_check(DiscGeom.down_of(200, 128, N) == Vector2i(-1, 0), "ita -> alas (-1,0)")
	_check(DiscGeom.down_of(50, 128, N) == Vector2i(1, 0), "lansi -> alas (1,0)")
	_check(DiscGeom.down_of(128, 50, N) == Vector2i(0, 1), "pohjoinen -> alas (0,1)")
	_check(DiscGeom.down_of(128, 200, N) == Vector2i(0, -1), "etela -> alas (0,-1)")

	# Diagonaalirajat (|dxc|==|dyc|) -> tasapeli menee PYSTYSEKTORIIN (down.x == 0).
	_check(DiscGeom.down_of(200, 200, N).x == 0, "diagonaaliraja x=y -> pysty")
	_check(DiscGeom.down_of(50, 50, N).x == 0, "diagonaaliraja x=y (vastakkainen) -> pysty")
	_check(DiscGeom.down_of(100, 155, N).x == 0, "antidiagonaali x+y=255 -> pysty")

	# Ei koskaan nollavektori; aina yksikkopituus (|dx|+|dy| == 1).
	var all_unit := true
	var all_toward := true
	for sy in [1, 7, 33, 64, 127, 128, 190, 254]:
		for sx in [1, 7, 33, 64, 127, 128, 190, 254]:
			var d := DiscGeom.down_of(sx, sy, N)
			if absi(d.x) + absi(d.y) != 1:
				all_unit = false
			# "Alas" pienentaa sateen (paitsi keskimmaisessa 2x2:ssa, jonka core peittaa).
			var r0 := DiscGeom.radius_of(sx, sy, N)
			if r0 > float(R_CORE):
				var r1 := DiscGeom.radius_of(sx + d.x, sy + d.y, N)
				if r1 >= r0:
					all_toward = false
	_check(all_unit, "down_of aina yksikkovektori (ei nollaa)")
	_check(all_toward, "down_of pienentaa sateen (osoittaa keskipisteeseen)")

	# Pistesymmetria keskipisteen kautta: down_of(n-1-x, n-1-y) == -down_of(x,y).
	var all_sym := true
	for p in [Vector2i(200, 128), Vector2i(70, 90), Vector2i(128, 40), Vector2i(210, 60)]:
		var d := DiscGeom.down_of(p.x, p.y, N)
		var dm := DiscGeom.down_of(N - 1 - p.x, N - 1 - p.y, N)
		if dm != -d:
			all_sym = false
	_check(all_sym, "pistesymmetria: down_of(peilattu) == -down_of")


# --- Testi 2: hiekka 4 ilmansuunnasta ---------------------------------------

func _test_sand_cardinal() -> void:
	print("hiekka pudotettuna (4 ilmansuuntaa):")
	var dirs := {
		"pohjoinen": Vector2(0, -1),
		"etela": Vector2(0, 1),
		"lansi": Vector2(-1, 0),
		"ita": Vector2(1, 0),
	}
	for name in dirs:
		_run_sand_drop(name, dirs[name], 120)


func _test_sand_diagonal() -> void:
	print("hiekka pudotettuna (4 diagonaalia, sektorirajan yli):")
	var s := 0.70710678
	var dirs := {
		"koillinen": Vector2(s, -s),
		"kaakko": Vector2(s, s),
		"lounas": Vector2(-s, s),
		"luode": Vector2(-s, -s),
	}
	for name in dirs:
		_run_sand_drop(name, dirs[name], 200)


# Pudota yksi hiekanjyva suunnassa dvec pinnan ylapuolelle, steppaa, tarkista lahestyminen +
# pysahtyminen pinnan tuntumaan.
func _run_sand_drop(name: String, dvec: Vector2, steps: int) -> void:
	var g := _make_disc(N, R_SURF, R_CORE)
	var r_start := float(R_SURF) + 12.0
	_place_at_radius(g, N, dvec, r_start, DiscGeom.MAT_SAND)
	var r_init := _find_mat_radius(g, N, DiscGeom.MAT_SAND)

	# Steppaa suurin osa, mittaa, steppaa loput, mittaa -> pysahtymistarkistus.
	var settle := 20
	_step_n(g, N, 0, steps - settle)
	var r_mid := _find_mat_radius(g, N, DiscGeom.MAT_SAND)
	_step_n(g, N, steps - settle, settle)
	var r_end := _find_mat_radius(g, N, DiscGeom.MAT_SAND)

	if r_end < 0.0:
		_check(false, "%s: jyva katosi" % name)
		return
	var approached := r_end < r_init - 5.0
	var at_surface := r_end <= float(R_SURF) + 3.0 and r_end >= float(R_CORE)
	var stopped := absf(r_end - r_mid) <= 4.0
	_check(approached and at_surface and stopped,
		"%s: r %.1f -> %.1f (pinta ~%d, pysahtyi d=%.1f)" % [name, r_init, r_end, R_SURF, absf(r_end - r_mid)])


# --- Testi 4: vesi kuopassa -------------------------------------------------

func _test_water_pit() -> void:
	print("vesi kaivetussa kuopassa (eri sektorit):")
	_run_water_pit("pohjoinen", Vector2(0, -1))
	_run_water_pit("ita", Vector2(1, 0))


# Kaiva kuoppa pintaan suunnassa dvec, tayta vedella, steppaa -> vesi sailyy ja pysyy kuopassa.
func _run_water_pit(name: String, dvec: Vector2) -> void:
	var g := _make_disc(N, R_SURF, R_CORE)
	var depth := 25.0
	var half_w := 8.0
	var water_h := 12.0
	var water_count := 0
	var c := (N - 1) * 0.5
	var pvec := Vector2(-dvec.y, dvec.x)  # tangentti
	for y in N:
		for x in N:
			var rx := x - c
			var ry := y - c
			var along := rx * dvec.x + ry * dvec.y   # ulospain positiivinen
			var across := rx * pvec.x + ry * pvec.y
			if absf(across) <= half_w and along >= float(R_SURF) - depth and along <= float(R_SURF) + 4.0:
				var idx := y * N + x
				g[idx] = DiscGeom.MAT_EMPTY  # kaiva
				if absf(across) <= half_w - 1.0 and along <= float(R_SURF) - depth + water_h:
					g[idx] = DiscGeom.MAT_WATER
					water_count += 1

	_step_n(g, N, 0, 100)

	# Laske vesi ja mittaa sen ulompi sade.
	var count_after := 0
	var max_r := 0.0
	for i in N * N:
		if (g[i] & 0xFF) == DiscGeom.MAT_WATER:
			count_after += 1
			var r := DiscGeom.radius_of(i % N, i / N, N)
			if r > max_r:
				max_r = r
	var conserved := count_after == water_count
	var contained := max_r <= float(R_SURF) + 1.0
	_check(conserved and contained,
		"%s: vesi %d->%d (sailyy=%s), max_r=%.1f <= %d (ei karannut)" % [
			name, water_count, count_after, str(conserved), max_r, R_SURF])


# --- Testi 5: steam nousee --------------------------------------------------

func _test_steam_rises() -> void:
	print("steam nousee poispain keskipisteesta (joka sektori):")
	var dirs := {
		"pohjoinen": Vector2(0, -1),
		"etela": Vector2(0, 1),
		"lansi": Vector2(-1, 0),
		"ita": Vector2(1, 0),
	}
	for name in dirs:
		var g := _make_disc(N, R_SURF, R_CORE)
		_place_at_radius(g, N, dirs[name], float(R_SURF) + 5.0, DiscGeom.MAT_STEAM)
		var r_init := _find_mat_radius(g, N, DiscGeom.MAT_STEAM)
		_step_n(g, N, 0, 15)
		var r_end := _find_mat_radius(g, N, DiscGeom.MAT_STEAM)
		var rose := r_end > r_init + 5.0
		_check(rose, "%s: steam r %.1f -> %.1f (nousi)" % [name, r_init, r_end])
