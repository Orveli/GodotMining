extends SceneTree

# Yksikkotestit Logistics-datamallille (scripts/logistics.gd, API_CONTRACT_demo.md).
# Kattaa: pickup-/dump-pointtien lisays/poisto, filter_mask-bittimaski, base-dropoff
# (add_base_dropoff/is_base_dropoff) ja choose_dump-valinta (GDD §4.2: "filtteri
# hyvaksyy suurimman osan kuormasta ja lahinna").
#
# HUOM: base EI ole enaa kovakoodattu pseudokandidaatti choose_dumpissa — basen
# "dropoff point" on tavallinen Logistics-dump-vyohyke jolla lippu is_base_dropoff=true
# (ks. add_base_dropoff). choose_dump palauttaa siis AINA "kind"=="dump" (tai tyhjan {}
# jos mikaan dump-vyohyke, sis. base-dropoff, ei hyvaksy kuormaa).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_logistics.gd

const MAT_SAND := 1
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
	_test_choose_dump_empty_when_no_zones()
	_test_choose_dump_prefers_zone_that_accepts_more()
	_test_choose_dump_tiebreaks_by_distance()
	_test_choose_dump_empty_when_nothing_accepts()
	_test_add_base_dropoff_flags_zone_and_defaults_to_accept_all()
	_test_choose_dump_routes_to_base_dropoff_when_restricted()
	_test_zones_default_to_active_true()
	_test_set_zone_active_false_excludes_from_choose_dump()
	_test_set_zone_active_true_restores_candidacy_and_preserves_filter()
	_test_pickup_zones_excludes_inactive()
	_test_base_filter_auto_adjust_on_machine_register()
	_test_base_filter_auto_adjust_on_machine_remove()
	_test_base_filter_respects_user_modified()
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
	_check(bool(dump_z.get("is_base_dropoff", true)) == false, "add_dump_point ei ole base-dropoff (is_base_dropoff=false)")


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

# Base EI ole enaa kovakoodattu fallback-kandidaatti -> ilman dump-vyohykkeita
# (base-dropoff mukaan lukien) choose_dump palauttaa tyhjan {}.
func _test_choose_dump_empty_when_no_zones() -> void:
	var lg := Logistics.new()
	var cargo := {MAT_DIRT: 20}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(chosen.is_empty(), "ei dump-vyohykkeita (ei myoskaan base-dropoffia) -> tyhja tulos")


# GDD §4.2: valitaan dumpi joka hyvaksyy SUURIMMAN OSAN kuormasta (ei valttamatta lahin).
func _test_choose_dump_prefers_zone_that_accepts_more() -> void:
	var lg := Logistics.new()
	# Lahella oleva dump hyvaksyy vain pienen osan (COAL), kaukana oleva hyvaksyy koko kuorman (IRON_ORE).
	lg.add_dump_point(Rect2i(10, 10, 10, 10), 1 << MAT_COAL)       # lahella, hyvaksyy 2/30
	lg.add_dump_point(Rect2i(900, 900, 10, 10), 1 << MAT_IRON_ORE)  # kaukana, hyvaksyy 28/30
	var cargo := {MAT_IRON_ORE: 28, MAT_COAL: 2}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(String(chosen.get("kind", "")) == "dump", "valinta on dump-vyohyke")
	_check(int(chosen.get("accepted", 0)) == 28, "valittu dump hyvaksyy suuremman osuuden kuormasta (28), sai %d" % int(chosen.get("accepted", 0)))


func _test_choose_dump_tiebreaks_by_distance() -> void:
	var lg := Logistics.new()
	# Molemmat hyvaksyvat koko kuorman -> valitaan lahin.
	lg.add_dump_point(Rect2i(1000, 1000, 10, 10), 1 << MAT_DIRT)  # kaukana
	var near_id := lg.add_dump_point(Rect2i(20, 20, 10, 10), 1 << MAT_DIRT)  # lahella
	var cargo := {MAT_DIRT: 10}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(int(chosen.get("id", -1)) == near_id, "tasapelissa (molemmat hyvaksyvat kaiken) valitaan lahin vyohyke")


