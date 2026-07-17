# scripts/logistics.gd
# Logistiikan datamalli: pickup-pointit ja dump-pointit (GDD §4). Base EI ole enaa
# erillinen pseudokandidaatti — basen "dropoff point" on tavallinen dump-vyohyke jolla on
# lippu is_base_dropoff (ks. add_base_dropoff). Nain sama geneerinen vyohykepopover,
# pysyva renderointi ja hit-test toimivat baselle ilman erikoistapauksia.
# BotManagerin haulerit kayttavat tata:
#   - kasan valinta pickup-vyohykkeilta (dig_site-designaatiot skannaa BotManager itse),
#   - dumpin valinta "filtteri hyvaksyy suurimman osan kuormasta ja on lahinna" (§4.2).
# Koneiden input-dumpit rekisteroidaan tanne add_dump_pointilla (lane G kytkee koneen
# get_input_dump()-datalla). UI kutsuu vain kontraktin (API_CONTRACT_demo.md) metodeja.
#
# filter_mask: bittimaski, bitti = materiaali-ID (1 << mat_id). 0 = ei rajausta (kaikki kelpaa).
class_name Logistics
extends RefCounted

# Vyohyketyypit
const ZONE_PICKUP := 0
const ZONE_DUMP := 1

# Kaikkien materiaali-ID:iden (0..21) bittimaski. Kaytetaan basen dropoff-suodattimen
# materialisointiin (P0-2): koska filter_mask 0 tarkoittaa "kaikki kelpaa", yksittaisten
# materiaalien KIELTAMINEN vaatii maskin materialisoinnin (FULL_MASK & ~kielletyt). Ylimaaraiset
# bitit (esim. EMPTY=0, nesteet) ovat harmittomia — mask_accepts tarkistaa vain kuorman materiaalit.
const FULL_MASK := (1 << 22) - 1

# Vyohykkeet: { "id": int, "type": int, "rect": Rect2i, "filter_mask": int, "priority": int,
#   "is_base_dropoff": bool, "active": bool }.
# active: false = vyohyke on kaytosta pois pelaajan toimesta (ks. set_zone_active) - se ei
# koskaan kelpaa choose_dumpin kandidaatiksi eika naytu pickup_zones()-listalla, RIIPPUMATTA
# filter_mask-asetuksesta. Filtterivalinnat sailyvat muuttumattomina kytkimen tilasta huolimatta.
var _zones: Array = []
var _next_id: int = 1


# ============================================================
#  Kontraktin mukainen julkinen rajapinta (API_CONTRACT_demo.md)
# ============================================================

func add_pickup_point(rect: Rect2i, filter_mask: int, priority: int = 0) -> int:
	var id := _next_id
	_next_id += 1
	_zones.append({
		"id": id, "type": ZONE_PICKUP, "rect": rect,
		"filter_mask": filter_mask, "priority": priority, "active": true,
	})
	return id


func add_dump_point(rect: Rect2i, filter_mask: int) -> int:
	var id := _next_id
	_next_id += 1
	_zones.append({
		"id": id, "type": ZONE_DUMP, "rect": rect,
		"filter_mask": filter_mask, "priority": 0, "is_base_dropoff": false, "active": true,
	})
	return id


# Basen oletus-pudotuspiste: dump-vyohyke jonka purku reititetaan _drop_cargo_above_baseen
# (kirjoittaa vain intake-sarakkeisiin). Visuaalinen/klikattava rect voi olla intakea leveampi.
func add_base_dropoff(rect: Rect2i, filter_mask: int = 0) -> int:
	var id := _next_id
	_next_id += 1
	_zones.append({
		"id": id, "type": ZONE_DUMP, "rect": rect,
		"filter_mask": filter_mask, "priority": 0, "is_base_dropoff": true, "active": true,
	})
	return id


func remove_zone(id: int) -> void:
	for i in range(_zones.size() - 1, -1, -1):
		if int(_zones[i]["id"]) == id:
			_zones.remove_at(i)
			return


