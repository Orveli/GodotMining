extends SceneTree

# Yksikkotestit BotManager + Bot -tilakoneelle (scripts/bot_manager.gd, scripts/bot.gd).
# Kattaa katselmoinnissa puuttuneet alueet:
#   - Miner louhii kiven (STONE->GRAVEL) ja valmistaa solun (D_NONE + dig_site).
#   - Miner louhii granulaarin (DIRT) TYON kautta (etenee, ei jaa 2 s no-opiin / stall-vahdin varaan).
#   - Hauler imuroi irtomateriaalin cargoon ja purkaa baseen -> raha kasvaa.
#   - BLOCKED<->QUEUED reaktivointi: umpeen jaanyt designaatio muuttuu BLOCKEDiksi ja
#     palautuu QUEUEDiksi kun navnaapuri aukeaa (todistaa DoD-kohta 4: ei ikilooppia/jumia).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_bot_manager.gd

const SIM_W := 1664
const SIM_H := 960
const MAT_EMPTY := 0
const MAT_STONE := 3
const MAT_DIRT := 11
const MAT_GRAVEL := 18
const MAT_BEDROCK := 19

const D_NONE := 0
const D_QUEUED := 1
const D_BLOCKED := 2
const D_CLAIMED := 3
const D_MINING := 4

const DCELL := 16

var _pass := 0
var _fail := 0


# --- Kevyt fake-world joka tarjoaa BotManagerin tarvitseman rajapinnan ------
class FakeWorld extends Node:
	var grid: PackedByteArray
	var nav: NavGrid
	var desig: DesignationGrid
	var base: MoneyExit
	var building_pixels: Dictionary = {}
	var money: int = 0

	func _init() -> void:
		grid = PackedByteArray()
		grid.resize(SIM_W * SIM_H)
		grid.fill(MAT_EMPTY)
		nav = NavGrid.new()
		desig = DesignationGrid.new()

	func mvp_write_pixel(x: int, y: int, mat: int) -> void:
		if x < 0 or x >= SIM_W or y < 0 or y >= SIM_H:
			return
		var idx := y * SIM_W + x
		if building_pixels.has(idx):
			return
		if grid[idx] == MAT_BEDROCK:
			return
		grid[idx] = mat


