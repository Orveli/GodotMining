# scripts/logistics.gd
# Logistiikan datamalli: pickup-pointit, dump-pointit ja base-filtteri (GDD §4).
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

# Vyohykkeet: { "id": int, "type": int, "rect": Rect2i, "filter_mask": int, "priority": int }.
var _zones: Array = []
var _next_id: int = 1

# Base-filtteri: mitka materiaalit base (money box) hyvaksyy. 0 = kaikki kelpaa (oletus).
# Kaytto: aseta esim. vain jalostetut -> raakamalmi ohjautuu koneen dump-pisteeseen.
var base_filter: int = 0


# ============================================================
#  Kontraktin mukainen julkinen rajapinta (API_CONTRACT_demo.md)
# ============================================================

func add_pickup_point(rect: Rect2i, filter_mask: int, priority: int = 0) -> int:
	var id := _next_id
	_next_id += 1
	_zones.append({
		"id": id, "type": ZONE_PICKUP, "rect": rect,
		"filter_mask": filter_mask, "priority": priority,
	})
	return id


func add_dump_point(rect: Rect2i, filter_mask: int) -> int:
	var id := _next_id
	_next_id += 1
	_zones.append({
		"id": id, "type": ZONE_DUMP, "rect": rect,
		"filter_mask": filter_mask, "priority": 0,
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


func set_base_filter(filter_mask: int) -> void:
	base_filter = filter_mask


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
		})
	return out


# ============================================================
#  BotManagerin sisainen apurajapinta (ei UI-kaytto)
# ============================================================

# Pickup-vyohykkeet suoraan (sisaiset dict-viittaukset). BotManager vain lukee naita.
func pickup_zones() -> Array:
	var out: Array = []
	for z in _zones:
		if int(z["type"]) == ZONE_PICKUP:
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
# base_intake = basen intake-piste (world.base.intake_pos()). Kandidaatteina base (base_filter)
# + kaikki dump-vyohykkeet. Palauttaa:
#   { "kind": "base"|"dump", "pos": Vector2, "rect": Rect2i, "id": int, "accepted": int }
# tai tyhjan {} jos mikaan kandidaatti ei hyvaksy yhtaan kuormasta.
func choose_dump(cargo: Dictionary, from_px: Vector2, base_intake: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_accepted := 0
	var best_dist := INF
	# Base-kandidaatti (base_filter). Tyhjaa rectia kaytetaan tunnisteena "myy baseen".
	var base_acc := accepted_count(base_filter, cargo)
	if base_acc > 0:
		best = {
			"kind": "base", "pos": base_intake, "rect": Rect2i(),
			"id": -1, "accepted": base_acc,
		}
		best_accepted = base_acc
		best_dist = from_px.distance_squared_to(base_intake)
	# Dump-vyohykkeet
	for z in _zones:
		if int(z["type"]) != ZONE_DUMP:
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
			}
			best_accepted = acc
			best_dist = dist
	return best


func _rect_center(rect: Rect2i) -> Vector2:
	return Vector2(
		float(rect.position.x) + float(rect.size.x) * 0.5,
		float(rect.position.y) + float(rect.size.y) * 0.5,
	)
