extends SceneTree

# Yksikkotestit NavGridille (scripts/nav_grid.gd).
# Rakentaa synteettisen 4096x448 CA-gridin (planeettakoko) ja testaa A*-reitityksen +
# lapaisevyyskynnyksen + dirty-osittaispaivityksen + TOROIDAALISEN wrapin (sauman yli).
# HUOM: x-akseli wrappaa (sauma x=0 <-> x=NW-1), joten yksi PYSTYseina EI enaa katkaise
# maailmaa (voi kiertaa sauman kautta) -> estotestit kayttavat VAAKAseinaa (y ei wrappaa).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_nav_grid.gd

# Mirroroi NavGridin planeettakokoa (NW=256, NH=28 -> 4096x448).
const SIM_W := 4096
const SIM_H := 448

const MAT_EMPTY := 0
const MAT_STONE := 3

# Kaytetaan jasenmuuttujaa: index-assign jasenmuuttujaan heijastuu aina takaisin
# (toisin kuin parametrina valitetyn PackedByteArrayn mutatointi CoW:n takia).
var _grid: PackedByteArray

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== NAVGRID-TESTIT ===\n")
	_test_empty_world_path()
	_test_wall_blocks_path()
	_test_open_threshold()
	_test_dirty_update_opens_path()
	_test_seam_path()
	_test_octile_wrap()
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


func _reset_grid() -> void:
	# Tuore tyhja (EMPTY) CA-gridi tasmalleen simulaation kokoisena.
	_grid = PackedByteArray()
	_grid.resize(SIM_W * SIM_H)
	_grid.fill(MAT_EMPTY)


func _fill_rect(x0: int, y0: int, w: int, h: int, mat: int) -> void:
	# Mutatoi jasenmuuttujaa suoraan -> muutokset sailyvat.
	for y in range(y0, y0 + h):
		if y < 0 or y >= SIM_H:
			continue
		var base := y * SIM_W
		for x in range(x0, x0 + w):
			if x < 0 or x >= SIM_W:
				continue
			_grid[base + x] = mat


# --- Testi 1: tyhjassa maailmassa polku loytyy ------------------------------

func _test_empty_world_path() -> void:
	print("--- Testi 1: Polku tyhjassa maailmassa ---")
	_reset_grid()
	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	var from_px := Vector2(400, 224)
	var to_px := Vector2(1200, 224)
	var path := nav.find_path_px(from_px, to_px)

	_check(path.size() > 0, "polku loytyy kahden pisteen valilla tyhjassa maailmassa")
	# Viimeisen waypointin tulisi osua kohdesolun keskipisteeseen.
	if path.size() > 0:
		var last: Vector2 = path[path.size() - 1]
		var goal_center := Vector2(75 * 16 + 8, 14 * 16 + 8)  # (1208, 232)
		_check(last.distance_to(goal_center) < 1.0, "polun paatepiste = kohdesolun keskipiste")


# --- Testi 2: umpiseina estaa reitin (VAAKAseina, koska y ei wrappaa) --------

func _test_wall_blocks_path() -> void:
	print("\n--- Testi 2: Umpinainen VAAKA-STONE-seina estaa reitin ---")
	_reset_grid()
	# Vaakaseina solurivilla 14 (y 224..239) koko leveydelta -> jakaa maailman ylos/alas.
	# (Pystyseina EI kavisi: x wrappaa, joten sen voisi kiertaa sauman kautta.)
	_fill_rect(0, 224, SIM_W, 16, MAT_STONE)
	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	# Varmistetaan ettei seinasolu ole OPEN.
	_check(not nav.is_open(50, 14), "seinasolu (50,14) on SOLID")
	_check(nav.is_open(25, 6) and nav.is_open(25, 21), "seinan ylä- ja alapuoli ovat OPEN")

	var path := nav.find_path_px(Vector2(400, 100), Vector2(400, 350))
	_check(path.size() == 0, "umpiseinan lapi EI loydy polkua")


# --- Testi 3: OPEN-kynnys (70 %) --------------------------------------------

