# Hissi-linko: imee materiaalia kuilun kautta ylös, ampuu vaakasuoraan tykkiputkesta
class_name Launcher
extends Node2D

const SHAFT_WIDTH := 4         # Kuilun leveys pikseleinä
const BARREL_LENGTH := 6       # Tykkiputken pituus pikseleinä
var launch_speed: float = 120.0    # px/s perusnopeus
var launch_angle_deg: float = -45.0 # 45° ylöspäin (negatiivinen Y = ylös)
const ANGLE_VARIANCE := 3.0    # ±astetta hajontaa
const SPEED_VARIANCE := 0.05   # ±5% nopeushajonta
var intake_cooldown: float = 0.32  # s per pikseli-erä
const MAX_INTAKE_PER_FRAME := 4  # Pikseleitä per frame maksimissaan
const FLOOR_MAT := 3           # MAT_STONE

# Materiaalien massat — raskaammat lentävät lyhyemmälle
const MAT_MASS: Dictionary = {
	0: 0.0,   # EMPTY
	1: 1.0,   # SAND
	2: 0.5,   # WATER (kevyt)
	3: 2.5,   # STONE (raskas)
	4: 1.5,   # WOOD
	5: 0.3,   # FIRE (erittäin kevyt)
	6: 0.8,   # OIL
	7: 0.1,   # STEAM (lähes painoton)
	8: 1.2,   # ASH
	9: 1.5,   # WOOD_FALLING
	10: 2.0,  # GLASS
}
const BASE_MASS: float = 1.0  # Referenssimassa — nopeus jaetaan (massa / BASE_MASS)

var start_pos: Vector2i = Vector2i.ZERO   # Pohja (hihnan kohdalla)
var end_pos: Vector2i = Vector2i.ZERO     # Katto (suoraan ylhäällä)
var launch_dir: float = 1.0              # 1.0=oikealle, -1.0=vasemmalle
var structure_pixels: Array[Vector2i] = []  # Kuilun reunat + tykki (check_intact seuraa näitä)
var _jalusta_pixels: Array[Vector2i] = []   # Jalusta erikseen — ei check_intact:ssa (osuu hihnaan)
var _own_pixel_set: Dictionary = {}         # Kaikki omat pikselit hashattuina Vector2i → true
var barrel_tip: Vector2i = Vector2i.ZERO  # Tykkiputken kärki
var broken: bool = false
var locked_conveyor_y: int = -1  # -1 = ei lukittu, muuten konveyori-rivi
var cooldown_timer: float = 0.0
var _flash_timer: float = 0.0
var shaft_pixels: Array[Dictionary] = []  # Kuilussa matkustavat pikselit
var shaft_speed: float = 180.0               # px/s ylöspäin kuilussa


func build_structure(start: Vector2i, end: Vector2i, dir: float) -> void:
	# Rakentaa hissilinkon: kuilu + jalusta + tykkiputki
	start_pos = start
	end_pos = end
	launch_dir = dir
	structure_pixels.clear()

	# Kuilu: start.y ylhäältä end.y:hyn asti
	# Vasen reuna (x == end.x) ja oikea reuna (x == end.x + SHAFT_WIDTH - 1) = kivi
	# Sisus tyhjä — materiaali nousee siitä
	for y in range(end.y, start.y):
		for x in range(end.x, end.x + SHAFT_WIDTH):
			if x == end.x or x == end.x + SHAFT_WIDTH - 1:
				# Reunapikselit ovat kiveä
				structure_pixels.append(Vector2i(x, y))
			# Sisäpikselit jätetään tyhjäksi — ei lisätä structure_pixels

	# Jalusta: 2 alinta riviä, koko leveys — tuki kuille
	# Ei lisätä structure_pixels-listaan koska ne osuvat hihnan omiin pikseleihin
	# ja check_intact tulisi rikki — jalusta kirjoitetaan gridiin write_to_grid:ssa erikseen
	for y in range(start.y, start.y + 2):
		for x in range(start.x, start.x + SHAFT_WIDTH):
			_jalusta_pixels.append(Vector2i(x, y))

	# Tykkiputki: 45° kulmassa ylöspäin, BARREL_LENGTH pitkä
	# Lähtee kuilun yläreunasta diagonaalisesti oikealle/vasemmalle ylöspäin
	if dir > 0:
		# Tykkiputki oikealle-ylös (45°)
		var bx0: int = end.x + SHAFT_WIDTH
		for i in range(BARREL_LENGTH):
			structure_pixels.append(Vector2i(bx0 + i, end.y - i))
			structure_pixels.append(Vector2i(bx0 + i, end.y - i + 1))  # 2px paksuus
		barrel_tip = Vector2i(bx0 + BARREL_LENGTH, end.y - BARREL_LENGTH)
	else:
		# Tykkiputki vasemmalle-ylös (45°)
		var bx0: int = end.x - 1
		for i in range(BARREL_LENGTH):
			structure_pixels.append(Vector2i(bx0 - i, end.y - i))
			structure_pixels.append(Vector2i(bx0 - i, end.y - i + 1))  # 2px paksuus
		barrel_tip = Vector2i(bx0 - BARREL_LENGTH, end.y - BARREL_LENGTH)

	# Rakennetaan oma pikselijoukko nopeaa hakua varten (update_bottom käyttää tätä)
	_own_pixel_set.clear()
	for p: Vector2i in structure_pixels:
		_own_pixel_set[p] = true
	for p: Vector2i in _jalusta_pixels:
		_own_pixel_set[p] = true

	position = Vector2.ZERO
	queue_redraw()


