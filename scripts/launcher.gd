# Hissi-linko: imee materiaalia kuilun kautta ylös, ampuu vaakasuoraan tykkiputkesta
class_name Launcher
extends Node2D

const SHAFT_WIDTH := 4         # Kuilun leveys pikseleinä
const BARREL_LENGTH := 6       # Tykkiputken pituus pikseleinä
const LAUNCH_SPEED := 120.0    # px/s perusnopeus
const LAUNCH_ANGLE_DEG := 0.0  # Vaakasuora laukaisukulma
const ANGLE_VARIANCE := 5.0    # ±astetta hajontaa
const SPEED_VARIANCE := 0.15   # ±15% nopeushajonta
const INTAKE_COOLDOWN := 0.08  # s per pikseli-erä
const MAX_INTAKE_PER_FRAME := 4  # Pikseleitä per frame maksimissaan
const FLOOR_MAT := 3           # MAT_STONE

var start_pos: Vector2i = Vector2i.ZERO   # Pohja (hihnan kohdalla)
var end_pos: Vector2i = Vector2i.ZERO     # Katto (suoraan ylhäällä)
var launch_dir: float = 1.0              # 1.0=oikealle, -1.0=vasemmalle
var structure_pixels: Array[Vector2i] = []  # Kuilun reunat + tykki (check_intact seuraa näitä)
var _jalusta_pixels: Array[Vector2i] = []   # Jalusta erikseen — ei check_intact:ssa (osuu hihnaan)
var intake_pixels: Array[Vector2i] = []  # Pohjan pikselit joista imetään
var barrel_tip: Vector2i = Vector2i.ZERO  # Tykkiputken kärki
var broken: bool = false
var cooldown_timer: float = 0.0
var _flash_timer: float = 0.0
var shaft_pixels: Array[Dictionary] = []  # Kuilussa matkustavat pikselit
const SHAFT_SPEED := 180.0               # px/s ylöspäin kuilussa


func build_structure(start: Vector2i, end: Vector2i, dir: float) -> void:
	# Rakentaa hissilinkon: kuilu + jalusta + tykkiputki
	start_pos = start
	end_pos = end
	launch_dir = dir
	structure_pixels.clear()
	intake_pixels.clear()

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

	# Tykkiputki: 1 pikseli korkea, BARREL_LENGTH pitkä
	# Lähtee kuilun yläreunasta oikealle tai vasemmalle
	var barrel_start_x: int
	if dir > 0:
		# Tykkiputki oikealle — alkaa kuilun oikeasta reunasta
		barrel_start_x = end.x + SHAFT_WIDTH
		barrel_tip = Vector2i(barrel_start_x + BARREL_LENGTH, end.y)  # yksi ohi viimeisen kivipikselerin
	else:
		# Tykkiputki vasemmalle — alkaa kuilun vasemmasta reunasta - 1
		barrel_start_x = end.x - BARREL_LENGTH
		barrel_tip = Vector2i(barrel_start_x - 1, end.y)  # yksi ohi viimeisen kivipikselerin
	for bx in range(barrel_start_x, barrel_start_x + BARREL_LENGTH):
		structure_pixels.append(Vector2i(bx, end.y))
		structure_pixels.append(Vector2i(bx, end.y + 1))  # 2px korkea

	# Intake-pikselit: kuilun vieressä hihnan tasolla — imetään hihnan päältä
	# Skannaa laajempi alue kuilun kummallakin puolella jotta hihnalta tuleva
	# materiaali löytyy vaikka se ei osu suoraan kuilun kohdalle
	const INTAKE_REACH := 6  # pikseliä kummaltakin sivulta
	for x in range(start.x - INTAKE_REACH, start.x + SHAFT_WIDTH + INTAKE_REACH):
		intake_pixels.append(Vector2i(x, start.y - 1))
		intake_pixels.append(Vector2i(x, start.y - 2))

	position = Vector2.ZERO
	queue_redraw()


func write_to_grid(grid: PackedByteArray, color_seed: PackedByteArray, w: int) -> void:
	# Kirjoittaa rakennuksen kivipikselit gridiin (kuilu + tykki + jalusta)
	for p in structure_pixels + _jalusta_pixels:
		var idx := p.y * w + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = FLOOR_MAT
			color_seed[idx] = randi() % 256


