extends SceneTree

# Yksikkotestit M3-lataukselle (scripts/charger.gd + bot_manager.gd:n lataustilakone).
# Kattaa:
#   - charge_rate: trickle (coal_buffer=0) vs coal-buusti (coal_buffer>0)
#   - feed_coal: puskuri kasvaa COAL_UNITS_PER_PX:lla; ei-positiivinen syotto on no-op
#   - slot_pos: rajatarkistus (ulkopuolella -> ensimmainen; tyhja -> ZERO)
#   - slot-varaus: 1 slotti + 2 matala-akku-bottia -> yksi SEEK_CHARGE, toinen WAITING_CHARGER
#   - varausvuoto: abortoinut botti vapauttaa slotin (miehitys JOHDETAAN tilasta, ei laskurista)
#   - lataus: akku nousee, coal_buffer kuluu VAIN buustatusta osuudesta, loppuu FULL_ENOUGHiin
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_charger.gd

const SIM_W := 1664
const SIM_H := 960
const MAT_EMPTY := 0

var _pass := 0
var _fail := 0


# --- Kevyt fake-world: BotManager tarvitsee vain nav:in (_seek_charge reitittaa) + get():n. ---
class FakeWorld extends Node:
	var grid: PackedByteArray
	var nav: NavGrid
	var desig: DesignationGrid
	var base: MoneyExit

	func _init() -> void:
		grid = PackedByteArray()
		grid.resize(SIM_W * SIM_H)
		grid.fill(MAT_EMPTY)
		nav = NavGrid.new()
		nav.rebuild_full(grid)   # koko kentta OPEN -> find_path_px ei kaadu
		desig = DesignationGrid.new()


func _init() -> void:
	print("=== CHARGER-TESTIT (M3) ===\n")
	_test_charge_rate_trickle_vs_coal()
	_test_feed_coal_units_and_noop()
	_test_slot_pos_bounds()
	_test_slot_reservation_one_slot_two_bots()
	_test_reservation_no_leak_after_abort()
	_test_charging_raises_battery_and_burns_coal()
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


func _make_bm() -> BotManager:
	var w := FakeWorld.new()
	var bm := BotManager.new()
	bm.setup(w)
	return bm


# charge_rate(): ilman hiilta trickle (1.5), hiilella coal-buusti (9.0).
func _test_charge_rate_trickle_vs_coal() -> void:
	var c := Charger.new()
	_check(absf(c.charge_rate() - BotManager.CHARGE_TRICKLE) < 0.001,
		"charge_rate = CHARGE_TRICKLE (%.1f) kun coal_buffer=0, sai %.2f" % [BotManager.CHARGE_TRICKLE, c.charge_rate()])
	c.coal_buffer = 10.0
	_check(absf(c.charge_rate() - BotManager.CHARGE_COAL) < 0.001,
		"charge_rate = CHARGE_COAL (%.1f) kun coal_buffer>0, sai %.2f" % [BotManager.CHARGE_COAL, c.charge_rate()])


# feed_coal(px): coal_buffer += px * COAL_UNITS_PER_PX; px<=0 on no-op.
func _test_feed_coal_units_and_noop() -> void:
	var c := Charger.new()
	c.feed_coal(2)
	var expected := 2.0 * BotManager.COAL_UNITS_PER_PX
	_check(absf(c.coal_buffer - expected) < 0.001,
		"feed_coal(2) -> coal_buffer = 2*%.0f = %.0f, sai %.1f" % [BotManager.COAL_UNITS_PER_PX, expected, c.coal_buffer])
	c.feed_coal(3)
	_check(absf(c.coal_buffer - (5.0 * BotManager.COAL_UNITS_PER_PX)) < 0.001,
		"feed_coal kumuloituu (yht. 5 px), sai %.1f" % c.coal_buffer)
	var before := c.coal_buffer
	c.feed_coal(0)
	c.feed_coal(-5)
	_check(absf(c.coal_buffer - before) < 0.001, "feed_coal(<=0) on no-op (puskuri ennallaan)")


# slot_pos(): rajojen sisalla oikea sijainti, ulkopuolella ensimmainen, tyhja -> ZERO.
func _test_slot_pos_bounds() -> void:
	var c := Charger.new()
	c.slot_positions = [Vector2(10, 20), Vector2(30, 40)]
	_check(c.slot_pos(0) == Vector2(10, 20), "slot_pos(0) = ensimmainen dokkauspiste")
	_check(c.slot_pos(1) == Vector2(30, 40), "slot_pos(1) = toinen dokkauspiste")
	_check(c.slot_pos(5) == Vector2(10, 20), "slot_pos(rajan yli) palauttaa ensimmaisen")
	var c2 := Charger.new()
	_check(c2.slot_pos(0) == Vector2.ZERO, "tyhja slot_positions -> ZERO (degeneroitunut testitapaus)")