func _test_choose_dump_empty_when_nothing_accepts() -> void:
	var lg := Logistics.new()
	lg.add_dump_point(Rect2i(10, 10, 10, 10), 1 << MAT_COAL)  # ei hyvaksy IRON_ORE:a
	var cargo := {MAT_IRON_ORE: 10}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(chosen.is_empty(), "tyhja tulos kun mikaan dump-vyohyke ei hyvaksy kuormaa")


# --- add_base_dropoff / is_base_dropoff -----------------------------------------

# add_base_dropoff luo tavallisen dump-tyyppisen vyohykkeen jolla lippu is_base_dropoff=true
# (add_dump_point vastaavasti false). Oletusfiltteri 0 = kaikki kelpaa (kuten muillakin dumpeilla).
func _test_add_base_dropoff_flags_zone_and_defaults_to_accept_all() -> void:
	var lg := Logistics.new()
	var did := lg.add_base_dropoff(Rect2i(50, 50, 10, 10))
	var zones := lg.get_zones()
	_check(zones.size() == 1, "add_base_dropoff lisaa yhden vyohykkeen")
	var z: Dictionary = zones[0]
	_check(int(z.get("id", -1)) == did, "palautettu id vastaa vyohykkeen id:ta")
	_check(String(z.get("type", "")) == "dump", "base-dropoff on tyypiltaan 'dump'")
	_check(bool(z.get("is_base_dropoff", false)) == true, "is_base_dropoff-lippu on tosi")
	_check(int(z.get("filter_mask", -1)) == 0, "oletusfiltteri 0 (kaikki kelpaa)")
	var cargo := {MAT_DIRT: 5, MAT_IRON_ORE: 5}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(int(chosen.get("accepted", 0)) == 10, "oletusfiltteri hyvaksyy koko kuorman (10)")


# Rajattu base-dropoff (filter_mask vain DIRT) hyvaksyy silti OSITTAISEN kuorman (>0) ja
# valitaan silloin kun se on ainoa kandidaatti — ja choose_dump merkitsee sen oikein
# is_base_dropoff=true, jotta bot_manager osaa reitittaa purun _drop_cargo_above_baseen.
func _test_choose_dump_routes_to_base_dropoff_when_restricted() -> void:
	var lg := Logistics.new()
	lg.add_base_dropoff(Rect2i(50, 50, 10, 10), 1 << MAT_DIRT)  # base-dropoff hyvaksyy VAIN DIRTin
	var cargo_mixed := {MAT_DIRT: 5, MAT_IRON_ORE: 5}
	var chosen := lg.choose_dump(cargo_mixed, Vector2(0, 0))
	_check(String(chosen.get("kind", "")) == "dump", "base-dropoff valitaan silti (osittainen hyvaksynta > 0)")
	_check(int(chosen.get("accepted", 0)) == 5, "base-dropoff hyvaksyy vain filtterin lapaisevan osan (5 DIRT), sai %d" % int(chosen.get("accepted", 0)))
	_check(bool(chosen.get("is_base_dropoff", false)) == true, "valittu kandidaatti on merkitty is_base_dropoff=true")


# --- active-lippu (Aktiivinen/Pois paalta -kytkin) --------------------------------

# add_dump_point/add_pickup_point/add_base_dropoff asettavat active=true oletuksena, jotta
# olemassa oleva peli/testit eivat riko - vyohyke on kaytossa heti luonnin jalkeen.
func _test_zones_default_to_active_true() -> void:
	var lg := Logistics.new()
	var pid := lg.add_pickup_point(Rect2i(0, 0, 10, 10), 0)
	var did := lg.add_dump_point(Rect2i(20, 20, 10, 10), 0)
	var bid := lg.add_base_dropoff(Rect2i(40, 40, 10, 10))
	var pickup_active := true
	var dump_active := true
	var base_active := true
	for z in lg.get_zones():
		if int(z["id"]) == pid:
			pickup_active = bool(z.get("active", false))
		elif int(z["id"]) == did:
			dump_active = bool(z.get("active", false))
		elif int(z["id"]) == bid:
			base_active = bool(z.get("active", false))
	_check(pickup_active, "add_pickup_point: active=true oletuksena")
	_check(dump_active, "add_dump_point: active=true oletuksena")
	_check(base_active, "add_base_dropoff: active=true oletuksena")


