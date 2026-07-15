extends SceneTree

# Yksikkotestit Logistics-datamallille (scripts/logistics.gd, API_CONTRACT_demo.md).
# Kattaa: pickup-/dump-pointtien lisays/poisto, filter_mask-bittimaski, base-filtteri,
# ja choose_dump-valinta (GDD §4.2: "filtteri hyvaksyy suurimman osan kuormasta ja lahinna").
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_logistics.gd

const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13
const MAT_COAL := 16

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== LOGISTICS-TESTIT ===\n")
	_test_add_and_get_zones()
	_test_remove_zone()
	_test_set_zone_filter()
	_test_mask_accepts_zero_is_wildcard()
	_test_mask_accepts_specific_bits()
	_test_accepted_count_sums_only_matching()
	_test_choose_dump_defaults_to_base_when_no_zones()
	_test_choose_dump_prefers_zone_that_accepts_more()
	_test_choose_dump_tiebreaks_by_distance()
	_test_choose_dump_empty_when_nothing_accepts()
	_test_base_filter_restricts_base_acceptance()
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


# --- add/remove/get_zones -----------------------------------------------------

func _test_add_and_get_zones() -> void:
	var lg := Logistics.new()
	var pid := lg.add_pickup_point(Rect2i(10, 10, 20, 20), 1 << MAT_IRON_ORE, 5)
	var did := lg.add_dump_point(Rect2i(100, 100, 30, 30), 1 << MAT_DIRT)
	var zones := lg.get_zones()
	_check(zones.size() == 2, "get_zones palauttaa molemmat lisatyt vyohykkeet (2), sai %d" % zones.size())
	var pickup_z: Dictionary = {}
	var dump_z: Dictionary = {}
	for z in zones:
		if int(z["id"]) == pid:
			pickup_z = z
		elif int(z["id"]) == did:
			dump_z = z
	_check(String(pickup_z.get("type", "")) == "pickup", "pickup-vyohyke merkitty tyypiltaan 'pickup'")
	_check(String(dump_z.get("type", "")) == "dump", "dump-vyohyke merkitty tyypiltaan 'dump'")
	_check(int(pickup_z.get("priority", -1)) == 5, "pickup-vyohykkeen prioriteetti sailyy (5)")
	_check((pickup_z.get("rect", Rect2i()) as Rect2i) == Rect2i(10, 10, 20, 20), "pickup-vyohykkeen rect sailyy")
	_check(int(dump_z.get("filter_mask", -1)) == (1 << MAT_DIRT), "dump-vyohykkeen filter_mask sailyy")


func _test_remove_zone() -> void:
	var lg := Logistics.new()
	var id1 := lg.add_pickup_point(Rect2i(0, 0, 10, 10), 0)
	var id2 := lg.add_dump_point(Rect2i(20, 20, 10, 10), 0)
	lg.remove_zone(id1)
	var zones := lg.get_zones()
	_check(zones.size() == 1, "remove_zone poistaa vain kohdevyohykkeen (jaljella 1), sai %d" % zones.size())
	_check(int(zones[0]["id"]) == id2, "jaljella oleva vyohyke on oikea (id2)")
	# Poisto tuntemattomalla id:lla ei kaada eika muuta mitaan.
	lg.remove_zone(9999)
	_check(lg.get_zones().size() == 1, "tuntemattoman id:n poisto ei muuta zonelistaa")


func _test_set_zone_filter() -> void:
	var lg := Logistics.new()
	var id := lg.add_dump_point(Rect2i(0, 0, 10, 10), 1 << MAT_DIRT)
	lg.set_zone_filter(id, 1 << MAT_IRON_ORE)
	var zones := lg.get_zones()
	_check(int(zones[0]["filter_mask"]) == (1 << MAT_IRON_ORE), "set_zone_filter paivittaa maskin")


# --- filter_mask-bittimaski ----------------------------------------------------

func _test_mask_accepts_zero_is_wildcard() -> void:
	_check(Logistics.mask_accepts(0, MAT_DIRT), "mask=0 hyvaksyy minka tahansa materiaalin (DIRT)")
	_check(Logistics.mask_accepts(0, MAT_IRON_ORE), "mask=0 hyvaksyy minka tahansa materiaalin (IRON_ORE)")


func _test_mask_accepts_specific_bits() -> void:
	var mask := (1 << MAT_DIRT) | (1 << MAT_COAL)
	_check(Logistics.mask_accepts(mask, MAT_DIRT), "maski hyvaksyy DIRTin (bitti asetettu)")
	_check(Logistics.mask_accepts(mask, MAT_COAL), "maski hyvaksyy COALin (bitti asetettu)")
	_check(not Logistics.mask_accepts(mask, MAT_IRON_ORE), "maski EI hyvaksy IRON_ORE:a (bitti ei asetettu)")


