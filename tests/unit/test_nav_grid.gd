extends SceneTree

# Yksikkotestit NavGridille (scripts/nav_grid.gd).
# Rakentaa synteettisen 1664x960 CA-gridin ja testaa A*-reitityksen +
# lapaisevyyskynnyksen + dirty-osittaispaivityksen.
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_nav_grid.gd

const SIM_W := 1664
const SIM_H := 960

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

	var from_px := Vector2(400, 480)
	var to_px := Vector2(1200, 480)
	var path := nav.find_path_px(from_px, to_px)

	_check(path.size() > 0, "polku loytyy kahden pisteen valilla tyhjassa maailmassa")
	# Viimeisen waypointin tulisi osua kohdesolun keskipisteeseen.
	if path.size() > 0:
		var last: Vector2 = path[path.size() - 1]
		var goal_center := Vector2(75 * 16 + 8, 30 * 16 + 8)  # (1208, 488)
		_check(last.distance_to(goal_center) < 1.0, "polun paatepiste = kohdesolun keskipiste")


# --- Testi 2: umpiseina estaa reitin ----------------------------------------

func _test_wall_blocks_path() -> void:
	print("\n--- Testi 2: Umpinainen STONE-seina estaa reitin ---")
	_reset_grid()
	# Pystyseina solusarakkeeseen 50 (x 800..815) koko korkeudelta -> jakaa maailman.
	_fill_rect(800, 0, 16, SIM_H, MAT_STONE)
	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	# Varmistetaan ettei seinasolu ole OPEN.
	_check(not nav.is_open(50, 30), "seinasolu (50,30) on SOLID")
	_check(nav.is_open(25, 30) and nav.is_open(75, 30), "vasen ja oikea puoli ovat OPEN")

	var path := nav.find_path_px(Vector2(400, 480), Vector2(1200, 480))
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
	# Sama umpiseina kuin testissa 2.
	_fill_rect(800, 0, 16, SIM_H, MAT_STONE)
	var nav := NavGrid.new()
	nav.rebuild_full(_grid)

	var path_before := nav.find_path_px(Vector2(400, 480), Vector2(1200, 480))
	_check(path_before.size() == 0, "ennen reikaa: ei polkua")

	# Puhkaistaan solu (50,30): px (800,480)..(815,495) -> EMPTY.
	_fill_rect(800, 480, 16, 16, MAT_EMPTY)
	nav.mark_dirty_px_rect(Rect2i(800, 480, 16, 16))
	nav.update_dirty(_grid)

	_check(nav.is_open(50, 30), "reikasolu (50,30) on paivittynyt OPENiksi")
	var path_after := nav.find_path_px(Vector2(400, 480), Vector2(1200, 480))
	_check(path_after.size() > 0, "reian jalkeen: polku loytyy")

	# Varmistetaan etta muut seinasolut pysyivat SOLIDeina (osittaispaivitys ei
	# nollannut koko karttaa).
	_check(not nav.is_open(50, 10) and not nav.is_open(50, 50), "muut seinasolut yha SOLID")
