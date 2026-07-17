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
const MAT_IRON_ORE := 12
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
	# M1: inventaario-API:n peilaus (pixel_world.deposit_* — oletuspolitiikka SELL,
	# joten vanhat raha-assertit pysyvat valideina; STORE vain jos policy asetettu).
	var inventory: Dictionary = {}
	var material_policy: Dictionary = {}
	var total_revenue: int = 0

	func _init() -> void:
		grid = PackedByteArray()
		grid.resize(SIM_W * SIM_H)
		grid.fill(MAT_EMPTY)
		nav = NavGrid.new()
		desig = DesignationGrid.new()

	func deposit_material(mat_id: int, px: int) -> void:
		if px <= 0:
			return
		if int(material_policy.get(mat_id, 0)) == 1:  # POLICY_STORE
			inventory[mat_id] = int(inventory.get(mat_id, 0)) + px
		else:
			var value := int(MoneyExit.PRICES.get(mat_id, MoneyExit.DEFAULT_PRICE)) * px
			money += value
			total_revenue += value

	func deposit_cargo(cargo: Dictionary) -> void:
		for mat_id in cargo:
			deposit_material(int(mat_id), int(cargo[mat_id]))

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
	_test_buy_bot_price_and_spawn()
	_test_set_role_interrupts_claim_and_dumps_cargo()
	_test_upgrade_bot_tiers()
	_test_get_fleet_stats()
	_test_hauler_routes_to_accepting_dump_zone()
	_test_hauler_stays_idle_with_cargo_when_no_dump_accepts()
	_test_dig_site_fifo_keeps_nonempty_piles()
	_test_hauler_collects_single_cell_between_walls()
	_test_assignment_scales_with_many_bots()
	_test_haulers_spread_over_piles()
	_test_small_pile_limits_claims()
	_test_big_pile_allows_multiple_claims()
	_test_miners_spread_frontier()
	_test_separation_diverges_overlapping_bots()
	_test_separation_push_capped()
	_test_crowd_factor_curve()
	_test_timed_dump_drains_over_time()
	_test_dump_cargo_conserved_when_destination_full()
	_test_dump_watchdog_sells_leftover()
	_test_vacuum_slows_under_congestion()
	_test_idle_reason_derivation()
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

	# Purku baseen: uusi kaytos = kuorma pudotetaan FYYSISINA pikseleina intake-aukon
	# ylapuolelle (ei enaa suoraa accept_cargoa). FakeWorld ei aja update_exitia, joten
	# raha pysyy 0:ssa; sen sijaan pikselit loytyvat drop-sarakkeista basen ylapuolelta.
	# Kerros 3: dumppi on AJALLINEN -> tikataan kunnes valmis (ei enaa yksi _st_dump-kutsu).
	w.money = 0
	var expected_px := b.cargo_total  # 40 DIRT-pikselia
	b.dump_target = {}                # ei dump_targetia -> fallback basen intakeen
	b.state = Bot.BotState.DUMP
	b.work_accum = 0.0
	for _t in 200:
		if b.state != Bot.BotState.DUMP:
			break
		bm._st_dump(b, 0.1)
	_check(b.cargo_total == 0, "cargo tyhjeni purun jalkeen (ajallinen dumppi)")
	_check(w.money == 0, "base-purku EI enaa anna rahaa suoraan (raha tulee putoavista pikseleista update_exitissa)")
	# Laske pudotetut DIRT-pikselit intake-sarakkeista basen ylapuolelta (y < grid_pos.y).
	var cols: Array = w.base.drop_columns()
	var top_y: int = w.base.grid_pos.y
	var dropped := 0
	for yy in range(0, top_y):
		for cx in cols:
			if w.grid[yy * SIM_W + int(cx)] == MAT_DIRT:
				dropped += 1
	_check(dropped == expected_px, "kaikki %d DIRT-pikselia pudotettiin intake-sarakkeisiin basen ylapuolelle, loytyi %d" % [expected_px, dropped])


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


# --- A1: Osto & nouseva hinta ------------------------------------------------

# next_bot_price(): 25 * 1.25^n, n = ostetut (aloitus-2 ei laske).
# buy_bot(): tarkistaa varan, vahentaa rahan, spawnaa world.base.spawn_pos():iin.
func _test_buy_bot_price_and_spawn() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	# Alkutila: 2 aloitusbottia EIVAT ole ostettuja -> ensimmainen osto on silti hinnalla 25.
	bm.add_bot(Bot.Role.MINER, Vector2(10, 10))
	bm.add_bot(Bot.Role.HAULER, Vector2(20, 10))
	_check(bm.next_bot_price() == 25, "ensimmaisen ostettavan botin hinta on 25 (aloitusbotit eivat kasvata), sai %d" % bm.next_bot_price())

	# Ei varaa -> osto epaonnistuu, raha ja bottimaara ennallaan.
	w.money = 24
	var before_count := bm.bot_count()
	_check(bm.buy_bot(Bot.Role.MINER) == false, "buy_bot palauttaa false kun raha ei riita")
	_check(bm.bot_count() == before_count, "epaonnistunut osto ei spawnaa bottia")
	_check(w.money == 24, "epaonnistunut osto ei vahenna rahaa")

	# Riittava raha -> osto onnistuu, raha vahenee, botti ilmestyy basen spawn_pos:iin.
	w.money = 25
	_check(bm.buy_bot(Bot.Role.MINER) == true, "buy_bot onnistuu kun raha riittaa")
	_check(w.money == 0, "osto vahensi rahan tasan hinnan verran")
	_check(bm.bot_count() == before_count + 1, "botti lisattiin laumaan")
	var spawned: Bot = bm.bots[bm.bots.size() - 1]
	_check(spawned.pos.is_equal_approx(w.base.spawn_pos()), "uusi botti spawnasi basen spawn_pos:iin")

	# Nouseva hinta: 2. ostettu botti (n=1) -> round(25*1.25) = 31.
	_check(bm.next_bot_price() == 31, "toisen ostetun botin hinta nousee 31:een, sai %d" % bm.next_bot_price())
	w.money = 31
	_check(bm.buy_bot(Bot.Role.HAULER) == true, "toinen osto onnistuu 31:lla")
	# 3. ostettu botti (n=2) -> round(25*1.25^2) = 39.
	_check(bm.next_bot_price() == 39, "kolmannen ostetun botin hinta nousee 39:aan, sai %d" % bm.next_bot_price())