func write_to_grid(grid: PackedByteArray, color_seed: PackedByteArray, w: int) -> void:
	# Kirjoittaa rakennuksen kivipikselit gridiin (kuilu + tykki + jalusta)
	for p in structure_pixels + _jalusta_pixels:
		var idx := p.y * w + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = FLOOR_MAT
			color_seed[idx] = randi() % 256


func check_intact(chk_grid: PackedByteArray, chk_w: int) -> bool:
	# Tarkistaa onko rakenne ehjä — jos yli 30% structure_pixels puuttuu gridistä, palauttaa false
	if structure_pixels.is_empty():
		return true
	var missing := 0
	for p: Vector2i in structure_pixels:
		var idx := p.y * chk_w + p.x
		if idx < 0 or idx >= chk_grid.size() or chk_grid[idx] != FLOOR_MAT:
			missing += 1
	# Yli 30% puuttuu → rakenne rikki
	if float(missing) / float(structure_pixels.size()) > 0.30:
		broken = true
		return false
	return true


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


func update_launcher(grid: PackedByteArray, w: int, delta: float) -> void:
	# Skannaa intake-pikselit, poistaa materiaalin gridistä ja lisää shaft_pixels-listaan
	if broken:
		return

	cooldown_timer -= delta
	if cooldown_timer > 0.0:
		return

	const INTAKE_DEPTH := 5    # pikseliä alaspäin

	var count := 0
	for x in range(start_pos.x, start_pos.x + SHAFT_WIDTH):
		if count >= MAX_INTAKE_PER_FRAME:
			break
		for dy in range(2, INTAKE_DEPTH + 2):  # +2 hypätään jalustapikselien yli
			var py := start_pos.y + dy
			var idx := py * w + x
			if idx < 0 or idx >= grid.size():
				break
			var mat := grid[idx]
			if mat == FLOOR_MAT:  # Kivi tai hihna estää — pysähdy tähän sarakkeeseen
				break
			if mat == 0:  # Tyhjä — jatka alaspäin
				continue
			# Löydettiin imettävää materiaalia
			grid[idx] = 0
			shaft_pixels.append({
				"pos": Vector2(float(x), float(start_pos.y - 1)),
				"mat": mat,
				"seed": randi() % 256
			})
			count += 1
			break  # Yksi pikseli per sarake per frame

	if count > 0:
		cooldown_timer = intake_cooldown
		_flash_timer = 0.1

	# Laske flash-timer alas joka päivityksellä
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer < 0.0:
			_flash_timer = 0.0
		queue_redraw()


func update_shaft(grid: PackedByteArray, w: int, h: int, delta: float) -> Array[Dictionary]:
	# Liikuttaa shaft_pixels ylöspäin kuilussa.
	# Pikselit EIVÄT ole gridissä — ne piirretään _draw():ssa overlayina.
	# Tämä estää GPU-simulaatiota sotkemasta niitä (monistuminen).
	# Palauttaa FlyingPixelit kun pikseli saavuttaa kuilun yläpään.
	var launched: Array[Dictionary] = []
	var still_in_shaft: Array[Dictionary] = []

	var shaft_center_x: float = float(start_pos.x) + float(SHAFT_WIDTH) / 2.0

	for sp: Dictionary in shaft_pixels:
		# Liiku ylöspäin (negatiivinen Y = ylös)
		sp["pos"].y -= shaft_speed * delta
		sp["pos"].x = shaft_center_x  # lukitse x keskelle

		# Onko saavutettu kuilun yläpää?
		if sp["pos"].y <= float(end_pos.y):
			# Muuta FlyingPixeliksi — lentää tykkiputken suuntaan
			var angle_rad := deg_to_rad(launch_angle_deg + randf_range(-ANGLE_VARIANCE, ANGLE_VARIANCE))
			# Raskaammat aineet saavat pienemmän nopeuden
			var mat: int = sp["mat"]
			var mass: float = MAT_MASS.get(mat, BASE_MASS)
			var mass_factor: float = BASE_MASS / max(mass, 0.1)
			var speed := launch_speed * mass_factor * (1.0 + randf_range(-SPEED_VARIANCE, SPEED_VARIANCE))
			var vel := Vector2(cos(angle_rad) * launch_dir, sin(angle_rad)) * speed
			launched.append({
				"pos": Vector2(float(barrel_tip.x), float(barrel_tip.y)),
				"vel": vel,
				"mat": sp["mat"],
				"seed": sp["seed"],
				"age": 0.0
			})
			_flash_timer = 0.1
			queue_redraw()
		else:
			still_in_shaft.append(sp)

	shaft_pixels = still_in_shaft
	if not shaft_pixels.is_empty():
		queue_redraw()
	return launched