# set_zone_active(id, false) jalkeen choose_dump EI valitse ko. vyohyketta, vaikka
# filter_mask hyvaksyisi kaiken (mask=0).
func _test_set_zone_active_false_excludes_from_choose_dump() -> void:
	var lg := Logistics.new()
	var did := lg.add_dump_point(Rect2i(10, 10, 10, 10), 0)
	lg.set_zone_active(did, false)
	var cargo := {MAT_DIRT: 10}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(chosen.is_empty(), "pois paalta kytketty ainoa dump-vyohyke -> choose_dump palauttaa tyhjan, vaikka filter_mask=0 hyvaksyisi kaiken")


# set_zone_active(id, true) palauttaa vyohykkeen valittavaksi, ja filter_mask on sailynyt
# muuttumattomana koko ajan (kytkimen tila ei vaikuta filtteriin).
func _test_set_zone_active_true_restores_candidacy_and_preserves_filter() -> void:
	var lg := Logistics.new()
	var mask := 1 << MAT_IRON_ORE
	var did := lg.add_dump_point(Rect2i(10, 10, 10, 10), mask)
	lg.set_zone_active(did, false)
	lg.set_zone_active(did, true)
	var zones := lg.get_zones()
	_check(int(zones[0].get("filter_mask", -1)) == mask, "filter_mask sailyy muuttumattomana active-kytkimen edestakaisen vaihdon jalkeen")
	var cargo := {MAT_IRON_ORE: 10}
	var chosen := lg.choose_dump(cargo, Vector2(0, 0))
	_check(int(chosen.get("id", -1)) == did, "active=true palauttaa vyohykkeen taas choose_dumpin kandidaatiksi")


# pickup_zones() ei palauta pois-paalta-kytkettya pickup-vyohyketta.
func _test_pickup_zones_excludes_inactive() -> void:
	var lg := Logistics.new()
	var pid := lg.add_pickup_point(Rect2i(0, 0, 10, 10), 0)
	lg.set_zone_active(pid, false)
	var zones := lg.pickup_zones()
	_check(zones.is_empty(), "pois paalta kytketty pickup-vyohyke ei nay pickup_zones()-listalla")


# --- P0-2: basen dropoff-suodattimen auto-saato (jalostusketjun auto-aktivointi) ----

# Apuri: base-dropoffin nykyinen filter_mask.
func _base_mask(lg: Logistics, bid: int) -> int:
	for z in lg.get_zones():
		if int(z["id"]) == bid:
			return int(z["filter_mask"])
	return -1


