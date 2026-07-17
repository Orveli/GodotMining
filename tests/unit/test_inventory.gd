extends SceneTree

# Yksikkotestit M1-inventaario- ja myynti-API:lle (scripts/pixel_world.gd):
# deposit_material (SELL vs STORE), deposit_cargo, sell_from_inventory,
# sell_all_surplus, can_afford_materials, spend_materials, inventory_total_value.
#
# pixel_world.gd on TextureRect mutta nama funktiot koskettavat vain jasenmuuttujia
# (inventory/material_policy/money/total_revenue) + MoneyExit.PRICES-taulua, joten
# .new() ilman scene-treeta riittaa (headless-turvallinen, _ready ei aja).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_inventory.gd

const PixelWorld = preload("res://scripts/pixel_world.gd")

const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD := 15
const MAT_COAL := 16
const MAT_GRAVEL := 18
const MAT_COPPER := 20

# PRICES (money_exit.gd): DIRT=1, IRON_ORE=3, GOLD=12, COAL=2, GRAVEL=1, COPPER=4.

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== INVENTAARIO-TESTIT (M1) ===\n")
	_test_deposit_sell_material_to_money()
	_test_deposit_store_material_to_inventory()
	_test_deposit_cargo_mixed_policies()
	_test_sell_from_inventory_all()
	_test_sell_from_inventory_partial()
	_test_sell_all_surplus()
	_test_can_afford_and_spend()
	_test_spend_insufficient_is_atomic()
	_test_inventory_total_value()
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


func _make_world() -> Object:
	var w = PixelWorld.new()
	# Fresh .new(): inventory={}, material_policy={}, money=0, total_revenue=0.
	# Oletuspolitiikat asetetaan vasta _init_bot_sim():ssa jota ei aja tassa -> asetetaan testeissa kasin.
	return w


# SELL-materiaali (oletus): deposit_material -> money + total_revenue, EI inventaarioon.
func _test_deposit_sell_material_to_money() -> void:
	var w = _make_world()
	w.deposit_material(MAT_GRAVEL, 10)  # SELL oletus, 1 $/px -> 10
	_check(w.money == 10, "SELL: money nousi 10 (10*GRAVEL), sai %d" % w.money)
	_check(w.total_revenue == 10, "SELL: total_revenue nousi 10, sai %d" % w.total_revenue)
	_check(w.inventory_amount(MAT_GRAVEL) == 0, "SELL: inventaario pysyy tyhjana")
	w.free()


# STORE-materiaali: deposit_material -> inventaario, EI rahaa.
func _test_deposit_store_material_to_inventory() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 15)
	_check(w.inventory_amount(MAT_IRON_ORE) == 15, "STORE: inventaarioon kertyi 15, sai %d" % w.inventory_amount(MAT_IRON_ORE))
	_check(w.money == 0, "STORE: raha ei muuttunut")
	_check(w.total_revenue == 0, "STORE: total_revenue ei muuttunut")
	# Toinen erä kumuloituu.
	w.deposit_material(MAT_IRON_ORE, 5)
	_check(w.inventory_amount(MAT_IRON_ORE) == 20, "STORE: erat kumuloituvat (20), sai %d" % w.inventory_amount(MAT_IRON_ORE))
	w.free()


# deposit_cargo reitittaa jokaisen materiaalin erikseen politiikan mukaan.
func _test_deposit_cargo_mixed_policies() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	# GRAVEL SELL (1$/px), IRON_ORE STORE.
	w.deposit_cargo({MAT_GRAVEL: 8, MAT_IRON_ORE: 12})
	_check(w.money == 8, "cargo: SELL-osa rahaksi (8), sai %d" % w.money)
	_check(w.inventory_amount(MAT_IRON_ORE) == 12, "cargo: STORE-osa inventaarioon (12), sai %d" % w.inventory_amount(MAT_IRON_ORE))
	w.free()