func _test_accepted_count_sums_only_matching() -> void:
	var lg := Logistics.new()
	var cargo := {MAT_DIRT: 10, MAT_IRON_ORE: 5, MAT_GOLD_ORE: 3}
	var mask := (1 << MAT_DIRT) | (1 << MAT_GOLD_ORE)
	var acc := lg.accepted_count(mask, cargo)
	_check(acc == 13, "accepted_count summaa vain hyvaksytyt materiaalit (10 DIRT + 3 GOLD_ORE = 13), sai %d" % acc)
	_check(lg.accepted_count(0, cargo) == 18, "accepted_count(0,...) hyvaksyy kaiken (10+5+3=18)")


# --- choose_dump ----------------------------------------------------------------

func _test_choose_dump_defaults_to_base_when_no_zones() -> void:
	var lg := Logistics.new()
	var cargo := {MAT_DIRT: 20}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0), Vector2(500, 500))
	_check(String(chosen.get("kind", "")) == "base", "ei dump-vyohykkeita -> valinta on base")
	_check((chosen.get("pos", Vector2.ZERO) as Vector2).is_equal_approx(Vector2(500, 500)), "base-kohde on annettu base_intake")


# GDD §4.2: valitaan dumpi joka hyvaksyy SUURIMMAN OSAN kuormasta (ei valttamatta lahin).
# Base rajataan pois kilpailusta (filtteri ei hyvaksy kumpaakaan materiaalia) jotta testi
# vertailee nimenomaan kahta dump-vyohyketta keskenaan.
func _test_choose_dump_prefers_zone_that_accepts_more() -> void:
	var lg := Logistics.new()
	lg.set_base_filter(1 << MAT_GOLD_ORE)  # base ei hyvaksy IRON_ORE:a eika COALia -> base_acc=0
	# Lahella oleva dump hyvaksyy vain pienen osan (COAL), kaukana oleva hyvaksyy koko kuorman (IRON_ORE).
	lg.add_dump_point(Rect2i(10, 10, 10, 10), 1 << MAT_COAL)       # lahella, hyvaksyy 2/30
	lg.add_dump_point(Rect2i(900, 900, 10, 10), 1 << MAT_IRON_ORE)  # kaukana, hyvaksyy 28/30
	var cargo := {MAT_IRON_ORE: 28, MAT_COAL: 2}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0), Vector2(500, 500))
	_check(String(chosen.get("kind", "")) == "dump", "valinta on dump-vyohyke")
	_check(int(chosen.get("accepted", 0)) == 28, "valittu dump hyvaksyy suuremman osuuden kuormasta (28), sai %d" % int(chosen.get("accepted", 0)))


func _test_choose_dump_tiebreaks_by_distance() -> void:
	var lg := Logistics.new()
	# Molemmat hyvaksyvat koko kuorman -> valitaan lahin.
	lg.add_dump_point(Rect2i(1000, 1000, 10, 10), 1 << MAT_DIRT)  # kaukana
	var near_id := lg.add_dump_point(Rect2i(20, 20, 10, 10), 1 << MAT_DIRT)  # lahella
	var cargo := {MAT_DIRT: 10}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0), Vector2(500, 500))
	_check(int(chosen.get("id", -1)) == near_id, "tasapelissa (molemmat hyvaksyvat kaiken) valitaan lahin vyohyke")


func _test_choose_dump_empty_when_nothing_accepts() -> void:
	var lg := Logistics.new()
	lg.set_base_filter(1 << MAT_DIRT)  # base ei hyvaksy IRON_ORE:a
	lg.add_dump_point(Rect2i(10, 10, 10, 10), 1 << MAT_COAL)  # ei myoskaan hyvaksy IRON_ORE:a
	var cargo := {MAT_IRON_ORE: 10}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0), Vector2(500, 500))
	_check(chosen.is_empty(), "tyhja tulos kun mikaan kandidaatti ei hyvaksy kuormaa")


func _test_base_filter_restricts_base_acceptance() -> void:
	var lg := Logistics.new()
	_check(lg.base_filter == 0, "oletus base_filter on 0 (kaikki kelpaa)")
	lg.set_base_filter(1 << MAT_DIRT)
	var cargo_mixed := {MAT_DIRT: 5, MAT_IRON_ORE: 5}
	var chosen := lg.choose_dump(cargo_mixed, Vector2(0, 0), Vector2(500, 500))
	# Ei dump-vyohykkeita -> ainoa kandidaatti on base, joka hyvaksyy vain DIRTin osan (5).
	_check(String(chosen.get("kind", "")) == "base", "base valitaan silti (osittainen hyvaksynta > 0)")
	_check(int(chosen.get("accepted", 0)) == 5, "base hyvaksyy vain filtterin lapaisevan osan (5 DIRT), sai %d" % int(chosen.get("accepted", 0)))
