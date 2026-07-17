# Haamumoduulit + moduuliketju (M4 - SPEC_seed_ship). Node2D jotta haamun aariviiva ja
# tayttomittari voidaan piirtaa basen kylkeen (building_layer skaalaa grid-px -> screen).
# Datamalli + tayttologiikka + trigger-tilakone; itse rakenteen kirjoitus gridiin, unlock-hookit
# ja charger-lisays tehdaan pixel_world.gd:ssa (se omistaa gridin ja bot_managerin).
#
# Moduuliketju (2 moduulia; varastosiilo jatetty toteuttamatta -> ketju paattyy 2:een, ks. raportti):
#   1 Latausrivisto      req 30 IRON_ORE          trigger: waiting_charger>0 TAI fleet>=4
#                        unlock: uusi Charger (2 slottia) bot_manageriin
#   2 Jalostamo-liitanta req 40 IRON_ORE + 20 COAL trigger: moduuli 1 valmis JA peak_iron>=40
#                        unlock: furnace + crusher build-trayhin (UI lukee is_module_built(2))
#
# Tayttomekaniikka: MOLEMMAT (SPEC 2.4 suositus). Haulerien tuoma STORE-materiaali reititetaan
# aktiivisen (paljastetun) haamun tayttolaskuriin ENNEN inventaarioon kertymista (pixel_world
# deposit_material); LISAKSI pelaaja voi klikata haamua -> Rakenna spend_materials:lla jos varaa.
# ASCII-only-kommentit (bottisim-tiedosto).
class_name BaseModules
extends Node2D

# Materiaalit (rakennusaineet)
const MAT_STONE := 3
const MAT_IRON_ORE := 12
const MAT_COAL := 16

# Moduulin rakenteen ulkomitat (px) basen kyljessa
const MOD_W := 8
const MOD_H := 8
const MOD_GAP := 2                 # rako basen reunaan

# Trigger-kynnykset (SPEC 2.4)
const TRIGGER_FLEET := 4           # moduuli 1 paljastuu kun lauma >= tama
const TRIGGER_PEAK_IRON := 40      # moduuli 2 paljastuu kun inventory piti joskus >= tama


# Yksittainen moduuli. req/fill: mat_id -> px.
class Module extends RefCounted:
	var id: int = 0
	var mod_name: String = ""
	var req: Dictionary = {}
	var fill: Dictionary = {}
	var revealed: bool = false
	var built: bool = false
	var structure_pixels: Array[Vector2i] = []
	var docks: Array[Vector2] = []       # latausrivistolle: uuden chargerin dokkauspisteet

	func req_total() -> int:
		var t := 0
		for m in req:
			t += int(req[m])
		return t

	func fill_total() -> int:
		var t := 0
		for m in req:
			t += mini(int(fill.get(m, 0)), int(req[m]))
		return t

	func is_complete() -> bool:
		for m in req:
			if int(fill.get(m, 0)) < int(req[m]):
				return false
		return true

	# Jaljella oleva tayttotarve (klikkaus-rakennuksen spend_materials-resepti).
	func remaining_recipe() -> Dictionary:
		var r: Dictionary = {}
		for m in req:
			var need := int(req[m]) - int(fill.get(m, 0))
			if need > 0:
				r[m] = need
		return r


var modules: Array[Module] = []
var _peak_iron: int = 0             # inventory piti joskus >= tama (moduuli 2 -trigger)

# Sprite — pixel_world antaa viitteen instansoinnin yhteydessä. null = fallback (ei spriteä,
# valmiit moduulit nakyvat vain gridin kivipikseleina kuten ennen).
var sprite_atlas: SpriteAtlas


# Alusta moduuliketju basen sijainnin ja koon mukaan. base_pos = basen grid_pos (vasen ala),
# base_w/base_h = MoneyExit.EXIT_W/EXIT_H. Moduuli 1 basen vasemmalle, moduuli 2 oikealle.
func setup(base_pos: Vector2i, base_w: int, base_h: int, sim_w: int, sim_h: int) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # sprite teravana, ei sumea skaalaus
	modules.clear()
	_peak_iron = 0

	# Moduuli 1: latausrivisto (basen vasen kylki)
	var m1 := Module.new()
	m1.id = 1
	m1.mod_name = "Latausrivisto"
	m1.req = { MAT_IRON_ORE: 30 }
	var x1 := base_pos.x - MOD_GAP - MOD_W
	m1.structure_pixels = _build_block(x1, base_pos.y, sim_w, sim_h)
	# Uuden chargerin 2 dokkauspistetta moduulin ylapuolelle (2 ERILLISTA, ks. M3-raportti)
	m1.docks = [
		Vector2(float(x1 + 2), float(base_pos.y - 6)),
		Vector2(float(x1 + MOD_W - 2), float(base_pos.y - 6)),
	]
	modules.append(m1)

	# Moduuli 2: jalostamo-liitanta (basen oikea kylki)
	var m2 := Module.new()
	m2.id = 2
	m2.mod_name = "Jalostamo-liitanta"
	m2.req = { MAT_IRON_ORE: 40, MAT_COAL: 20 }
	var x2 := base_pos.x + base_w + MOD_GAP
	m2.structure_pixels = _build_block(x2, base_pos.y, sim_w, sim_h)
	modules.append(m2)