func set_zone_filter(id: int, filter_mask: int) -> void:
	for z in _zones:
		if int(z["id"]) == id:
			z["filter_mask"] = filter_mask
			# Pelaajan kasin tekema base-suodattimen muutos lukitsee automaattisen saadon (P0-2):
			# koneiden rakennus/purku ei enaa ylikirjoita pelaajan valintaa (ks. auto_adjust_base_filter).
			if bool(z.get("is_base_dropoff", false)):
				z["user_modified"] = true
			return


# Kytkee vyohykkeen aktiivisuuden (Aktiivinen/Pois paalta -kytkin popoverissa). filter_mask
# sailyy koskemattomana - vain active-lippu muuttuu.
func set_zone_active(id: int, active: bool) -> void:
	for z in _zones:
		if int(z["id"]) == id:
			z["active"] = active
			return


# ============================================================
#  Basen dropoff-suodattimen automaattisaato (P0-2)
# ============================================================

# Sisainen viittaus base-dropoff-vyohykkeeseen (dictionaryt ovat viittaustyyppisia, joten
# palautettuun sanakirjaan kirjoittaminen paivittaa _zonesin alkiota). {} jos basea ei ole.
func _base_zone() -> Dictionary:
	for z in _zones:
		if bool(z.get("is_base_dropoff", false)):
			return z
	return {}


# Base-dropoff-vyohykkeen id (-1 jos ei ole). UI/pixel_world kayttaa.
func base_dropoff_id() -> int:
	var z := _base_zone()
	return int(z.get("id", -1)) if not z.is_empty() else -1


# Onko pelaaja saatanyt base-suodatinta kasin (ks. set_zone_filter). true -> auto-saato ei koske.
func base_filter_user_modified() -> bool:
	var z := _base_zone()
	return (not z.is_empty()) and bool(z.get("user_modified", false))


# Saada base-dropoffin suodatin niin ettei se enaa hyvaksy remove_mask-materiaaleja (P0-2).
# Koska filter_mask 0 = "kaikki kelpaa", yksittaisten materiaalien kieltaminen vaatii maskin
# MATERIALISOINNIN: FULL_MASK & ~remove_mask. remove_mask == 0 palauttaa suodattimen takaisin
# nollaan (kaikki kelpaa jalleen). EI ylikirjoita jos pelaaja on kasin muokannut suodatinta
# (user_modified) -> palauttaa applied=false, user_locked=true (kutsuja nayttaa vain vihjeen).
# Palauttaa: {
#   "applied": bool,        # muuttuiko suodatin
#   "user_locked": bool,    # esto johtui user_modifiedista
#   "newly_removed": int,   # bitit jotka EIVAT enaa kelpaa mutta kelpasivat ennen (toast nimeaa)
#   "restored": int,        # bitit jotka taas kelpaavat (koneen purku palautti)
# }
func auto_adjust_base_filter(remove_mask: int) -> Dictionary:
	var z := _base_zone()
	if z.is_empty():
		return {"applied": false, "user_locked": false, "newly_removed": 0, "restored": 0}
	if bool(z.get("user_modified", false)):
		return {"applied": false, "user_locked": true, "newly_removed": 0, "restored": 0}
	var old_mask := int(z["filter_mask"])
	var new_mask := 0 if remove_mask == 0 else (FULL_MASK & ~remove_mask)
	# Vertailu tehdaan materialisoiduilla maskeilla (0 -> FULL_MASK = "kaikki kelpaa"), jotta
	# newly_removed/restored kertovat oikeat materiaalit riippumatta 0-erikoistapauksesta.
	var old_eff := FULL_MASK if old_mask == 0 else old_mask
	var new_eff := FULL_MASK if new_mask == 0 else new_mask
	var newly_removed := old_eff & ~new_eff
	var restored := new_eff & ~old_eff
	z["filter_mask"] = new_mask
	return {
		"applied": (newly_removed != 0 or restored != 0),
		"user_locked": false,
		"newly_removed": newly_removed, "restored": restored,
	}


