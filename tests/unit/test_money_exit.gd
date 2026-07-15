extends SceneTree

# Yksikkotestit MoneyExitin Base-roolille (scripts/money_exit.gd):
# accept_cargo (hinnoittelu PRICES-taulusta), spawn_pos ja intake_pos -geometria.
# Kattaa rajapintakontraktin: accept_cargo EI muuta world-tilaa, palauttaa vain summan.
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_money_exit.gd

const MAT_SAND := 1
const MAT_STONE := 3
const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13
const MAT_GOLD := 15
const MAT_COAL := 16
const MAT_GRAVEL := 18

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== MONEYEXIT-TESTIT ===\n")
	_test_accept_cargo_sums_prices()
	_test_accept_cargo_unknown_material()
	_test_accept_cargo_ignores_nonpositive()
	_test_accept_cargo_empty()
	_test_spawn_and_intake_geometry()
	_test_accept_cargo_increments_earned_total_cumulatively()
	_test_update_exit_increments_earned_total()
	_test_prices_include_copper_and_rare_earth()
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


func _make_base(center: Vector2i) -> MoneyExit:
	var me := MoneyExit.new()
	me.setup(center)
	return me


# Kuorman arvo = summa yksikkohinnoista * maara. DIRT=1, IRON_ORE=3, GOLD=12.
func _test_accept_cargo_sums_prices() -> void:
	var me := _make_base(Vector2i(200, 200))
	var cargo := {MAT_DIRT: 10, MAT_IRON_ORE: 2, MAT_GOLD: 1}
	var total := me.accept_cargo(cargo)
	# 10*1 + 2*3 + 1*12 = 28
	_check(total == 28, "accept_cargo summaa hinnat (10*DIRT + 2*IRON_ORE + 1*GOLD = 28), sai %d" % total)
	me.free()


# Tuntematon materiaali-ID -> DEFAULT_PRICE (1).
func _test_accept_cargo_unknown_material() -> void:
	var me := _make_base(Vector2i(200, 200))
	var total := me.accept_cargo({200: 5})  # 200 ei ole PRICES-taulussa
	_check(total == 5, "tuntematon materiaali hinnoitellaan DEFAULT_PRICElla (5*1=5), sai %d" % total)
	me.free()


# Ei-positiiviset maarat ohitetaan (ei negatiivista rahaa).
func _test_accept_cargo_ignores_nonpositive() -> void:
	var me := _make_base(Vector2i(200, 200))
	var total := me.accept_cargo({MAT_SAND: -3, MAT_STONE: 0, MAT_GRAVEL: 4})
	# vain GRAVEL 4*1 = 4
	_check(total == 4, "negatiivinen/nolla-maara ohitetaan (vain 4*GRAVEL=4), sai %d" % total)
	me.free()


func _test_accept_cargo_empty() -> void:
	var me := _make_base(Vector2i(200, 200))
	_check(me.accept_cargo({}) == 0, "tyhja kuorma -> 0")
	me.free()


# spawn_pos on basen ylapuolella, intake_pos basen ylareunassa, molemmat keskilinjalla.
func _test_spawn_and_intake_geometry() -> void:
	var center := Vector2i(400, 300)
	var me := _make_base(center)
	var sp := me.spawn_pos()
	var ip := me.intake_pos()
	# Sama x-keskilinja
	_check(is_equal_approx(sp.x, ip.x), "spawn_pos ja intake_pos jakavat x-keskilinjan (%.1f vs %.1f)" % [sp.x, ip.x])
	# spawn selvasti intaken ylapuolella (pienempi y)
	_check(sp.y < ip.y - 10.0, "spawn_pos on selvasti intake_pos:n ylapuolella (sp.y=%.1f < ip.y=%.1f)" % [sp.y, ip.y])
	# intake basen ylareunassa (grid_pos.y)
	_check(is_equal_approx(ip.y, float(me.grid_pos.y)), "intake_pos.y = basen ylareuna grid_pos.y")
	me.free()


# earned_total on kumulatiivinen laskuri joka kasvaa JOKAISESTA accept_cargo-kutsusta
# (ei nollaudu, toisin kuin frame_earnings). Lane G laskee tasta liukuvan $/s-mittarin.
func _test_accept_cargo_increments_earned_total_cumulatively() -> void:
	var me := _make_base(Vector2i(200, 200))
	_check(me.earned_total == 0, "earned_total alkaa nollasta")
	me.accept_cargo({MAT_DIRT: 10})  # +10
	_check(me.earned_total == 10, "earned_total kasvoi ensimmaisesta accept_cargo-kutsusta (10), sai %d" % me.earned_total)
	me.accept_cargo({MAT_IRON_ORE: 2})  # +6
	_check(me.earned_total == 16, "earned_total on kumulatiivinen usean accept_cargo-kutsun yli (10+6=16), sai %d" % me.earned_total)
	me.free()


# update_exit (pikselinsyonti intake-aukosta) kasvattaa myos earned_totalia, ei vain
# label-nakyvaa total_earnedia.
func _test_update_exit_increments_earned_total() -> void:
	var me := _make_base(Vector2i(200, 200))
	var w := 300
	var h := 300
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(0)
	var color_seed := PackedByteArray()
	color_seed.resize(w * h)
	color_seed.fill(0)
	var intake_y := me.grid_pos.y - 1
	var ix0: int = me.intake_x[0]
	var ix1: int = me.intake_x[1]
	grid[intake_y * w + ix0] = MAT_DIRT       # 1 $/px
	grid[intake_y * w + ix1] = MAT_IRON_ORE   # 3 $/px
	var frame_earn := me.update_exit(grid, color_seed, w, h, 0.016)
	_check(frame_earn == 4, "update_exit palauttaa frame_earningsin (1 DIRT + 3 IRON_ORE = 4), sai %d" % frame_earn)
	_check(me.earned_total == 4, "earned_total kasvoi frame_earningsin verran (4), sai %d" % me.earned_total)
	_check(me.total_earned == 4, "total_earned (label-arvo) kasvoi myos (4), sai %d" % me.total_earned)
	# Toinen kutsu ilman uutta materiaalia -> ei lisaa kasvua.
	var frame_earn2 := me.update_exit(grid, color_seed, w, h, 0.016)
	_check(frame_earn2 == 0, "toinen update_exit ilman materiaalia ei tuota lisatuloa")
	_check(me.earned_total == 4, "earned_total pysyy ennallaan kun ei uutta materiaalia")
	me.free()


# PRICES: COPPER_ORE (id 20) = 4, RARE_EARTH (id 21) = 8 (lane C lisaa worldgeniin).
func _test_prices_include_copper_and_rare_earth() -> void:
	var me := _make_base(Vector2i(200, 200))
	_check(int(MoneyExit.PRICES.get(20, -1)) == 4, "COPPER_ORE (id 20) hinta on 4, sai %d" % int(MoneyExit.PRICES.get(20, -1)))
	_check(int(MoneyExit.PRICES.get(21, -1)) == 8, "RARE_EARTH (id 21) hinta on 8, sai %d" % int(MoneyExit.PRICES.get(21, -1)))
	var total := me.accept_cargo({20: 3, 21: 2})  # 3*4 + 2*8 = 12+16 = 28
	_check(total == 28, "accept_cargo hinnoittelee COPPER_ORE+RARE_EARTH oikein (28), sai %d" % total)
	me.free()