# sell_from_inventory(-1) myy koko varaston materiaalista ja poistaa avaimen.
func _test_sell_from_inventory_all() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 10)  # IRON_ORE 3$/px
	var got: int = w.sell_from_inventory(MAT_IRON_ORE, -1)
	_check(got == 30, "myynti palauttaa arvon 30 (10*3), sai %d" % got)
	_check(w.money == 30, "myynti kasvatti rahaa 30, sai %d" % w.money)
	_check(w.total_revenue == 30, "myynti kasvatti total_revenuea 30, sai %d" % w.total_revenue)
	_check(w.inventory_amount(MAT_IRON_ORE) == 0, "koko varasto myyty -> 0")
	_check(not w.inventory.has(MAT_IRON_ORE), "avain poistettu inventaariosta")
	w.free()


# sell_from_inventory(px) myy vain px, jattaa loput.
func _test_sell_from_inventory_partial() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 10)
	var got: int = w.sell_from_inventory(MAT_IRON_ORE, 4)  # 4*3=12
	_check(got == 12, "osamyynti palauttaa 12 (4*3), sai %d" % got)
	_check(w.inventory_amount(MAT_IRON_ORE) == 6, "jaljella 6, sai %d" % w.inventory_amount(MAT_IRON_ORE))
	# px > varasto myy vain varaston verran.
	var got2: int = w.sell_from_inventory(MAT_IRON_ORE, 100)
	_check(got2 == 18, "px>varasto myy vain jaljella olevat (6*3=18), sai %d" % got2)
	_check(w.inventory_amount(MAT_IRON_ORE) == 0, "varasto tyhja osamyyntien jalkeen")
	w.free()


# sell_all_surplus myy kaikki materiaalit, palauttaa kokonaisarvon.
func _test_sell_all_surplus() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.set_material_policy(MAT_COPPER, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 10)  # 30
	w.deposit_material(MAT_COPPER, 5)     # 5*4=20
	var total: int = w.sell_all_surplus()
	_check(total == 50, "sell_all_surplus palauttaa 50 (30+20), sai %d" % total)
	_check(w.money == 50, "raha 50 kaiken myynnin jalkeen, sai %d" % w.money)
	_check(w.inventory.is_empty(), "inventaario tyhja kaiken myynnin jalkeen")
	w.free()


# can_afford_materials + spend_materials: riittava resepti kuluu, palauttaa true.
func _test_can_afford_and_spend() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 20)
	var recipe := {MAT_IRON_ORE: 14}
	_check(w.can_afford_materials(recipe), "can_afford true kun varaa (20 >= 14)")
	var ok: bool = w.spend_materials(recipe)
	_check(ok, "spend_materials palauttaa true kun varaa")
	_check(w.inventory_amount(MAT_IRON_ORE) == 6, "spend vahensi 14 -> 6 jaljella, sai %d" % w.inventory_amount(MAT_IRON_ORE))
	w.free()


# spend_materials on atominen: riittamaton resepti ei kuluta mitaan, palauttaa false.
func _test_spend_insufficient_is_atomic() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.set_material_policy(MAT_COAL, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 20)
	w.deposit_material(MAT_COAL, 3)
	# Resepti tarvitsee 10 rautaa (ok) + 10 hiilta (ei riita) -> ei saa kuluttaa rautaa.
	var recipe := {MAT_IRON_ORE: 10, MAT_COAL: 10}
	_check(not w.can_afford_materials(recipe), "can_afford false kun COAL ei riita")
	var ok: bool = w.spend_materials(recipe)
	_check(not ok, "spend_materials false kun ei kata")
	_check(w.inventory_amount(MAT_IRON_ORE) == 20, "atominen: rautaa ei kulutettu (20), sai %d" % w.inventory_amount(MAT_IRON_ORE))
	_check(w.inventory_amount(MAT_COAL) == 3, "atominen: hiilta ei kulutettu (3), sai %d" % w.inventory_amount(MAT_COAL))
	w.free()


# inventory_total_value summaa PRICES*px yli koko varaston.
func _test_inventory_total_value() -> void:
	var w = _make_world()
	w.set_material_policy(MAT_IRON_ORE, w.POLICY_STORE)
	w.set_material_policy(MAT_COAL, w.POLICY_STORE)
	w.deposit_material(MAT_IRON_ORE, 10)  # 30
	w.deposit_material(MAT_COAL, 5)       # 5*2=10
	_check(w.inventory_total_value() == 40, "inventory_total_value 40 (30+10), sai %d" % w.inventory_total_value())
	w.free()