func check_intact(grid: PackedByteArray, w: int) -> bool:
	# Tarkistaa että kaikki rakenteen pikselit ovat edelleen kiveä
	for p in structure_pixels:
		var idx := p.y * w + p.x
		if idx < 0 or idx >= grid.size():
			return false
		if grid[idx] != FLOOR_MAT:
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

	var count := 0
	for p in intake_pixels:
		if count >= MAX_INTAKE_PER_FRAME:
			break
		var idx := p.y * w + p.x
		if idx < 0 or idx >= grid.size():
			continue
		var mat := grid[idx]
		if mat == 0 or mat == FLOOR_MAT:  # Tyhjä tai kivi — ohita
			continue

		# Poista materiaali gridistä
		grid[idx] = 0

		# Lisää pikseli kuiluun — se nousee animoituna ylöspäin
		shaft_pixels.append({
			"pos": Vector2(float(p.x), float(start_pos.y - 1)),  # alkaa pohjan yläpuolelta
			"mat": mat,
			"seed": randi() % 256
		})
		count += 1

	if count > 0:
		cooldown_timer = INTAKE_COOLDOWN
		_flash_timer = 0.1

	# Laske flash-timer alas joka päivityksellä
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer < 0.0:
			_flash_timer = 0.0
		queue_redraw()


func update_shaft(grid: PackedByteArray, w: int, h: int, delta: float) -> Array[Dictionary]:
	# Liikuttaa shaft_pixels ylöspäin kuilussa.
	# Palauttaa FlyingPixelit kun pikseli saavuttaa kuilun yläpään.
	var launched: Array[Dictionary] = []
	var still_in_shaft: Array[Dictionary] = []

	# Kuilun keskikohdan x-koordinaatti — pikseli lukitaan tähän
	var shaft_center_x: int = start_pos.x + SHAFT_WIDTH / 2

	for sp: Dictionary in shaft_pixels:
		# Poista vanha sijainti gridistä (tyhjennä)
		var old_y := int(sp["pos"].y)
		var sx := int(sp["pos"].x)
		var old_idx := old_y * w + sx
		if old_idx >= 0 and old_idx < grid.size():
			if grid[old_idx] == sp["mat"]:  # varmista ettei poisteta väärää pikseliä
				grid[old_idx] = 0

		# Liiku ylöspäin (negatiivinen Y = ylös)
		sp["pos"].y -= SHAFT_SPEED * delta

		# Onko saavutettu kuilun yläpää?
		if sp["pos"].y <= float(end_pos.y):
			# Muuta FlyingPixeliksi — lentää tykkiputken suuntaan
			var angle_rad := deg_to_rad(LAUNCH_ANGLE_DEG + randf_range(-ANGLE_VARIANCE, ANGLE_VARIANCE))
			var speed := LAUNCH_SPEED * (1.0 + randf_range(-SPEED_VARIANCE, SPEED_VARIANCE))
			var vel := Vector2(cos(angle_rad) * launch_dir, sin(angle_rad)) * speed
			launched.append({
				"pos": Vector2(float(barrel_tip.x), float(barrel_tip.y)),
				"vel": vel,
				"mat": sp["mat"],
				"seed": sp["seed"],
				"age": 0.0
			})
			# Sytytä laukaisuvalo kun pikseli ampuu ulos
			_flash_timer = 0.1
			queue_redraw()
		else:
			# Kirjoita uusi sijainti gridiin — pikseli näkyy visuaalisesti kuilussa
			var new_y := int(sp["pos"].y)
			# Pidä pikseli kuilun sisällä (x lukittu shaft_center:iin)
			var new_idx := new_y * w + shaft_center_x
			if new_idx >= 0 and new_idx < grid.size() and new_idx < h * w:
				if grid[new_idx] == 0:
					grid[new_idx] = sp["mat"]
					sp["pos"].x = float(shaft_center_x)  # lukitse x keskelle
			still_in_shaft.append(sp)

	shaft_pixels = still_in_shaft
	return launched


func _draw() -> void:
	if structure_pixels.is_empty():
		return

	# Laukaisuvalo barrel_tip-kohdassa
	if _flash_timer > 0.0:
		draw_circle(Vector2(float(barrel_tip.x) + 0.5, float(barrel_tip.y) + 0.5),
			2.0, Color(1.0, 0.8, 0.2, _flash_timer * 5.0))

	# Suuntanuoli tykkiputken kärkeen
	var arrow_start := Vector2(float(barrel_tip.x) + 0.5, float(barrel_tip.y) + 0.5)
	var arrow_end := arrow_start + Vector2(launch_dir * 3.0, 0.0)
	draw_line(arrow_start, arrow_end, Color(0.9, 0.6, 0.1, 0.7), 0.5)
	draw_line(arrow_end, arrow_end + Vector2(-launch_dir * 1.5, -1.0), Color(0.9, 0.6, 0.1, 0.7), 0.5)
	draw_line(arrow_end, arrow_end + Vector2(-launch_dir * 1.5, 1.0), Color(0.9, 0.6, 0.1, 0.7), 0.5)