# 1 slotti, 2 matala-akku-bottia: ensimmainen varaa slotin (SEEK_CHARGE), toinen jaa
# WAITING_CHARGER-tilaan (pehmea cap). Miehitys johdetaan bottien tilasta.
func _test_slot_reservation_one_slot_two_bots() -> void:
	var bm := _make_bm()
	bm.make_base_charger(Vector2(800.0, 200.0))
	var b1 := bm.add_bot(Bot.Role.MINER, Vector2(810.0, 200.0))
	var b2 := bm.add_bot(Bot.Role.MINER, Vector2(820.0, 200.0))
	b1.battery = 5.0
	b2.battery = 5.0

	bm._seek_charge(b1)
	_check(b1.state == Bot.BotState.SEEK_CHARGE, "eka botti hakeutuu lataukseen (SEEK_CHARGE)")
	_check(b1.charger_slot >= 0, "eka botti varasi slotin (charger_slot=%d)" % b1.charger_slot)

	bm._seek_charge(b2)
	_check(b2.state == Bot.BotState.IDLE, "toka botti jaa IDLEen kun ainoa slotti varattu")
	_check(b2.charger_slot == -1, "toka botti EI varannut slottia (charger_slot=-1)")
	_check(bm._idle_reason_for(b2) == bm.IDLE_REASON_WAITING_CHARGER,
		"toka botti raportoi WAITING_CHARGER-syyn (odottaa vuoroa)")

	# Fleet-stats naytaa jonon M4:n disclosure-triggerille.
	var stats := bm.get_fleet_stats()
	_check(int(stats["charging"]) == 1, "fleet_stats.charging = 1 (eka botti), sai %d" % int(stats["charging"]))
	_check(int(stats["waiting_charger"]) == 1, "fleet_stats.waiting_charger = 1 (toka botti), sai %d" % int(stats["waiting_charger"]))


# Varausvuodon esto: kun varannut botti abortoi (charger_slot -> -1), slotti vapautuu
# valittomasti koska miehitys johdetaan tilasta -> odottava botti saa slotin seuraavalla yrityksella.
func _test_reservation_no_leak_after_abort() -> void:
	var bm := _make_bm()
	bm.make_base_charger(Vector2(800.0, 200.0))
	var b1 := bm.add_bot(Bot.Role.MINER, Vector2(810.0, 200.0))
	var b2 := bm.add_bot(Bot.Role.MINER, Vector2(820.0, 200.0))
	b1.battery = 5.0
	b2.battery = 5.0

	bm._seek_charge(b1)
	bm._seek_charge(b2)
	_check(b1.charger_slot >= 0 and b2.charger_slot == -1, "lahtotila: b1 varasi, b2 odottaa")

	# b1 abortoi (esim. charger katosi / turvavahti) -> slotti vapautuu.
	bm._abort_job(b1)
	_check(b1.charger_slot == -1, "abortoitu botti vapautti varauksensa")

	# b2 yrittaa uudelleen -> saa nyt vapautuneen slotin (ei varausvuotoa).
	bm._seek_charge(b2)
	_check(b2.state == Bot.BotState.SEEK_CHARGE, "odottanut botti sai vapautuneen slotin (SEEK_CHARGE)")
	_check(b2.charger_slot >= 0, "odottanut botti varasi slotin abortin jalkeen")


# CHARGING: akku nousee charge_ratella; coal_buffer kuluu VAIN buustatusta osuudesta
# (rate - CHARGE_TRICKLE); lataus loppuu ja slotti vapautuu kun akku >= BATTERY_FULL_ENOUGH.
func _test_charging_raises_battery_and_burns_coal() -> void:
	var bm := _make_bm()
	var ch := bm.make_base_charger(Vector2(800.0, 200.0))
	var b := bm.add_bot(Bot.Role.MINER, Vector2(800.0, 200.0))
	b.battery = 20.0
	b.charger_slot = bm._global_slot_key(ch, 0)
	b.state = Bot.BotState.CHARGING

	# 1) Trickle (ei hiilta): akku +CHARGE_TRICKLE per sekunti.
	bm._st_charging(b, 1.0)
	_check(absf(b.battery - (20.0 + BotManager.CHARGE_TRICKLE)) < 0.01,
		"trickle-lataus nosti akkua %.1f -> %.2f" % [BotManager.CHARGE_TRICKLE, b.battery])

	# 2) Hiilibuusti: akku +CHARGE_COAL, coal_buffer -= (CHARGE_COAL - CHARGE_TRICKLE) (trickle ilmainen).
	ch.feed_coal(1)                       # coal_buffer = COAL_UNITS_PER_PX
	var coal0 := ch.coal_buffer
	var batt0 := b.battery
	bm._st_charging(b, 1.0)
	_check(absf(b.battery - (batt0 + BotManager.CHARGE_COAL)) < 0.01,
		"hiilibuusti nosti akkua %.1f/s, sai %.2f" % [BotManager.CHARGE_COAL, b.battery])
	var burned := coal0 - ch.coal_buffer
	_check(absf(burned - (BotManager.CHARGE_COAL - BotManager.CHARGE_TRICKLE)) < 0.01,
		"coal_buffer kului vain buustatusta osuudesta (%.1f), sai %.2f" % [BotManager.CHARGE_COAL - BotManager.CHARGE_TRICKLE, burned])
	_check(ch.coal_buffer >= 0.0, "coal_buffer ei mene negatiiviseksi")

	# 3) Taysi lataus: akku ylittaa FULL_ENOUGHin -> IDLE + slotti vapautuu.
	b.battery = BotManager.BATTERY_FULL_ENOUGH - 1.0
	ch.coal_buffer = 0.0
	bm._st_charging(b, 1.0)              # +trickle 1.5 -> yli FULL_ENOUGHin
	_check(b.battery >= BotManager.BATTERY_FULL_ENOUGH, "lataus jatkui FULL_ENOUGHin yli")
	_check(b.state == Bot.BotState.IDLE, "tayteen ladattu botti palasi IDLEen")
	_check(b.charger_slot == -1, "ladattu botti vapautti slotin (charger_slot=-1)")