# --- A1: Roolinvaihto kesken tyon --------------------------------------------

# set_role(): CLAIMED-designaatio palautuu QUEUEDiksi, cargo dumpataan baseen ennen vaihtoa.
func _test_set_role_interrupts_claim_and_dumps_cargo() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)

	# 1) Miner jolla on CLAIMED-designaatio -> roolinvaihto vapauttaa sen QUEUEDiksi.
	var dx := 30
	var dy := 30
	w.desig.set_cell(dx, dy, D_CLAIMED)
	var miner := bm.add_bot(Bot.Role.MINER, Vector2(dx * DCELL, dy * DCELL))
	miner.target_cell = Vector2i(dx, dy)
	miner.state = Bot.BotState.MOVE

	bm.set_role(miner.id, Bot.Role.HAULER)
	_check(miner.role == Bot.Role.HAULER, "rooli vaihtui HAULERiksi")
	_check(w.desig.get_cell(dx, dy) == D_QUEUED, "CLAIMED-designaatio vapautui QUEUEDiksi roolinvaihdossa")
	_check(miner.state == Bot.BotState.IDLE, "tilakone nollautui IDLEen")
	_check(miner.target_cell == Vector2i(-1, -1), "target_cell nollautui")

	# 2) Hauler jolla on kesken kuorma -> cargo dumpataan baseen ennen vaihtoa, raha kasvaa.
	var hauler := bm.add_bot(Bot.Role.HAULER, Vector2(100, 100))
	hauler.add_cargo(MAT_DIRT, 15)
	w.money = 0
	bm.set_role(hauler.id, Bot.Role.MINER)
	_check(hauler.role == Bot.Role.MINER, "hauler vaihtui MINERiksi")
	_check(hauler.cargo_total == 0, "cargo tyhjeni roolinvaihdossa")
	_check(w.money == 15, "kesken ollut kuorma (15 DIRT) myytiin baseen roolinvaihdossa, sai %d" % w.money)

	# 3) Sama rooli -> ei-op (ei kaada, ei muuta tilaa turhaan).
	var m2 := bm.add_bot(Bot.Role.MINER, Vector2(50, 50))
	m2.state = Bot.BotState.WORK
	bm.set_role(m2.id, Bot.Role.MINER)
	_check(m2.state == Bot.BotState.WORK, "sama rooli ei keskeyta kesken olevaa tyota")


# --- A2: Mk-upgrade-tierit ----------------------------------------------------

# upgrade_bot(): Mk1->Mk2 400, Mk2->Mk3 900; kapasiteetti/nopeus mitattavissa tierin mukaan.
func _test_upgrade_bot_tiers() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	var b := bm.add_bot(Bot.Role.MINER, Vector2(10, 10))
	_check(b.tier == 1, "botti syntyy Mk1:na")
	_check(b.carry_cap() == 40 and b.mine_rate() == 80.0 and b.move_speed() == 40.0,
		"Mk1-arvot: carry=40 mine=80 speed=40, sai carry=%d mine=%.0f speed=%.0f" % [b.carry_cap(), b.mine_rate(), b.move_speed()])
	_check(bm.upgrade_price(b.id) == 400, "Mk1->Mk2 hinta on 400")

	# Ei varaa -> upgrade epaonnistuu, tier ennallaan.
	w.money = 399
	_check(bm.upgrade_bot(b.id) == false, "upgrade epaonnistuu kun raha ei riita")
	_check(b.tier == 1, "tier ei muuttunut epaonnistuneessa upgradessa")

	# Riittava raha -> Mk2.
	w.money = 400
	_check(bm.upgrade_bot(b.id) == true, "Mk1->Mk2 onnistuu 400:lla")
	_check(w.money == 0, "upgrade vahensi rahan tasan hinnan verran")
	_check(b.tier == 2, "botti on nyt Mk2")
	_check(b.carry_cap() == 90 and b.mine_rate() == 140.0 and b.move_speed() == 70.0,
		"Mk2-arvot: carry=90 mine=140 speed=70, sai carry=%d mine=%.0f speed=%.0f" % [b.carry_cap(), b.mine_rate(), b.move_speed()])

	# Mk2->Mk3 hinta 900.
	_check(bm.upgrade_price(b.id) == 900, "Mk2->Mk3 hinta on 900")
	w.money = 900
	_check(bm.upgrade_bot(b.id) == true, "Mk2->Mk3 onnistuu 900:lla")
	_check(b.tier == 3, "botti on nyt Mk3")
	_check(b.carry_cap() == 180 and b.mine_rate() == 220.0 and b.move_speed() == 110.0,
		"Mk3-arvot: carry=180 mine=220 speed=110, sai carry=%d mine=%.0f speed=%.0f" % [b.carry_cap(), b.mine_rate(), b.move_speed()])

	# Mk3 on katto -> ei enaa upgradea.
	_check(bm.upgrade_price(b.id) == 0, "Mk3:lla ei ole enaa upgrade-hintaa (0)")
	w.money = 9999
	_check(bm.upgrade_bot(b.id) == false, "upgrade epaonnistuu Mk3:sta eteenpain")
	_check(w.money == 9999, "epaonnistunut upgrade ei vahenna rahaa")


# --- A1: get_fleet_stats + bot_count ------------------------------------------

