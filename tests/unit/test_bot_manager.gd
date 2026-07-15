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
	_test_buy_bot_price_and_spawn()
	_test_set_role_interrupts_claim_and_dumps_cargo()
	_test_upgrade_bot_tiers()
	_test_get_fleet_stats()
	_test_hauler_routes_to_dump_zone_when_base_filter_denies()
	_test_dig_site_fifo_keeps_nonempty_piles()
	_test_assignment_scales_with_many_bots()
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


# --- A1: Osto & nouseva hinta ------------------------------------------------

# next_bot_price(): 300 * 1.5^n pyoristettyna alas 10:een, n = ostetut (aloitus-2 ei laske).
# buy_bot(): tarkistaa varan, vahentaa rahan, spawnaa world.base.spawn_pos():iin.
func _test_buy_bot_price_and_spawn() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	# Alkutila: 2 aloitusbottia EIVAT ole ostettuja -> ensimmainen osto on silti hinnalla 300.
	bm.add_bot(Bot.Role.MINER, Vector2(10, 10))
	bm.add_bot(Bot.Role.HAULER, Vector2(20, 10))
	_check(bm.next_bot_price() == 300, "ensimmaisen ostettavan botin hinta on 300 (aloitusbotit eivat kasvata), sai %d" % bm.next_bot_price())

	# Ei varaa -> osto epaonnistuu, raha ja bottimaara ennallaan.
	w.money = 299
	var before_count := bm.bot_count()
	_check(bm.buy_bot(Bot.Role.MINER) == false, "buy_bot palauttaa false kun raha ei riita")
	_check(bm.bot_count() == before_count, "epaonnistunut osto ei spawnaa bottia")
	_check(w.money == 299, "epaonnistunut osto ei vahenna rahaa")

	# Riittava raha -> osto onnistuu, raha vahenee, botti ilmestyy basen spawn_pos:iin.
	w.money = 300
	_check(bm.buy_bot(Bot.Role.MINER) == true, "buy_bot onnistuu kun raha riittaa")
	_check(w.money == 0, "osto vahensi rahan tasan hinnan verran")
	_check(bm.bot_count() == before_count + 1, "botti lisattiin laumaan")
	var spawned: Bot = bm.bots[bm.bots.size() - 1]
	_check(spawned.pos.is_equal_approx(w.base.spawn_pos()), "uusi botti spawnasi basen spawn_pos:iin")

	# Nouseva hinta: 2. ostettu botti (n=1) -> 300*1.5=450.
	_check(bm.next_bot_price() == 450, "toisen ostetun botin hinta nousee 450:een (1.5x), sai %d" % bm.next_bot_price())
	w.money = 450
	_check(bm.buy_bot(Bot.Role.HAULER) == true, "toinen osto onnistuu 450:lla")
	# 3. ostettu botti (n=2) -> 300*1.5^2 = 675 -> alaspain 10:een = 670.
	_check(bm.next_bot_price() == 670, "kolmannen ostetun botin hinta 670 (675 pyoristetty alas 10:een), sai %d" % bm.next_bot_price())


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


# --- A3: Hauler vie dump-vyohykkeelle kun base-filtteri kieltaa materiaalin --

# GDD §4.2: hauler valitsee dumpin joka hyvaksyy suurimman osan kuormasta ja on lahinna.
# Base-filtteri kieltaa IRON_ORE:n (hyvaksyy vain DIRT) -> hauler ohjautuu dump-vyohykkeelle
# jonka filtteri hyvaksyy IRON_ORE:n, silla base_acc=0 mutta dump_acc=cargo_total.
func _test_hauler_routes_to_dump_zone_when_base_filter_denies() -> void:
	var w := _make_world()
	var bm := BotManager.new()
	bm.setup(w)
	bm.logistics = Logistics.new()
	bm.logistics.set_base_filter(1 << MAT_DIRT)  # base hyvaksyy VAIN DIRTin

	# Dump-vyohyke joka hyvaksyy IRON_ORE:n, sijoitettu basesta erilleen (ei paalla structure_pixels).
	var dump_rect := Rect2i(1000, 500, 20, 20)
	var dump_id := bm.logistics.add_dump_point(dump_rect, 1 << MAT_IRON_ORE)

	var hauler := bm.add_bot(Bot.Role.HAULER, Vector2(1100, 100))
	hauler.add_cargo(MAT_IRON_ORE, 30)

	bm._start_dump(hauler)
	_check(String(hauler.dump_target.get("kind", "")) == "dump", "hauler valitsee dump-vyohykkeen kun base-filtteri kieltaa IRON_ORE:n")
	_check(int(hauler.dump_target.get("id", -1)) == dump_id, "dump_target.id vastaa rekisteroityä dump-pointin id:ta")
	var chosen_rect: Rect2i = hauler.dump_target.get("rect", Rect2i())
	_check(chosen_rect == dump_rect, "valittu dump-alue vastaa rekisteroityä dump-pointtia")

	# Aja purku loppuun: kuljeta perille (path tyhjaksi) ja pura.
	hauler.path = PackedVector2Array()
	hauler.path_idx = 0
	hauler.pos = Vector2(chosen_rect.position) + Vector2(chosen_rect.size) * 0.5
	w.money = 0
	bm._st_dump(hauler, 0.0)
	_check(hauler.cargo_total == 0, "kuorma purkautui")
	_check(w.money == 0, "IRON_ORE EI mennyt baseen rahaksi (base-filtteri kielsi)")
	# Kirjoitetut pikselit loytyvat dump-alueelta IRON_ORE-materiaalina (kone/pickup poimii ne myohemmin).
	var found_ore := 0
	for y in range(dump_rect.position.y, dump_rect.position.y + dump_rect.size.y):
		for x in range(dump_rect.position.x, dump_rect.position.x + dump_rect.size.x):
			if w.grid[y * SIM_W + x] == MAT_IRON_ORE:
				found_ore += 1
	_check(found_ore == 30, "kaikki 30 IRON_ORE-pikselia kirjoitettiin dump-alueelle, loytyi %d" % found_ore)


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