# Koneen rekisterointi materialisoi base-suodattimen: reseptin inputit EIVAT enaa kelpaa, muut
# kelpaavat (0 = "kaikki kelpaa" ei riittanyt kieltamaan yksittaisia -> materialisointi).
func _test_base_filter_auto_adjust_on_machine_register() -> void:
	var lg := Logistics.new()
	lg.add_base_dropoff(Rect2i(50, 50, 10, 10))  # oletusfiltteri 0 = kaikki kelpaa
	var bid := lg.base_dropoff_id()
	_check(bid >= 0, "base_dropoff_id palauttaa basen id:n")
	# Furnace-inputit: SAND | IRON_ORE | GOLD_ORE.
	var furnace_mask := (1 << MAT_SAND) | (1 << MAT_IRON_ORE) | (1 << MAT_GOLD_ORE)
	var res := lg.auto_adjust_base_filter(furnace_mask)
	_check(bool(res.get("applied", false)), "auto_adjust muuttaa suodatinta koneen inputeilla")
	_check((int(res.get("newly_removed", 0)) & furnace_mask) == furnace_mask,
		"newly_removed sisaltaa kaikki koneen inputit")
	var mask := _base_mask(lg, bid)
	_check(not Logistics.mask_accepts(mask, MAT_SAND), "base ei enaa hyvaksy hiekkaa")
	_check(not Logistics.mask_accepts(mask, MAT_IRON_ORE), "base ei enaa hyvaksy rautamalmia")
	_check(not Logistics.mask_accepts(mask, MAT_GOLD_ORE), "base ei enaa hyvaksy kultamalmia")
	_check(Logistics.mask_accepts(mask, MAT_DIRT), "base hyvaksyy yha mullan (ei koneen input)")
	_check(Logistics.mask_accepts(mask, MAT_COAL), "base hyvaksyy yha hiilen (ei koneen input)")
	# choose_dump: DIRT-kuorma kelpaa baseen, IRON_ORE-kuorma ei (ohjautuu koneelle).
	var chosen_dirt := lg.choose_dump({MAT_DIRT: 10}, Vector2(55, 55))
	_check(int(chosen_dirt.get("accepted", 0)) == 10, "DIRT-kuorma kelpaa baseen (10)")
	var chosen_ore := lg.choose_dump({MAT_IRON_ORE: 10}, Vector2(55, 55))
	_check(chosen_ore.is_empty(), "IRON_ORE-kuorma ei enaa kelpaa baseen")


# Koneen purku: auto_adjust_base_filter(0) palauttaa suodattimen nollaan (kaikki kelpaa),
# restored kertoo palautetut materiaalit.
func _test_base_filter_auto_adjust_on_machine_remove() -> void:
	var lg := Logistics.new()
	lg.add_base_dropoff(Rect2i(50, 50, 10, 10))
	var bid := lg.base_dropoff_id()
	var furnace_mask := (1 << MAT_SAND) | (1 << MAT_IRON_ORE)
	lg.auto_adjust_base_filter(furnace_mask)
	# Kone myyty -> ei enaa poistettavia inputteja -> palauta 0 (kaikki kelpaa).
	var res := lg.auto_adjust_base_filter(0)
	_check(bool(res.get("applied", false)), "auto_adjust(0) palauttaa suodattimen")
	_check(_base_mask(lg, bid) == 0, "suodatin palautui nollaan (kaikki kelpaa)")
	_check((int(res.get("restored", 0)) & furnace_mask) == furnace_mask,
		"restored sisaltaa palautetut inputit")
	_check(Logistics.mask_accepts(_base_mask(lg, bid), MAT_SAND), "base hyvaksyy taas hiekan")
	_check(Logistics.mask_accepts(_base_mask(lg, bid), MAT_IRON_ORE), "base hyvaksyy taas rautamalmin")


# user_modified: pelaajan set_zone_filter basen id:lle lukitsee auto-saadon (ei ylikirjoita).
func _test_base_filter_respects_user_modified() -> void:
	var lg := Logistics.new()
	lg.add_base_dropoff(Rect2i(50, 50, 10, 10))
	var bid := lg.base_dropoff_id()
	# Pelaaja saataa basen suodatinta kasin (hyvaksy vain DIRT).
	lg.set_zone_filter(bid, 1 << MAT_DIRT)
	_check(lg.base_filter_user_modified(), "kasin saato (set_zone_filter baselle) merkitsee user_modified")
	# Koneen rekisterointi EI saa muuttaa suodatinta.
	var res := lg.auto_adjust_base_filter((1 << MAT_SAND) | (1 << MAT_IRON_ORE))
	_check(not bool(res.get("applied", false)), "auto_adjust ei muuta suodatinta user_modifiedin jalkeen")
	_check(bool(res.get("user_locked", false)), "auto_adjust raportoi user_locked=true")
	_check(_base_mask(lg, bid) == (1 << MAT_DIRT), "pelaajan suodatin sailyy koskemattomana")