func _test_open_threshold() -> void:
	print("\n--- Testi 3: OPEN-kynnys ---")
	_reset_grid()

	# Solu (10,10): px-alue (160,160)..(175,175). Tayta 128/256 pikselia STONElla
	# (ylemmat 8 rivia, 16 px leveita) -> tasan 50 % kiintea -> SOLID.
	_fill_rect(160, 160, 16, 8, MAT_STONE)

	# Solu (20,20): px-alue (320,320)..(335,335). Tayta 5x5 = 25 px STONElla
	# -> passable 231/256 ~= 90 % tyhja -> OPEN.
	_fill_rect(320, 320, 5, 5, MAT_STONE)

	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	_check(not nav.is_open(10, 10), "~50 % kiintea solu on SOLID")
	_check(nav.is_open(20, 20), "~90 % tyhja solu on OPEN")
	# is_open_px kayttaa samaa logiikkaa px-koordinaateista.
	_check(not nav.is_open_px(Vector2(168, 168)), "is_open_px SOLID-solun sisalla = false")
	_check(nav.is_open_px(Vector2(328, 328)), "is_open_px OPEN-solun sisalla = true")


# --- Testi 4: dirty-paivitys avaa reitin ------------------------------------

func _test_dirty_update_opens_path() -> void:
	print("\n--- Testi 4: Dirty-paivitys avaa reian ---")
	_reset_grid()
	# Sama vaakaseina kuin testissa 2.
	_fill_rect(0, 224, SIM_W, 16, MAT_STONE)
	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	var path_before := nav.find_path_px(Vector2(400, 100), Vector2(400, 350))
	_check(path_before.size() == 0, "ennen reikaa: ei polkua")

	# Puhkaistaan solu (25,14): px (400,224)..(415,239) -> EMPTY.
	_fill_rect(400, 224, 16, 16, MAT_EMPTY)
	nav.mark_dirty_px_rect(Rect2i(400, 224, 16, 16))
	nav.update_dirty(_grid)

	_check(nav.is_open(25, 14), "reikasolu (25,14) on paivittynyt OPENiksi")
	var path_after := nav.find_path_px(Vector2(400, 100), Vector2(400, 350))
	_check(path_after.size() > 0, "reian jalkeen: polku loytyy")

	# Varmistetaan etta muut seinasolut pysyivat SOLIDeina (osittaispaivitys ei
	# nollannut koko karttaa).
	_check(not nav.is_open(50, 14) and not nav.is_open(100, 14), "muut seinasolut yha SOLID")


# --- Testi 5: A* loytaa reitin SAUMAN yli (toroidaalinen x) ------------------

func _test_seam_path() -> void:
	print("\n--- Testi 5: A* reitittaa sauman yli ---")
	_reset_grid()
	# Pystyseina keskelle (solusarake 128, x 2048..2063) koko korkeudelta. Se EI katkaise
	# maailmaa (x wrappaa), mutta se PAKOTTAA suoran keskireitin kiertoon sauman kautta.
	# Lahto solu (2,14) ja maali (254,14) ovat seinan eri puolilla suoraan mitattuna, mutta
	# sauman yli (2 -> 1 -> 0 -> 255 -> 254) vain ~4 solun paassa.
	_fill_rect(2048, 0, 16, SIM_H, MAT_STONE)
	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	_check(not nav.is_open(128, 14), "keskiseinasolu (128,14) on SOLID")

	var from_px := Vector2(2 * 16 + 8, 14 * 16 + 8)    # (40, 232), solu (2,14)
	var to_px := Vector2(254 * 16 + 8, 14 * 16 + 8)    # (4072, 232), solu (254,14)
	var path := nav.find_path_px(from_px, to_px)

	# Polku loytyy VAIN jos A* osaa kiertaa sauman kautta (keskiseina tukkii suoran reitin).
	_check(path.size() > 0, "polku loytyy sauman yli (keskiseina tukkii suoran reitin)")
	if path.size() > 0:
		var last: Vector2 = path[path.size() - 1]
		_check(last.distance_to(to_px) < 1.0, "sauma-polun paatepiste = maalisolun keskipiste")


# --- Testi 6: oktiili-heuristiikka wrappaa x:n ------------------------------

func _test_octile_wrap() -> void:
	print("\n--- Testi 6: Oktiili-heuristiikka wrappaa x:n ---")
	var nav := NavGrid.new()
	# Solusta 2 soluun 254 (NW=256): suora dx=252, mutta sauman yli dx=4.
	# Admissiivinen heuristiikka kayttaa lyhinta (4) -> muuten A* ei loytaisi optimia.
	var h_seam := nav._octile(2, 14, 254, 14)
	_check(absf(h_seam - 4.0) < 0.001, "octile(2->254) = 4 (sauman yli), ei 252")
	# Ei-sauma-tapaus sailyy ennallaan: dx=8.
	var h_near := nav._octile(2, 14, 10, 14)
	_check(absf(h_near - 8.0) < 0.001, "octile(2->10) = 8 (ei sauman yli)")
