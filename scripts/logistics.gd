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
			return


# Kytkee vyohykkeen aktiivisuuden (Aktiivinen/Pois paalta -kytkin popoverissa). filter_mask
# sailyy koskemattomana - vain active-lippu muuttuu.
func set_zone_active(id: int, active: bool) -> void:
	for z in _zones:
		if int(z["id"]) == id:
			z["active"] = active
			return


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
		var dist := from_px.distance_squared_to(center)
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