func _init() -> void:
	print("=== BOTMANAGER-TESTIT ===\n")
	_test_miner_mines_stone_cell()
	_test_miner_progresses_on_granular()
	_test_hauler_vacuum_and_dump()
	_test_blocked_reactivates_when_neighbor_opens()
	print("\n=== YHTEENVETO ===")
	print("RESULT: %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		print("TEST: FAILED")
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: ", name)
	else:
		_fail += 1
		print("  FAILED: ", name)


func _make_world() -> FakeWorld:
	var w := FakeWorld.new()
	w.base = MoneyExit.new()
	w.base.setup(Vector2i(800, 200))
	return w


func _fill_rect(w: FakeWorld, x0: int, y0: int, ww: int, hh: int, mat: int) -> void:
	for y in range(y0, y0 + hh):
		if y < 0 or y >= SIM_H:
			continue
		for x in range(x0, x0 + ww):
			if x < 0 or x >= SIM_W:
				continue
			w.grid[y * SIM_W + x] = mat


func _count_mat_in_cell(w: FakeWorld, dx: int, dy: int, mat: int) -> int:
	var n := 0
	var x0 := dx * DCELL
	var y0 := dy * DCELL
	for y in range(y0, y0 + DCELL):
		for x in range(x0, x0 + DCELL):
			if w.grid[y * SIM_W + x] == mat:
				n += 1
	return n


# --- Testit -----------------------------------------------------------------

# Miner louhii kokonaisen STONE-solun (16x16=256 px): kaikki kivi kasitellaan, solu
# valmistuu (D_NONE) ja dig_site lisataan. 25 % hukka: osa kivesta murenee tyhjaksi
# (ei GRAVELia), loput 75 % -> GRAVEL. Invariantti: STONE loppuu, jaljella vain GRAVEL+EMPTY.
# Louhinta ajetaan suoraan WORK-tilassa (ei pathfindingia).
func _test_miner_mines_stone_cell() -> void:
	var w := _make_world()
	var dx := 40
	var dy := 40
	_fill_rect(w, dx * DCELL, dy * DCELL, DCELL, DCELL, MAT_STONE)
	w.nav.rebuild_full(w.grid)

	var bm := BotManager.new()
	bm.setup(w)
	var b := bm.add_bot(Bot.Role.MINER, Vector2(dx * DCELL, dy * DCELL - 20))
	b.target_cell = Vector2i(dx, dy)
	b.mine_targets = bm._cell_solids(dx, dy)
	b.mine_targets.sort_custom(bm._cmp_y_desc)
	b.mine_cursor = 0
	w.desig.set_cell(dx, dy, D_MINING)
	b.state = Bot.BotState.WORK

	var iters := 0
	while b.state == Bot.BotState.WORK and iters < 500:
		bm._work_mine(b, 0.1)  # 80 px/s * 0.1 = 8 px/tikki
		iters += 1

	var gravel := _count_mat_in_cell(w, dx, dy, MAT_GRAVEL)
	var empty := _count_mat_in_cell(w, dx, dy, MAT_EMPTY)
	var stone_left := _count_mat_in_cell(w, dx, dy, MAT_STONE)
	_check(stone_left == 0, "solussa ei jaljella kiveä, jaljella %d" % stone_left)
	_check(gravel + empty == 256, "kaikki 256 px louhittu (GRAVEL+tyhja), sai %d+%d" % [gravel, empty])
	_check(gravel > 0, "osa kivesta muuntui GRAVELiksi (75%% odotus), sai %d" % gravel)
	_check(w.desig.get_cell(dx, dy) == D_NONE, "solu valmistui -> D_NONE")
	_check(bm.dig_sites.has(Vector2i(dx, dy)), "dig_site lisattiin louhitulle solulle")


# Granulaari (DIRT) louhitaan TYON kautta: cursor etenee heti (ei stall-no-op), solu
# valmistuu, ja irtomateriaali jaa paikoilleen (loosening -> haulerin poimittavaksi).
# 25 % hukka: osa DIRTista murenee tyhjaksi; loput (~75 %) jaa paikoilleen kasaksi.
func _test_miner_progresses_on_granular() -> void:
	var w := _make_world()
	var dx := 50
	var dy := 50
	_fill_rect(w, dx * DCELL, dy * DCELL, DCELL, DCELL, MAT_DIRT)
	w.nav.rebuild_full(w.grid)

	var bm := BotManager.new()
	bm.setup(w)
	var b := bm.add_bot(Bot.Role.MINER, Vector2(dx * DCELL, dy * DCELL - 20))
	b.target_cell = Vector2i(dx, dy)
	b.mine_targets = bm._cell_solids(dx, dy)
	b.mine_targets.sort_custom(bm._cmp_y_desc)
	b.mine_cursor = 0
	w.desig.set_cell(dx, dy, D_MINING)
	b.state = Bot.BotState.WORK

	# Yksi tikki (0.2 s -> budjetti 16 px @ MINE_RATE=80): cursor etenee heti -> ei stall-riippuvuutta.
	bm._work_mine(b, 0.2)
	_check(b.mine_cursor >= 16, "granulaarilla edistyminen alkaa heti (cursor=%d >= 16)" % b.mine_cursor)

	var iters := 0
	while b.state == Bot.BotState.WORK and iters < 500:
		bm._work_mine(b, 0.2)
		iters += 1

	var dirt_left := _count_mat_in_cell(w, dx, dy, MAT_DIRT)
	var empty := _count_mat_in_cell(w, dx, dy, MAT_EMPTY)
	_check(w.desig.get_cell(dx, dy) == D_NONE, "granulaarisolu valmistui -> D_NONE")
	_check(bm.dig_sites.has(Vector2i(dx, dy)), "dig_site lisattiin granulaarisolulle")
	_check(dirt_left + empty == 256, "kaikki 256 px kasitelty (DIRT jai + tyhja hukka), sai %d+%d" % [dirt_left, empty])
	_check(dirt_left >= 128, "valtaosa DIRTista jai paikoilleen haulerille (>=128/256), jaljella %d" % dirt_left)


# Hauler imuroi DIRT-kasan cargoon ja purkaa baseen -> money kasvaa oikean summan.
func _test_hauler_vacuum_and_dump() -> void:
	var w := _make_world()
	var px := 300
	var py := 300
	_fill_rect(w, px - 8, py - 8, 16, 16, MAT_DIRT)  # 256 px DIRT-lohko (radius 10 kattaa >40)
	w.nav.rebuild_full(w.grid)

	var bm := BotManager.new()
	bm.setup(w)
	var b := bm.add_bot(Bot.Role.HAULER, Vector2(px, py - 40))
	b.pickup_pos = Vector2(px, py)

	var picked := bm._vacuum(b)
	_check(picked > 0, "hauler imuroi irtomateriaalia (picked=%d)" % picked)
	_check(b.cargo_total == Bot.CARRY_CAP, "cargo tayttyi CARRY_CAPiin (%d)" % b.cargo_total)
	_check(int(b.cargo.get(MAT_DIRT, 0)) == b.cargo_total, "koko kuorma on DIRTia")

	# Purku baseen
	w.money = 0
	var expected := w.base.accept_cargo(b.cargo)  # DIRT=1 -> 40
	bm._st_dump(b, 0.0)
	_check(w.money == expected, "purku kasvatti rahaa accept_cargon verran (%d)" % w.money)
	_check(w.money == Bot.CARRY_CAP, "40 px DIRTia = $40")
	_check(b.cargo_total == 0, "cargo tyhjeni purun jalkeen")


# Umpeen jaanyt designaatio -> BLOCKED; kun navnaapuri aukeaa -> QUEUED (reaktivointi).
# Todistaa ettei louhinta jumita frontieriin (DoD-kohta 4).
func _test_blocked_reactivates_when_neighbor_opens() -> void:
	var w := _make_world()
	# Umpikivi 128x128 (px 256..384), nav-linjattu (256/16=16).
	_fill_rect(w, 256, 256, 128, 128, MAT_STONE)
	w.nav.rebuild_full(w.grid)

	var bm := BotManager.new()
	bm.setup(w)

	# Designaatiosolu keskella kivea (DCELL=16 -> solu = navsolu; solu (19,19) keskus px 312,312,
	# nav-solut 16..23 taynna kivea -> sisasolun (19,19) kaikki 8 navnaapuria SOLID) -> ei OPEN-naapuria.
	var dx := 19
	var dy := 19
	w.desig.set_cell(dx, dy, D_QUEUED)

	_check(not bm._has_open_neighbor(dx, dy), "umpikivessa solulla EI ole OPEN-navnaapuria")
	bm._scan_designations()
	_check(w.desig.get_cell(dx, dy) == D_BLOCKED, "QUEUED umpisolu -> BLOCKED skannauksessa")

	# Avaa yksi navsolu (16x16) solun viereen: nav (19,18) = px [304,320)x[288,304).
	_fill_rect(w, 304, 288, 16, 16, MAT_EMPTY)
	w.nav.mark_dirty_px_rect(Rect2i(304, 288, 16, 16))
	w.nav.update_dirty(w.grid)

	_check(bm._has_open_neighbor(dx, dy), "navsolun avaamisen jalkeen OPEN-naapuri loytyy")
	bm._scan_designations()
	_check(w.desig.get_cell(dx, dy) == D_QUEUED, "BLOCKED-solu reaktivoituu QUEUEDiksi (ei jumia)")
