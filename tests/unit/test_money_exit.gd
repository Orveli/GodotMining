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