func _test_get_fleet_stats() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	var m1 := bm.add_bot(Bot.Role.MINER, Vector2(10, 10))
	bm.add_bot(Bot.Role.MINER, Vector2(20, 10))
	var h1 := bm.add_bot(Bot.Role.HAULER, Vector2(30, 10))
	m1.state = Bot.BotState.WORK
	h1.state = Bot.BotState.CARRY_MOVE

	_check(bm.bot_count() == 3, "bot_count palauttaa laumakoon (3)")
	var stats := bm.get_fleet_stats()
	_check(int(stats["miners"]) == 2, "2 mineria tilastoissa")
	_check(int(stats["haulers"]) == 1, "1 hauler tilastoissa")
	_check(int(stats["miners_active"]) == 1, "1 miner aktiivinen (WORK)")
	_check(int(stats["haulers_active"]) == 1, "1 hauler aktiivinen (CARRY_MOVE)")
	_check((stats["bots"] as Array).size() == 3, "bots-lista sisaltaa kaikki 3 bottia")


# --- A3: Hauler vie dump-vyohykkeelle joka hyvaksyy kuorman ------------------

# GDD §4.2: hauler valitsee dumpin joka hyvaksyy suurimman osan kuormasta ja on lahinna.
# HUOM: base EI ole enaa kovakoodattu pseudokandidaatti (aiempi "base-filtteri kieltaa"
# -skenaario poistui logistics.gd:n choose_dump-refaktoroinnissa) — hauler valitsee AINA
# jonkin dump-vyohykkeen (mukaan lukien mahdollinen base-dropoff); tassa testissa ainoa
# rekisteroity dump-vyohyke hyvaksyy IRON_ORE:n, joten hauler ohjautuu sinne.
func _test_hauler_routes_to_accepting_dump_zone() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	bm.logistics = Logistics.new()

	# Dump-vyohyke joka hyvaksyy IRON_ORE:n, sijoitettu basesta erilleen (ei paalla structure_pixels).
	var dump_rect := Rect2i(1000, 500, 20, 20)
	var dump_id := bm.logistics.add_dump_point(dump_rect, 1 << MAT_IRON_ORE)

	var hauler := bm.add_bot(Bot.Role.HAULER, Vector2(1100, 100))
	hauler.add_cargo(MAT_IRON_ORE, 30)

	bm._start_dump(hauler)
	_check(String(hauler.dump_target.get("kind", "")) == "dump", "hauler valitsee ainoan hyvaksyvan dump-vyohykkeen")
	_check(int(hauler.dump_target.get("id", -1)) == dump_id, "dump_target.id vastaa rekisteroityä dump-pointin id:ta")
	_check(bool(hauler.dump_target.get("is_base_dropoff", true)) == false, "tavallinen dump-piste ei ole base-dropoff")
	var chosen_rect: Rect2i = hauler.dump_target.get("rect", Rect2i())
	_check(chosen_rect == dump_rect, "valittu dump-alue vastaa rekisteroityä dump-pointtia")

	# Aja purku loppuun: kuljeta perille (path tyhjaksi) ja pura AJALLISESTI (tikataan valmiiksi).
	hauler.path = PackedVector2Array()
	hauler.path_idx = 0
	hauler.pos = Vector2(chosen_rect.position) + Vector2(chosen_rect.size) * 0.5
	hauler.state = Bot.BotState.DUMP
	hauler.work_accum = 0.0
	w.money = 0
	for _t in 200:
		if hauler.state != Bot.BotState.DUMP:
			break
		bm._st_dump(hauler, 0.1)
	_check(hauler.cargo_total == 0, "kuorma purkautui")
	_check(w.money == 0, "IRON_ORE ei mene suoraan rahaksi (kirjoitetaan pikseleina dump-alueelle)")
	# Kirjoitetut pikselit loytyvat dump-alueelta IRON_ORE-materiaalina (kone/pickup poimii ne myohemmin).
	var found_ore := 0
	for y in range(dump_rect.position.y, dump_rect.position.y + dump_rect.size.y):
		for x in range(dump_rect.position.x, dump_rect.position.x + dump_rect.size.x):
			if w.grid[y * SIM_W + x] == MAT_IRON_ORE:
				found_ore += 1
	_check(found_ore == 30, "kaikki 30 IRON_ORE-pikselia kirjoitettiin dump-alueelle, loytyi %d" % found_ore)


# --- A3b: Hauler EI hyvaksyvaa dump-vyohyketta -> jaa IDLEen kuorman kanssa --

# Uusi kaytos (base-fallback poistettu): jos mikaan dump-vyohyke ei hyvaksy kuormaa,
# hauler EI enaa palaa automaattisesti baseen — se pitaa kuorman, jaa IDLEen ja
# yrittaa uudelleen DUMP_RETRY_DELAY-sekunnin paasta (ks. bot_manager.gd _start_dump).
func _test_hauler_stays_idle_with_cargo_when_no_dump_accepts() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	bm.logistics = Logistics.new()
	# Ainoa dump-vyohyke hyvaksyy vain DIRTin -> ei hyvaksy IRON_ORE-kuormaa.
	bm.logistics.add_dump_point(Rect2i(1000, 500, 20, 20), 1 << MAT_DIRT)

	var hauler := bm.add_bot(Bot.Role.HAULER, Vector2(1100, 100))
	hauler.add_cargo(MAT_IRON_ORE, 30)

	bm._start_dump(hauler)
	_check(hauler.state == Bot.BotState.IDLE, "hauler jaa IDLEen kun mikaan dump ei hyvaksy kuormaa")
	_check(hauler.cargo_total == 30, "kuorma sailyy (ei tyhjenny epaonnistuneessa dump-yrityksessa)")
	_check(hauler.dump_retry_cooldown > 0.0, "dump_retry_cooldown asetettiin uudelleenyritysta varten")

	# _assign_hauler ei hae uutta tyota kesken cooldownin (kuorma jaa odottamaan).
	bm._assign_hauler(hauler)
	_check(hauler.state == Bot.BotState.IDLE, "hauler pysyy IDLEna cooldownin aikana (ei uutta pickup/dig-hakua)")
	_check(hauler.cargo_total == 30, "kuorma ei kadonnut cooldownin aikana")

	# Kun cooldown on kulunut loppuun, seuraava _assign_hauler yrittaa dumpata uudelleen.
	hauler.dump_retry_cooldown = 0.0
	bm._assign_hauler(hauler)
	_check(hauler.state == Bot.BotState.IDLE, "yritys epaonnistuu edelleen (sama ei-hyvaksyva vyohyke) -> jaa IDLEen")
	_check(hauler.dump_retry_cooldown > 0.0, "cooldown asetettiin uudelleen epaonnistuneen uusintayrityksen jalkeen")