# Palauttaa kopiot vyohykkeista (kutsuja ei muokkaa sisaista tilaa suoraan). UI-kaytto.
func get_zones() -> Array:
	var out: Array = []
	for z in _zones:
		out.append({
			"id": z["id"],
			"type": ("pickup" if int(z["type"]) == ZONE_PICKUP else "dump"),
			"rect": z["rect"],
			"filter_mask": z["filter_mask"],
			"priority": z["priority"],
			"is_base_dropoff": z.get("is_base_dropoff", false),
			"active": z.get("active", true),
		})
	return out


# ============================================================
#  BotManagerin sisainen apurajapinta (ei UI-kaytto)
# ============================================================

# Pickup-vyohykkeet suoraan (sisaiset dict-viittaukset). BotManager vain lukee naita.
# Pois paalta kytketyt (active=false) vyohykkeet suodatetaan pois - haulerit eivat naytua nae.
func pickup_zones() -> Array:
	var out: Array = []
	for z in _zones:
		if int(z["type"]) == ZONE_PICKUP and bool(z.get("active", true)):
			out.append(z)
	return out


# Hyvaksyyko maski materiaalin? 0 = ei rajausta -> kaikki kelpaa.
static func mask_accepts(mask: int, mat_id: int) -> bool:
	if mask == 0:
		return true
	return (mask & (1 << mat_id)) != 0


# Montako pikselia kuormasta maski hyvaksyy (GDD §4.2: "suurin osa kuormasta").
func accepted_count(mask: int, cargo: Dictionary) -> int:
	var total := 0
	for mat in cargo:
		if mask_accepts(mask, int(mat)):
			total += int(cargo[mat])
	return total


# Valitse paras dump kuormalle: hyvaksyy suurimman osan kuormasta, tie-break lahin.
# Kandidaatteina VAIN dump-vyohykkeet (ei enaa kovakoodattua base-pseudokandidaattia — base
# on nykyaan tavallinen dump-vyohyke, ks. add_base_dropoff/is_base_dropoff). Palauttaa:
#   { "kind": "dump", "pos": Vector2, "rect": Rect2i, "id": int, "accepted": int,
#     "is_base_dropoff": bool }
# tai tyhjan {} jos mikaan dump-vyohyke ei hyvaksy yhtaan kuormasta (hauler jaa IDLEen
# kuorman kanssa ja yrittaa myohemmin, ks. bot_manager.gd DUMP_RETRY_DELAY).
func choose_dump(cargo: Dictionary, from_px: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_accepted := 0
	var best_dist := INF
	for z in _zones:
		if int(z["type"]) != ZONE_DUMP:
			continue
		if not bool(z.get("active", true)):
			continue
		var acc := accepted_count(int(z["filter_mask"]), cargo)
		if acc <= 0:
			continue
		var rect: Rect2i = z["rect"]
		var center := _rect_center(rect)
		# Planeetta: x jaksollinen -> toroidaalinen etaisyys (lyhin sauman yli).
		# torus_dist on lineaarinen (ei nelio), mutta tie-break-jarjestys sailyy monotonisena.
		var dist := PlanetGeom.torus_dist(from_px, center, float(NavGrid.SIM_W))
		# Ensisijaisesti suurin hyvaksytty osuus, tie-break lyhin etaisyys.
		if acc > best_accepted or (acc == best_accepted and dist < best_dist):
			best = {
				"kind": "dump", "pos": center, "rect": rect,
				"id": int(z["id"]), "accepted": acc,
				"is_base_dropoff": bool(z.get("is_base_dropoff", false)),
			}
			best_accepted = acc
			best_dist = dist
	return best


func _rect_center(rect: Rect2i) -> Vector2:
	return Vector2(
		float(rect.position.x) + float(rect.size.x) * 0.5,
		float(rect.position.y) + float(rect.size.y) * 0.5,
	)