# Yksi MOD_W x MOD_H -lohko (x0,y0)-nurkasta. Rajojen ulkopuoliset pikselit karsitaan.
func _build_block(x0: int, y0: int, sim_w: int, sim_h: int) -> Array[Vector2i]:
	var px: Array[Vector2i] = []
	for dy in MOD_H:
		for dx in MOD_W:
			var x := x0 + dx
			var y := y0 + dy
			if x >= 0 and x < sim_w and y >= 0 and y < sim_h:
				px.append(Vector2i(x, y))
	return px


# Paivita haamujen paljastus (trigger-tilakone). Kutsutaan joka frame pixel_worldista.
#   moduuli 1: waiting_charger > 0 TAI fleet >= TRIGGER_FLEET
#   moduuli 2: moduuli 1 valmis JA inventory piti joskus >= TRIGGER_PEAK_IRON
# peak_iron_now = talla hetkella varastossa oleva IRON_ORE (huippua seurataan sisaisesti).
func update_reveal(fleet_count: int, waiting_charger: int, peak_iron_now: int) -> void:
	_peak_iron = maxi(_peak_iron, peak_iron_now)
	var changed := false
	var m1 := module_at(1)
	if m1 != null and not m1.revealed and not m1.built:
		if waiting_charger > 0 or fleet_count >= TRIGGER_FLEET:
			m1.revealed = true
			changed = true
	var m2 := module_at(2)
	if m2 != null and not m2.revealed and not m2.built:
		if m1 != null and m1.built and _peak_iron >= TRIGGER_PEAK_IRON:
			m2.revealed = true
			changed = true
	if changed:
		queue_redraw()


# Ensimmainen paljastettu, viela rakentamaton moduuli (aktiivinen haamu) tai null.
func active_module() -> Module:
	for m in modules:
		if m.revealed and not m.built:
			return m
	return null


# Moduuli id:lla (1-pohjainen). null jos ei loydy.
func module_at(n: int) -> Module:
	for m in modules:
		if m.id == n:
			return m
	return null


# Syota tayttolaskuriin. Palauttaa tosiasiassa kulutetun maaran (ylijaama jaa kutsujalle).
# Ei rakenna moduulia (kutsuja tarkistaa is_complete ja ajaa unlock-hookin).
func add_fill(m: Module, mat_id: int, px: int) -> int:
	if m == null or px <= 0 or not m.req.has(mat_id):
		return 0
	var have := int(m.fill.get(mat_id, 0))
	var need := int(m.req[mat_id]) - have
	if need <= 0:
		return 0
	var take := mini(px, need)
	m.fill[mat_id] = have + take
	queue_redraw()
	return take


# Merkitse moduuli rakennetuksi (haamu -> valmis). Unlock/rakenne hoidetaan pixel_worldissa.
func mark_built(m: Module) -> void:
	if m == null:
		return
	m.built = true
	m.revealed = true
	# Varmista etta fill kattaa reqin (klikkaus-rakennus voi jattaa vajaan laskurin).
	for mat_id in m.req:
		m.fill[mat_id] = int(m.req[mat_id])
	queue_redraw()


# Kaikki ketjun moduulit rakennettu? (demo-completen _all_modules_built lukee taman)
func all_built() -> bool:
	if modules.is_empty():
		return false
	for m in modules:
		if not m.built:
			return false
	return true


func is_module_built(n: int) -> bool:
	var m := module_at(n)
	return m != null and m.built


# Bounding box structure_pixeleista grid-px-koordinaateissa (Rect2: position=topleft, size=w/h).
func _module_bbox(m: Module) -> Rect2:
	var minx := 100000
	var miny := 100000
	var maxx := -100000
	var maxy := -100000
	for p in m.structure_pixels:
		minx = mini(minx, p.x)
		miny = mini(miny, p.y)
		maxx = maxi(maxx, p.x)
		maxy = maxi(maxy, p.y)
	return Rect2(float(minx), float(miny), float(maxx - minx + 1), float(maxy - miny + 1))


# Haamun aariviiva + tayttomittari aktiiviselle moduulille + sprite valmiille moduulille.
# Piirretaan grid-px-koordinaateissa (building_layer skaalaa).
func _draw() -> void:
	# Valmiit moduulit: sprite overlay kivipikselien päälle (sama malli kuin furnace/crusher/
	# drill — build_structure/_complete_module bakettaa MAT_STONE-pohjan, sprite piirtyy sen
	# päälle). base_module on staattinen (1 frame), ei animaatiota.
	if sprite_atlas != null:
		var tex := sprite_atlas.tex("base_module", 0)
		if tex:
			for m in modules:
				if not m.built or m.structure_pixels.is_empty():
					continue
				draw_texture(tex, _module_bbox(m).position)
	for m in modules:
		if m.built or not m.revealed or m.structure_pixels.is_empty():
			continue
		var bbox := _module_bbox(m)
		var w := bbox.size.x
		var h := bbox.size.y
		var origin := bbox.position
		# Haamun tayttoaste (0..1)
		var total := m.req_total()
		var ratio := 0.0
		if total > 0:
			ratio = clampf(float(m.fill_total()) / float(total), 0.0, 1.0)
		# Taytetty osuus (alhaalta ylos) himmealla ambrilla
		if ratio > 0.0:
			var fh := h * ratio
			draw_rect(Rect2(origin.x, origin.y + (h - fh), w, fh), Color(0.9, 0.6, 0.15, 0.35))
		# Aariviiva (katkoviivamainen ei tuettu -> ohut kehys)
		draw_rect(Rect2(origin, Vector2(w, h)), Color(0.95, 0.75, 0.3, 0.85), false, 1.0)