# --- A4/B1: dig_sites ei pudota kasoja joissa on viela materiaalia -----------

func _test_dig_site_fifo_keeps_nonempty_piles() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	# Yksi dig_site jossa oikeasti on materiaalia jaljella (DIRT-kasa solun alla).
	var live_cell := Vector2i(5, 5)
	_fill_rect(w, live_cell.x * DCELL, live_cell.y * DCELL, DCELL, DCELL, MAT_DIRT)
	bm._add_dig_site(live_cell)
	# Tayta katon yli (+1, 20x20-lohko = MAX_DIG_SITES tyhjaa solua, ei materiaalia alla,
	# gridin sisalla) -> pakottaa TASMALLEEN yhden siivouskierroksen (nopea testi).
	for i in 20:
		for j in 20:
			bm._add_dig_site(Vector2i(10 + i, 10 + j))
	_check(bm.dig_sites.has(live_cell), "materiaalia sisaltava dig_site EI pudonnut listalta taytosta huolimatta")
	_check(bm.dig_sites.size() <= bm.MAX_DIG_SITES, "dig_sites-lista pysyy katon alla siivouksen jalkeen (%d <= %d)" % [bm.dig_sites.size(), bm.MAX_DIG_SITES])


# --- Regressio: hauler kerää YHDEN solun kuopan viereisista kiviseinista huolimatta ----

# Bugi: kun designoi vain yhden blokin, kerääjä ei tullut keraamaan saalista. Syy: _find_pile
# luki viereisten LOUHIMATTOMIEN kiviseinien (PILE_SCAN_HALF_W = 4 px marginaali molemmin puolin)
# olevan "lattia" -> katkaisi sarakeskannauksen heti ensimmaiseen gravel-riviin -> aliarvioi
# kasan (esim. 3 px) alle PILE_MIN_PX:n -> _assign_hauler_dig poisti dig_siten tyhjana eika
# hauler koskaan mennyt. Leveassa kaivannossa kasan vieressa on tyhjaa, joten bugi ei nakynyt.
# Fix: lattia tunnistetaan VAIN solun omasta sarakkeesta, ei seinamarginaalista.
func _test_hauler_collects_single_cell_between_walls() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	var dx := 40
	var dy := 25
	var cx0 := dx * DCELL          # 640 — solun oma sarake
	var y0 := dy * DCELL           # 400 — solun ylareuna
	# Kiviperusta: leveat seinat molemmin puolin + lattia solun alle. Ylapuoli jaa tyhjaksi (taivas).
	_fill_rect(w, cx0 - 32, y0, DCELL + 64, DCELL + 32, MAT_STONE)
	# Louhi solu kuopaksi ja tayta realistinen settlingin-jalkeinen gravel-kasa:
	#   ylin 4 rivia tyhjaa (gravel valunut alas), rivi 4 vain 3 px (kasan HARVA karki, joka
	#   laukaisi vanhan <PILE_MIN_PX-bugin), loput rivit taynna.
	for yy in DCELL:
		for xx in DCELL:
			w.grid[(y0 + yy) * SIM_W + (cx0 + xx)] = MAT_EMPTY
	var expected_gravel := 0
	for yy in range(4, DCELL):
		var fill := 3 if yy == 4 else DCELL
		for xx in fill:
			w.grid[(y0 + yy) * SIM_W + (cx0 + xx)] = MAT_GRAVEL
			expected_gravel += 1
	w.nav.rebuild_full(w.grid)

	# 1) _find_pile ei saa katketa seiniin: laskee KOKO kasan, ei vain harvaa karkirivia.
	var pile := bm._find_pile(dx, dy)
	_check(int(pile["count"]) == expected_gravel,
		"_find_pile laskee koko kasan (%d), ei katkea kiviseiniin — sai %d" % [expected_gravel, int(pile["count"])])
	_check(int(pile["count"]) >= bm.PILE_MIN_PX, "kasa ylittaa PILE_MIN_PX-kynnyksen (%d)" % int(pile["count"]))

	# 2) Hauler saa tyon kuopalta EIKA dig_sitea poisteta tyhjana.
	bm._add_dig_site(Vector2i(dx, dy))
	var hauler := bm.add_bot(Bot.Role.HAULER, Vector2(float(cx0 + 8), float(y0 - 40)))
	var ok := bm._assign_hauler_dig(hauler)
	_check(ok, "hauler sai tyon yhden solun kuopalta (ei hylkaa dig_sitea)")
	_check(bm.dig_sites.has(Vector2i(dx, dy)), "dig_sitea EI poistettu tyhjana (kasa on oikeasti taynna)")
	_check(hauler.state == Bot.BotState.MOVE, "hauler siirtyi MOVE-tilaan kohti kasaa")


# --- A4/B2: assign-tikki skaalautuu (ei koko gridin skannausta per botti) ----

# Karkea suorituskykysavy: 20 bottia + laaja designaatioalue ei saa hidastua rajusti
# (frontier-cache: yksi 6240-solun skannaus/kierros, ei 20*6240). Generoisen marginaalin
# takia raja on lyalla (50 ms) ettei testi ole herkka hitaalle CI-koneelle, mutta paljastaa
# selvan O(n * grid)-regression jos frontier-cache poistuu kaytosta.
func _test_assignment_scales_with_many_bots() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	# Iso avoin designaatioalue (louhittavissa heti, kaikki QUEUED avoimella pinnalla).
	w.desig.paint_px_rect(Rect2i(0, 0, SIM_W, DCELL * 4), true)
	w.nav.rebuild_full(w.grid)  # avoin (EMPTY) -> kaikki OPEN
	for i in 20:
		bm.add_bot(Bot.Role.MINER, Vector2(float(i * 20), 10.0))

	var t0 := Time.get_ticks_usec()
	bm._run_assignment()
	var elapsed_ms := float(Time.get_ticks_usec() - t0) / 1000.0
	print("  (info) 20 botin _run_assignment kesti %.3f ms" % elapsed_ms)
	_check(elapsed_ms < 50.0, "20 botin assign-tikki pysyy jarkevissa rajoissa (<50 ms), kesti %.3f ms" % elapsed_ms)