func update_bottom(grid: PackedByteArray, w: int, conveyor_mat: int) -> bool:
	# Tarkistaa jalustasta alaspäin — laskeutuu tyhjän päälle tai lukittuu konveyyoriin.
	# Palauttaa true jos start_pos.y muuttui (jalusta liikkunut).
	if broken:
		return false

	# Tarkista onko jalustasta kaksi riviä alempana konveyori-kiviä (FLOOR_MAT)
	# Koska konveyorit tallennetaan gridiin MAT_STONE:na, tarkistetaan onko alhaalla
	# kivi building_pixels-rakenteessa — mutta tässä skriptiä ei voi suoraan tarkistaa sitä.
	# Yksinkertaistettu logiikka: jos alempana on MAT_STONE tai conveyor_mat → lukittuu.
	var check_y: int = start_pos.y + 2  # Kaksi riviä jalustasta alas
	var grid_h: int = grid.size() / w

	# Tarkista onko locked_conveyor_y:n rivillä edelleen konveyyori-materiaali
	if locked_conveyor_y >= 0:
		var all_present := true
		for x in range(start_pos.x, start_pos.x + SHAFT_WIDTH):
			var idx := locked_conveyor_y * w + x
			if idx < 0 or idx >= grid.size():
				all_present = false
				break
			var p := Vector2i(x, locked_conveyor_y)
			# Launcherin omat pikselit ohitetaan — ne eivät ole ulkoinen konveyyori
			if _own_pixel_set.has(p):
				continue
			var mat := grid[idx]
			if mat != FLOOR_MAT and mat != conveyor_mat:
				all_present = false
				break
		if not all_present:
			# Konveyori on tuhoutunut — vapaudu lukituksesta
			locked_conveyor_y = -1
		else:
			# Edelleen kiinni konveyyorissa — ei liikettä
			return false

	# Tarkista onko jalustasta suoraan alhaalta (check_y = start_pos.y + 2)
	# ulkoinen konveyyori tai kivi (FLOOR_MAT) — lukittuu siihen.
	# conveyor_mat == 0 tarkoittaa "ei konveyyoria" — lukitusta ei tehdä tyhjälle.
	# Launcherin omat rakennepikslit (kuilun reunat) eivät laukaise lukitusta.
	if check_y >= 0 and check_y < grid_h and conveyor_mat != 0:
		var found_conveyor := true
		for x in range(start_pos.x, start_pos.x + SHAFT_WIDTH):
			var idx := check_y * w + x
			if idx < 0 or idx >= grid.size():
				found_conveyor = false
				break
			var p := Vector2i(x, check_y)
			# Ohitetaan launcherin omat pikselit — ne eivät ole ulkoinen konveyyori
			if _own_pixel_set.has(p):
				found_conveyor = false
				break
			var mat := grid[idx]
			if mat != FLOOR_MAT and mat != conveyor_mat:
				found_conveyor = false
				break
		if found_conveyor:
			locked_conveyor_y = check_y
			return false

	# Ei konveyori-lukitusta — tarkista onko jalustasta suoraan alla tyhjää
	var below_y: int = start_pos.y + 2  # Ensimmäinen rivi jalustapikselien alapuolella
	if below_y < 0 or below_y >= grid_h:
		return false  # Ei voi laskeutua rajojen yli

	var below_empty := true
	for x in range(start_pos.x, start_pos.x + SHAFT_WIDTH):
		var idx := below_y * w + x
		if idx < 0 or idx >= grid.size():
			below_empty = false
			break
		var p := Vector2i(x, below_y)
		# Launcherin omat pikselit (kuilun reunat) eivät estä putoamista
		if _own_pixel_set.has(p):
			continue
		var mat := grid[idx]
		if mat != 0 and mat != conveyor_mat:
			# Ulkoinen kiinteä materiaali suoraan alla — ei liiku
			below_empty = false
			break

	if below_empty:
		# Varmista ettei mennä ruudukon ulkopuolelle
		var new_y: int = start_pos.y + 1
		if new_y + 2 < grid_h:
			start_pos.y = new_y
			return true

	return false


