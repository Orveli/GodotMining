extends SceneTree

# Yksikkotestit M4-haamumoduuleille (scripts/base_modules.gd).
# Kattaa:
#   - setup: 2 moduulia oikeilla resepteilla + rakennepikselit basen molemmin puolin
#   - update_reveal: moduuli 1 triggeri (fleet>=4 TAI waiting_charger>0);
#                    moduuli 2 triggeri (moduuli 1 valmis JA peak_iron>=40)
#   - add_fill: clamppaus reseptiin, palautettu kulutus, ylitayton no-op
#   - is_complete / remaining_recipe
#   - mark_built: fill taydentyy reqiin, all_built, active_module-jarjestys
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_base_modules.gd

const SIM_W := 1664
const SIM_H := 960
const MAT_IRON_ORE := 12
const MAT_COAL := 16

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== BASE_MODULES-TESTIT (M4) ===\n")
	_test_setup_chain()
	_test_reveal_module1()
	_test_reveal_module2()
	_test_fill_and_complete()
	_test_remaining_recipe()
	_test_mark_built_and_all_built()
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


func _make() -> BaseModules:
	var bm := BaseModules.new()
	get_root().add_child(bm)   # CanvasItem-varoitusten valttamiseksi (queue_redraw)
	bm.setup(Vector2i(800, 400), 12, 10, SIM_W, SIM_H)
	return bm


func _test_setup_chain() -> void:
	var bm := _make()
	_check(bm.modules.size() == 2, "setup luo 2 moduulia (ketju paattyy 2:een), sai %d" % bm.modules.size())
	var m1 := bm.module_at(1)
	var m2 := bm.module_at(2)
	_check(m1 != null and int(m1.req.get(MAT_IRON_ORE, 0)) == 30, "moduuli 1 = 30 IRON_ORE")
	_check(m2 != null and int(m2.req.get(MAT_IRON_ORE, 0)) == 40 and int(m2.req.get(MAT_COAL, 0)) == 20,
		"moduuli 2 = 40 IRON_ORE + 20 COAL")
	_check(not m1.structure_pixels.is_empty() and not m2.structure_pixels.is_empty(),
		"molemmilla moduuleilla rakennepikselit")
	_check(m1.docks.size() == 2, "moduuli 1:lla 2 chargerin dokkauspistetta, sai %d" % m1.docks.size())
	_check(m1.docks[0] != m1.docks[1], "dokkauspisteet ovat erilliset (ei paallekkain)")
	bm.queue_free()


func _test_reveal_module1() -> void:
	var bm := _make()
	var m1 := bm.module_at(1)
	# Alle kynnyksen: ei paljastu
	bm.update_reveal(2, 0, 0)
	_check(not m1.revealed, "moduuli 1 EI paljastu kun fleet<4 ja ei jonoa")
	# fleet>=4 paljastaa
	bm.update_reveal(4, 0, 0)
	_check(m1.revealed, "moduuli 1 paljastuu kun fleet>=4")
	# Toinen instanssi: waiting_charger>0 paljastaa vaikka fleet pieni
	var bm2 := _make()
	bm2.update_reveal(2, 1, 0)
	_check(bm2.module_at(1).revealed, "moduuli 1 paljastuu kun waiting_charger>0")
	bm.queue_free()
	bm2.queue_free()


func _test_reveal_module2() -> void:
	var bm := _make()
	var m1 := bm.module_at(1)
	var m2 := bm.module_at(2)
	bm.update_reveal(4, 0, 40)
	_check(not m2.revealed, "moduuli 2 EI paljastu ennen kuin moduuli 1 rakennettu (vaikka peak>=40)")
	# Rakenna moduuli 1
	bm.add_fill(m1, MAT_IRON_ORE, 30)
	_check(m1.is_complete(), "moduuli 1 tayttyi 30 raudalla")
	bm.mark_built(m1)
	bm.update_reveal(4, 0, 30)   # peak jaa aiemmasta 40:sta
	_check(m2.revealed, "moduuli 2 paljastuu kun moduuli 1 valmis JA peak_iron>=40 (huippu muistetaan)")
	bm.queue_free()


func _test_fill_and_complete() -> void:
	var bm := _make()
	var m1 := bm.module_at(1)
	var used := bm.add_fill(m1, MAT_IRON_ORE, 20)
	_check(used == 20, "add_fill(20) kulutti 20, sai %d" % used)
	_check(not m1.is_complete(), "20/30 ei viela valmis")
	# Ylitayto: vain 10 mahtuu, loput jaa kutsujalle
	used = bm.add_fill(m1, MAT_IRON_ORE, 25)
	_check(used == 10, "add_fill clamppaa jaljella olevaan (10), sai %d" % used)
	_check(m1.is_complete(), "30/30 valmis")
	# Taynna -> lisatayto no-op
	used = bm.add_fill(m1, MAT_IRON_ORE, 5)
	_check(used == 0, "taysi moduuli: add_fill on no-op, sai %d" % used)
	# Vaara materiaali -> no-op
	used = bm.add_fill(m1, MAT_COAL, 5)
	_check(used == 0, "moduuli 1 ei ota COALia (ei reseptissa)")
	bm.queue_free()


func _test_remaining_recipe() -> void:
	var bm := _make()
	var m2 := bm.module_at(2)
	bm.add_fill(m2, MAT_IRON_ORE, 15)
	var r: Dictionary = m2.remaining_recipe()
	_check(int(r.get(MAT_IRON_ORE, 0)) == 25 and int(r.get(MAT_COAL, 0)) == 20,
		"remaining_recipe = {iron:25, coal:20} osittain tayetylle")
	bm.add_fill(m2, MAT_IRON_ORE, 25)
	r = m2.remaining_recipe()
	_check(not r.has(MAT_IRON_ORE) and int(r.get(MAT_COAL, 0)) == 20,
		"tayttynyt materiaali putoaa reseptista")
	bm.queue_free()


func _test_mark_built_and_all_built() -> void:
	var bm := _make()
	var m1 := bm.module_at(1)
	var m2 := bm.module_at(2)
	bm.update_reveal(4, 0, 40)
	_check(bm.active_module() == m1, "active_module = ensimmainen paljastettu rakentamaton (m1)")
	bm.mark_built(m1)
	_check(int(m1.fill.get(MAT_IRON_ORE, 0)) == 30, "mark_built taydentaa fillin reqiin")
	_check(not bm.all_built(), "all_built false kun m2 kesken")
	bm.update_reveal(4, 0, 40)
	_check(bm.active_module() == m2, "active_module siirtyy m2:een kun m1 rakennettu")
	bm.mark_built(m2)
	_check(bm.all_built(), "all_built true kun molemmat rakennettu")
	_check(bm.is_module_built(1) and bm.is_module_built(2), "is_module_built molemmille")
	bm.queue_free()