# --- Kerros 1: kohteiden hajautus ---------------------------------------------

# Kaksi dig_sitea kasoineen (molemmat pieni, kapasiteetti 1), kaksi idle-hauleria samassa
# pisteessa -> yhden _run_assignment-kierroksen jalkeen haulerit hajautuvat ERI kasoille
# (ensimmainen nappaa lahimman, toinen pakotetaan seuraavaan koska lahin on jo taynna).
func _test_haulers_spread_over_piles() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	# Kaksi pienta DIRT-kasaa (24 px kumpikin -> kapasiteetti ceil(24/40)=1).
	var cell_a := Vector2i(20, 20)
	var cell_b := Vector2i(30, 20)
	_fill_rect(w, cell_a.x * DCELL, cell_a.y * DCELL, 6, 4, MAT_DIRT)
	_fill_rect(w, cell_b.x * DCELL, cell_b.y * DCELL, 6, 4, MAT_DIRT)
	w.nav.rebuild_full(w.grid)
	bm._add_dig_site(cell_a)
	bm._add_dig_site(cell_b)
	# Molemmat haulerit SAMASSA pisteessa, lahempana kasaa A -> ilman hajautusta molemmat A:han.
	var hpos := Vector2(float(cell_a.x * DCELL + 8), float(cell_a.y * DCELL - 40))
	var h1 := bm.add_bot(Bot.Role.HAULER, hpos)
	var h2 := bm.add_bot(Bot.Role.HAULER, hpos)

	bm._run_assignment()
	_check(h1.state == Bot.BotState.MOVE, "hauler 1 sai tyon (MOVE)")
	_check(h2.state == Bot.BotState.MOVE, "hauler 2 sai tyon (MOVE)")
	_check(h1.target_cell != h2.target_cell,
		"haulerit hajautuivat eri kasoille (h1=%s, h2=%s)" % [str(h1.target_cell), str(h2.target_cell)])


# Yksi pieni kasa (36 px -> kapasiteetti 1), kaksi hauleria -> vain yksi saa tyon,
# toinen jaa IDLEen (kapasiteettikatto estaa ruuhkautumisen samaan kasaan).
func _test_small_pile_limits_claims() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	var cell := Vector2i(25, 25)
	_fill_rect(w, cell.x * DCELL, cell.y * DCELL, 6, 6, MAT_DIRT)  # 36 px -> capacity 1
	w.nav.rebuild_full(w.grid)
	bm._add_dig_site(cell)
	var hpos := Vector2(float(cell.x * DCELL + 8), float(cell.y * DCELL - 40))
	var h1 := bm.add_bot(Bot.Role.HAULER, hpos)
	var h2 := bm.add_bot(Bot.Role.HAULER, hpos)

	bm._run_assignment()
	var moving := int(h1.state == Bot.BotState.MOVE) + int(h2.state == Bot.BotState.MOVE)
	var idle := int(h1.state == Bot.BotState.IDLE) + int(h2.state == Bot.BotState.IDLE)
	_check(moving == 1, "pienesta kasasta vain yksi hauler sai tyon (MOVE=%d)" % moving)
	_check(idle == 1, "toinen hauler jai IDLEen (kapasiteettikatto), IDLE=%d" % idle)


# Iso kasa (150 px -> kapasiteetti 3) ainoana kohteena, kaksi hauleria -> MOLEMMAT saavat
# saman kasan (iso kasa kestaa useamman hakijan).
func _test_big_pile_allows_multiple_claims() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	var cell := Vector2i(25, 25)
	_fill_rect(w, cell.x * DCELL, cell.y * DCELL, 15, 10, MAT_DIRT)  # 150 px -> capacity 3
	w.nav.rebuild_full(w.grid)
	bm._add_dig_site(cell)
	var hpos := Vector2(float(cell.x * DCELL + 8), float(cell.y * DCELL - 40))
	var h1 := bm.add_bot(Bot.Role.HAULER, hpos)
	var h2 := bm.add_bot(Bot.Role.HAULER, hpos)

	bm._run_assignment()
	_check(h1.state == Bot.BotState.MOVE and h2.state == Bot.BotState.MOVE,
		"molemmat haulerit saivat tyon isosta kasasta")
	_check(h1.target_cell == cell and h2.target_cell == cell,
		"molemmat kohdistuivat samaan isoon kasaan (h1=%s, h2=%s)" % [str(h1.target_cell), str(h2.target_cell)])


# Vaakarivi QUEUED-frontier-soluja, kaksi mineria samassa pisteessa -> ruuhkasakko tyontaa
# toisen kauemmas: kohteiden Chebyshev-etaisyys >= 2 (ilman sakkoa ne olisivat vierekkain, cheby 1).
func _test_miners_spread_frontier() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	# Avoin maailma (kaikki EMPTY -> nav kaikki OPEN) + vaakarivi QUEUED-soluja dy=20.
	w.nav.rebuild_full(w.grid)
	var dy := 20
	for dx in range(24, 37):
		w.desig.set_cell(dx, dy, D_QUEUED)
	# Molemmat minerit SAMASSA pisteessa solussa (30,20).
	var mpos := Vector2(float(30 * DCELL + 8), float(dy * DCELL + 8))
	var m1 := bm.add_bot(Bot.Role.MINER, mpos)
	var m2 := bm.add_bot(Bot.Role.MINER, mpos)

	bm._run_assignment()
	_check(m1.state == Bot.BotState.MOVE, "miner 1 sai kohteen (MOVE)")
	_check(m2.state == Bot.BotState.MOVE, "miner 2 sai kohteen (MOVE)")
	var cheby := maxi(absi(m1.target_cell.x - m2.target_cell.x), absi(m1.target_cell.y - m2.target_cell.y))
	_check(cheby >= 2,
		"minerien kohteet hajautuivat (Chebyshev >= 2, sai %d: m1=%s, m2=%s)" % [cheby, str(m1.target_cell), str(m2.target_cell)])