func move_bottom(new_y: int, grid: PackedByteArray, w: int) -> Array:
	# Poistaa vanhat jalustapikselit gridistä, päivittää koordinaatit ja kirjoittaa uudet.
	# Palauttaa [old_jalusta_list, new_jalusta_list] pixel_world.gd:n rekisteröintiä varten.
	var old_jalusta: Array[Vector2i] = _jalusta_pixels.duplicate()

	# Poista vanhat jalustapikselit gridistä
	for p: Vector2i in _jalusta_pixels:
		var idx := p.y * w + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = 0  # MAT_EMPTY

	# Päivitä jalustapikselien koordinaatit uudelle riville
	_jalusta_pixels.clear()
	for y in range(new_y, new_y + 2):
		for x in range(start_pos.x, start_pos.x + SHAFT_WIDTH):
			_jalusta_pixels.append(Vector2i(x, y))

	# Kirjoita uudet jalustapikselit gridiin (MAT_STONE = 3)
	for p: Vector2i in _jalusta_pixels:
		var idx := p.y * w + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = FLOOR_MAT

	# Päivitä oma pikselijoukko vastaamaan uusia jalustapikseleitä
	_own_pixel_set.clear()
	for p: Vector2i in structure_pixels:
		_own_pixel_set[p] = true
	for p: Vector2i in _jalusta_pixels:
		_own_pixel_set[p] = true

	queue_redraw()
	return [old_jalusta, _jalusta_pixels.duplicate()]


# Materiaalivärit shaft-pikselien piirtämiseen (vastaa pixel_render.gdshader)
const _MAT_COLORS: Array = [
	Color(0.08, 0.08, 0.12),  # 0 EMPTY
	Color(0.86, 0.78, 0.45),  # 1 SAND
	Color(0.2,  0.4,  0.85),  # 2 WATER
	Color(0.5,  0.5,  0.52),  # 3 STONE
	Color(0.45, 0.28, 0.12),  # 4 WOOD
	Color(1.0,  0.5,  0.1 ),  # 5 FIRE
	Color(0.2,  0.15, 0.1 ),  # 6 OIL
	Color(0.8,  0.85, 0.9 ),  # 7 STEAM
	Color(0.35, 0.33, 0.3 ),  # 8 ASH
	Color(0.45, 0.28, 0.12),  # 9 WOOD_FALLING
	Color(0.65, 0.88, 0.84),  # 10 GLASS
]


func _draw() -> void:
	if structure_pixels.is_empty():
		return

	# Piirrä shaft-pikselit overlayina — ne eivät ole gridissä
	for sp: Dictionary in shaft_pixels:
		var mat: int = sp["mat"]
		var color: Color = _MAT_COLORS[mat] if mat < _MAT_COLORS.size() else Color(1, 0, 1)
		var px: Vector2 = sp["pos"]
		draw_rect(Rect2(px.x, px.y, 1.0, 1.0), color)

	# Laukaisuvalo barrel_tip-kohdassa
	if _flash_timer > 0.0:
		draw_circle(Vector2(float(barrel_tip.x) + 0.5, float(barrel_tip.y) + 0.5),
			2.0, Color(1.0, 0.8, 0.2, _flash_timer * 5.0))

	# Suuntanuoli tykkiputken kärkeen (45° kulmassa)
	var arrow_start := Vector2(float(barrel_tip.x) + 0.5, float(barrel_tip.y) + 0.5)
	var arrow_dir := Vector2(launch_dir, -1.0).normalized()
	var arrow_end := arrow_start + arrow_dir * 3.0
	var perp := Vector2(arrow_dir.y, -arrow_dir.x)
	draw_line(arrow_start, arrow_end, Color(0.9, 0.6, 0.1, 0.7), 0.5)
	draw_line(arrow_end, arrow_end - arrow_dir * 1.5 + perp * 1.0, Color(0.9, 0.6, 0.1, 0.7), 0.5)
	draw_line(arrow_end, arrow_end - arrow_dir * 1.5 - perp * 1.0, Color(0.9, 0.6, 0.1, 0.7), 0.5)