# --- Kerros 2: separation-tyonto + ruuhkakerroin -----------------------------

# Kaksi bottia TASMALLEEN samassa pisteessa. world.base = null -> _st_idle ei liikuta,
# vain separation vaikuttaa -> muutaman tickin jalkeen etaisyys > 0, aarellinen (ei NaN),
# ja tulos deterministinen (sama etaisyys kahdella identtisella ajolla, ei randf:aa).
func _test_separation_diverges_overlapping_bots() -> void:
	var dist_a := _run_overlap_sim()
	var dist_b := _run_overlap_sim()
	_check(dist_a > 0.0, "paallekkaiset botit erkanivat (etaisyys %.4f > 0)" % dist_a)
	_check(is_finite(dist_a), "erkaantumisen tulos on aarellinen (ei NaN/inf)")
	_check(absf(dist_a - dist_b) < 1e-6,
		"erkaantuminen deterministinen (%.6f == %.6f)" % [dist_a, dist_b])


# Ajaa kaksi paallekkaista IDLE-bottia 8 tickia ilman basea ja palauttaa lopullisen etaisyyden.
func _run_overlap_sim() -> float:
	var w := _make_world()
	w.base = null
	var bm := BotManager.new()
	bm.setup(w)
	var b0 := bm.add_bot(Bot.Role.MINER, Vector2(600.0, 600.0))
	var b1 := bm.add_bot(Bot.Role.MINER, Vector2(600.0, 600.0))
	for _i in 8:
		bm.tick(0.067)
	return b0.pos.distance_to(b1.pos)


# Botti keskella tiheaa rypasta (8 naapuria samalla puolella -> raaka tyonto ylittaa katon).
# Yhden tickin siirtyma <= move_speed * SEP_FACTOR * delta + epsilon (push.limit_length(1) kattaa).
# world.base = null -> _st_idle ei liikuta, joten mitattu siirtyma on puhtaasti separationia.
func _test_separation_push_capped() -> void:
	var w := _make_world()
	w.base = null
	var bm := BotManager.new()
	bm.setup(w)
	var center := bm.add_bot(Bot.Role.MINER, Vector2(500.0, 500.0))
	# 8 naapuria kaikki +x-puolella (SEP_RADIUS=12 sisalla) -> nettotyonto -x, raaka pituus > 1.
	var offs := [Vector2(2, 0), Vector2(3, 0), Vector2(4, 0), Vector2(2, 2),
			Vector2(3, 2), Vector2(2, -2), Vector2(3, -2), Vector2(4, 1)]
	for off in offs:
		bm.add_bot(Bot.Role.MINER, Vector2(500.0, 500.0) + off)
	bm._build_crowd_index()
	var before := center.pos
	var delta := 0.067
	bm._update_bot(center, delta)
	var moved := before.distance_to(center.pos)
	var cap := center.move_speed() * bm.SEP_FACTOR * delta
	_check(moved <= cap + 0.001,
		"separation-tyonto ei ylita kattoa (siirtyma %.4f <= %.4f)" % [moved, cap])
	_check(moved > 0.0, "epasymmetrinen rypas aiheutti tyonnon (%.4f > 0)" % moved)


# _crowd_factor-kayra: 1 naapuri -> 1.0; 2 -> ~0.714; iso ryhma -> lattia 0.25.
# Monotonisesti ei-kasvava naapurimaaran kasvaessa.
func _test_crowd_factor_curve() -> void:
	var w := _make_world()
	w.base = null
	var bm := BotManager.new()
	bm.setup(w)
	var center := bm.add_bot(Bot.Role.MINER, Vector2(400.0, 400.0))
	# 1 naapuri -> 1.0
	bm.add_bot(Bot.Role.MINER, Vector2(400.0, 400.0))
	bm._build_crowd_index()
	var f1 := bm._crowd_factor(center)
	_check(absf(f1 - 1.0) < 0.01, "1 naapuri -> factor ~1.0 (sai %.3f)" % f1)
	# 2 naapuria -> ~0.714
	bm.add_bot(Bot.Role.MINER, Vector2(400.0, 400.0))
	bm._build_crowd_index()
	var f2 := bm._crowd_factor(center)
	_check(absf(f2 - 0.714) < 0.01, "2 naapuria -> factor ~0.714 (sai %.3f)" % f2)
	# Iso ryhma (12 naapuria) -> lattia 0.25
	for _i in 10:
		bm.add_bot(Bot.Role.MINER, Vector2(400.0, 400.0))
	bm._build_crowd_index()
	var fbig := bm._crowd_factor(center)
	_check(absf(fbig - 0.25) < 0.01, "iso ryhma -> lattia 0.25 (sai %.3f)" % fbig)
	_check(f1 >= f2 and f2 >= fbig,
		"factor monotonisesti ei-kasvava (%.3f >= %.3f >= %.3f)" % [f1, f2, fbig])


# --- Kerros 3: ajallinen dumppi + ruuhkakerroin imussa ------------------------

# Ajallinen dumppi: taysi kuorma EI tyhjene yhdessa tikissa, vaan valuu monotonisesti
# useiden tikkien yli, ja lopputulos on oikein (kaikki px kirjoitetaan dump-alueelle).
func _test_timed_dump_drains_over_time() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	bm.logistics = Logistics.new()
	# Iso dump-vyohyke joka hyvaksyy DIRTin (mahtuu koko kuorma reilusti).
	var dump_rect := Rect2i(1000, 500, 30, 30)
	bm.logistics.add_dump_point(dump_rect, 1 << MAT_DIRT)
	var b := bm.add_bot(Bot.Role.HAULER, Vector2(1015.0, 515.0))
	b.add_cargo(MAT_DIRT, 40)
	b.dump_target = bm.logistics.choose_dump(b.cargo, b.pos)
	b.state = Bot.BotState.DUMP
	b.work_accum = 0.0
	var start_total := b.cargo_total  # 40

	# Ensimmainen tikki purkaa vain OSAN (DUMP_RATE 80 * 0.1 = 8 px), ei koko kuormaa.
	bm._st_dump(b, 0.1)
	_check(b.cargo_total > 0 and b.cargo_total < start_total,
		"ensimmainen tikki purki VAIN osan kuormasta (%d/%d jaljella)" % [b.cargo_total, start_total])

	# Loput tikit: kuorma tyhjenee monotonisesti (ei koskaan kasva) ja paatyy nollaan.
	var prev := b.cargo_total
	var monotone := true
	for _t in 100:
		if b.state != Bot.BotState.DUMP:
			break
		bm._st_dump(b, 0.1)
		if b.cargo_total > prev:
			monotone = false
		prev = b.cargo_total
	_check(monotone, "kuorma tyhjeni monotonisesti (ei kasvanut valissa)")
	_check(b.cargo_total == 0, "kuorma tyhjeni lopulta kokonaan")
	_check(b.state == Bot.BotState.IDLE, "botti palasi IDLEen dumpin jalkeen")

	# Kaikki 40 DIRT-px kirjoitettiin dump-alueelle (ei myyty baseen: alue riittava).
	var found := 0
	for y in range(dump_rect.position.y, dump_rect.position.y + dump_rect.size.y):
		for x in range(dump_rect.position.x, dump_rect.position.x + dump_rect.size.x):
			if w.grid[y * SIM_W + x] == MAT_DIRT:
				found += 1
	_check(found == start_total, "kaikki %d DIRT-px kirjoitettiin dump-alueelle, loytyi %d" % [start_total, found])
	_check(w.money == 0, "riittava dump-alue -> mitaan ei myyty baseen (money 0), sai %d" % w.money)


# Kohde tayttyy kesken purun: osa kuormasta kirjoitetaan alueelle, LOPUT myydaan baseen.
# Sailyvyysinvariantti: sijoitetut px + myydyt px == alkuperainen kuorma (mikaan ei katoa).
func _test_dump_cargo_conserved_when_destination_full() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	bm.logistics = Logistics.new()
	# Pieni 3x3 dump-alue (9 solua); esitaytetaan 4 solua STONElla -> tilaa tasan 5 DIRT-px.
	var dump_rect := Rect2i(1000, 500, 3, 3)
	bm.logistics.add_dump_point(dump_rect, 1 << MAT_DIRT)
	var filled := 0
	for yy in range(dump_rect.position.y, dump_rect.position.y + dump_rect.size.y):
		for xx in range(dump_rect.position.x, dump_rect.position.x + dump_rect.size.x):
			if filled < 4:
				w.grid[yy * SIM_W + xx] = MAT_STONE
				filled += 1
	var b := bm.add_bot(Bot.Role.HAULER, Vector2(1001.0, 501.0))
	b.add_cargo(MAT_DIRT, 20)
	b.dump_target = bm.logistics.choose_dump(b.cargo, b.pos)
	b.state = Bot.BotState.DUMP
	b.work_accum = 0.0
	w.money = 0
	var start_total := b.cargo_total  # 20

	for _t in 100:
		if b.state != Bot.BotState.DUMP:
			break
		bm._st_dump(b, 0.1)
	_check(b.cargo_total == 0, "kuorma purkautui kokonaan (osa alueelle, loput myyty)")

	var placed := 0
	for yy in range(dump_rect.position.y, dump_rect.position.y + dump_rect.size.y):
		for xx in range(dump_rect.position.x, dump_rect.position.x + dump_rect.size.x):
			if w.grid[yy * SIM_W + xx] == MAT_DIRT:
				placed += 1
	var sold := w.money  # DIRT = 1 $/px -> myydyt px == money
	_check(placed == 5, "vapaisiin 5 soluun kirjoitettiin 5 DIRT-px, loytyi %d" % placed)
	_check(placed + sold == start_total,
		"kuorma sailyi: sijoitetut %d + myydyt %d == alkuperainen %d" % [placed, sold, start_total])


# Turvavahti: jos dump kestaa yli DUMP_MAX_TIME, jaljella oleva kuorma MYYDAAN baseen ja
# botti palaa IDLEen. Kuorma ei katoa (koko jaannos rahaksi).
func _test_dump_watchdog_sells_leftover() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	bm.logistics = Logistics.new()
	var dump_rect := Rect2i(1000, 500, 30, 30)
	bm.logistics.add_dump_point(dump_rect, 1 << MAT_DIRT)
	var b := bm.add_bot(Bot.Role.HAULER, Vector2(1015.0, 515.0))
	b.add_cargo(MAT_DIRT, 30)
	b.dump_target = bm.logistics.choose_dump(b.cargo, b.pos)
	b.state = Bot.BotState.DUMP
	# Pakota watchdog: state_timer keinotekoisesti yli DUMP_MAX_TIMEn.
	b.state_timer = bm.DUMP_MAX_TIME + 1.0
	w.money = 0
	var start_total := b.cargo_total  # 30

	bm._st_dump(b, 0.1)
	_check(b.cargo_total == 0, "watchdog myi jaljella olevan kuorman (cargo tyhja)")
	_check(b.state == Bot.BotState.IDLE, "watchdog palautti botin IDLEen")
	_check(w.money == start_total,
		"koko kuorma (%d DIRT) myytiin baseen watchdogissa, sai %d" % [start_total, w.money])
	# Watchdog myy suoraan -> mitaan ei kirjoitettu dump-alueelle.
	var placed := 0
	for y in range(dump_rect.position.y, dump_rect.position.y + dump_rect.size.y):
		for x in range(dump_rect.position.x, dump_rect.position.x + dump_rect.size.x):
			if w.grid[y * SIM_W + x] == MAT_DIRT:
				placed += 1
	_check(placed == 0, "watchdog ei kirjoittanut mitaan dump-alueelle (myi suoraan), loytyi %d" % placed)


# Ruuhkakerroin imussa: hauler imuroi isoa kasaa. Yksin N tikissa poimittu maara > sama
# maara kun 4 idle-bottia on pysakoity CONGEST_RADIUSin sisaan (ruuhka hidastaa imua).
func _test_vacuum_slows_under_congestion() -> void:
	var solo := _run_vacuum_pick(0)     # ei naapureita
	var crowded := _run_vacuum_pick(4)  # 4 idle-bottia paalle (CONGEST_RADIUS sisaan)
	_check(solo > crowded,
		"ruuhka hidastaa imua (yksin %d px > ruuhkassa %d px)" % [solo, crowded])
	_check(crowded > 0, "ruuhkassakin imu etenee (lattia CONGEST_FLOOR), sai %d" % crowded)


# --- P0-1: idle-syyn johtaminen (get_fleet_stats["bots"][i]["idle_reason"]) -----

# Apuri: hae botin idle_reason id:lla get_fleet_statsista.
func _bot_reason(stats: Dictionary, id: int) -> int:
	for b in stats["bots"]:
		if int(b["id"]) == id:
			return int(b["idle_reason"])
	return -1


# Miner-idle-syy johdetaan tyonjaon tilannekuvasta (EI pysyvaa tilaa):
#   - ei designaatiota            -> NO_QUEUED
#   - designaatio HAUDATTU (umpikivessa, ei OPEN-naapuria, frontier tyhja) -> ALL_BLOCKED
#   - navnaapuri aukeaa -> frontier saa solun -> OK
# Hauler-idle-syy: ei kerattavaa -> NO_LOOSE; dig_site tarjolla -> OK.
func _test_idle_reason_derivation() -> void:
	var w := _make_world()
	# Umpikivi 128x128 (px 256..384), nav-linjattu. Sama kuin blocked-reactivate-testissa.
	_fill_rect(w, 256, 256, 128, 128, MAT_STONE)
	w.nav.rebuild_full(w.grid)
	var bm := BotManager.new()
	bm.setup(w)
	var miner := bm.add_bot(Bot.Role.MINER, Vector2(320, 200))  # IDLE oletuksena

	# 1) Ei yhtaan designaatiota -> NO_QUEUED.
	bm._scan_designations()
	var stats := bm.get_fleet_stats()
	_check(_bot_reason(stats, miner.id) == bm.IDLE_REASON_NO_QUEUED,
		"idle miner ilman designaatiota -> NO_QUEUED (sai %d)" % _bot_reason(stats, miner.id))
	_check(not bool(stats["any_designation"]), "any_designation=false kun ei designaatiota")

	# 2) Haudattu designaatio (umpikiven sisalla, ei OPEN-naapuria) -> ALL_BLOCKED.
	var dx := 19
	var dy := 19
	w.desig.set_cell(dx, dy, D_QUEUED)
	bm._scan_designations()
	_check(w.desig.get_cell(dx, dy) == D_BLOCKED, "haudattu QUEUED-solu -> BLOCKED skannauksessa")
	stats = bm.get_fleet_stats()
	_check(int(stats["desig_blocked"]) >= 1, "get_fleet_stats raportoi BLOCKED-solun (sai %d)" % int(stats["desig_blocked"]))
	_check(int(stats["frontier"]) == 0, "frontier tyhja (ei tavoitettavaa solua)")
	_check(_bot_reason(stats, miner.id) == bm.IDLE_REASON_ALL_BLOCKED,
		"idle miner + kaikki designaatiot BLOCKED -> ALL_BLOCKED (sai %d)" % _bot_reason(stats, miner.id))

	# 3) Avaa yksi navnaapuri -> solu palautuu QUEUEDiksi ja tulee frontieriin -> OK.
	_fill_rect(w, 304, 288, 16, 16, MAT_EMPTY)
	w.nav.mark_dirty_px_rect(Rect2i(304, 288, 16, 16))
	w.nav.update_dirty(w.grid)
	bm._scan_designations()
	stats = bm.get_fleet_stats()
	_check(int(stats["frontier"]) >= 1, "navnaapurin avaus tuo solun frontieriin (sai %d)" % int(stats["frontier"]))
	_check(_bot_reason(stats, miner.id) == bm.IDLE_REASON_OK,
		"idle miner + tavoitettava frontier -> OK (sai %d)" % _bot_reason(stats, miner.id))

	# 4) Hauler ilman kerattavaa -> NO_LOOSE; dig_site lisatty -> OK.
	var hauler := bm.add_bot(Bot.Role.HAULER, Vector2(320, 200))
	stats = bm.get_fleet_stats()
	_check(_bot_reason(stats, hauler.id) == bm.IDLE_REASON_NO_LOOSE,
		"idle hauler ilman kerattavaa -> NO_LOOSE (sai %d)" % _bot_reason(stats, hauler.id))
	bm._add_dig_site(Vector2i(5, 5))
	stats = bm.get_fleet_stats()
	_check(_bot_reason(stats, hauler.id) == bm.IDLE_REASON_OK,
		"idle hauler + dig_site tarjolla -> OK (sai %d)" % _bot_reason(stats, hauler.id))


# Aja hauler imuroimassa isoa kasaa 8 tikkia; palauta poimittu px-maara. extra_bots idle-bottia
# parkkeerataan TASMALLEEN haulerin paalle (etaisyys 0 < CONGEST_RADIUS) tuottamaan ruuhkaa.
func _run_vacuum_pick(extra_bots: int) -> int:
	var w := _make_world()
	var px := 300
	var py := 300
	_fill_rect(w, px - 12, py - 12, 24, 24, MAT_DIRT)  # iso kasa (radius 10 kattaa)
	w.nav.rebuild_full(w.grid)
	var bm := BotManager.new()
	bm.setup(w)
	# Mk3 hauler (carry_cap 180) jottei kuorma tayty kesken mittauksen.
	var b := bm.add_bot(Bot.Role.HAULER, Vector2(float(px), float(py)))
	b.tier = 3
	b.pickup_pos = Vector2(float(px), float(py))
	b.state = Bot.BotState.WORK
	b.work_accum = 0.0
	for _i in extra_bots:
		bm.add_bot(Bot.Role.HAULER, Vector2(float(px), float(py)))
	bm._build_crowd_index()
	for _t in 8:
		bm._work_vacuum(b, 0.1)
	return b.cargo_total
