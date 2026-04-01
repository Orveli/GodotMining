class_name TestSceneGenerator
# Generoi valmiita testisceneitä PixelWorldiin
# Käytetään ScenarioRunnerin load_scene-komennolla

const EMPTY := 0
const SAND := 1
const WATER := 2
const STONE := 3
const WOOD := 4
const FIRE := 5
const OIL := 6
const STEAM := 7
const ASH := 8
const WOOD_FALLING := 9
const GLASS := 10

const WIDTH := 416
const HEIGHT := 240

# Pääsisääntulokohta — generoi nimetty scene pixel_world-instanssiin
static func generate(scene_name: String, pixel_world: Node) -> void:
	match scene_name:
		"empty":           _gen_empty(pixel_world)
		"physics_playground": _gen_physics_playground(pixel_world)
		"material_soup":   _gen_material_soup(pixel_world)
		"factory_starter": _gen_factory_starter(pixel_world)
		"defense_wave":    _gen_defense_wave(pixel_world)
		"water_cave":      _gen_water_cave(pixel_world)
		"fire_forest":     _gen_fire_forest(pixel_world)
		_:
			push_warning("TestSceneGenerator: tuntematon scene '%s'" % scene_name)


# --- Apufunktiot ---

static func _fill(pw: Node, x: int, y: int, w: int, h: int, mat: int) -> void:
	# Kirjoittaa suorakulmion gridiin suoraan
	var grid: PackedByteArray = pw.get("grid")
	var seed_arr: PackedByteArray = pw.get("color_seed")
	if grid == null or grid.size() == 0:
		return
	var gw: int = pw.get("SIM_WIDTH") if pw.get("SIM_WIDTH") != null else WIDTH
	var gh: int = pw.get("SIM_HEIGHT") if pw.get("SIM_HEIGHT") != null else HEIGHT
	# SIM_WIDTH on const — käytetään WIDTH-vakiota jos get ei toimi
	# pixel_world.gd:ssä W = SIM_WIDTH = 416
	gw = WIDTH
	gh = HEIGHT
	for dy in h:
		var gy := y + dy
		if gy < 0 or gy >= gh:
			continue
		for dx in w:
			var gx := x + dx
			if gx < 0 or gx >= gw:
				continue
			var idx := gy * gw + gx
			grid[idx] = mat
			seed_arr[idx] = randi() % 256
	# Aseta muokatut arrayt takaisin ja merkitse paint_pending
	pw.set("grid", grid)
	pw.set("color_seed", seed_arr)
	pw.set("paint_pending", true)


static func _clear(pw: Node) -> void:
	# Kutsutaan pixel_worldin clear_world()-metodia
	pw.call("clear_world")


# --- Scenet ---

static func _gen_empty(pw: Node) -> void:
	# Tyhjennä kenttä + ohut kivilattia alareunaan
	_clear(pw)
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE)


static func _gen_physics_playground(pw: Node) -> void:
	# Kivilattia + 5 erikokoista kiviblokkia eri korkeuksilla
	_clear(pw)
	# Lattia
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE)
	# Blokit eri korkeuksilla ja koilla — putoavat lattialle
	_fill(pw, 30,  10, 30, 20, STONE)   # iso vasen
	_fill(pw, 100, 30, 20, 20, STONE)   # keski-vasen
	_fill(pw, 180, 5,  15, 15, STONE)   # pieni yläkeski
	_fill(pw, 270, 20, 25, 25, STONE)   # iso keski-oikea
	_fill(pw, 360, 40, 12, 12, STONE)   # pieni oikea


static func _gen_material_soup(pw: Node) -> void:
	# Kaikki materiaalit sekoitettuna — stressitesti
	_clear(pw)
	# Lattia kivestä
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE)
	var grid: PackedByteArray = pw.get("grid")
	var seed_arr: PackedByteArray = pw.get("color_seed")
	# Täytä puolet ruudusta satunnaisilla materiaaleilla
	var mats := [SAND, WATER, STONE, WOOD, OIL]
	for y in HEIGHT - 4:
		for x in WIDTH:
			if randf() < 0.35:
				var m: int = mats[randi() % mats.size()]
				var idx := y * WIDTH + x
				grid[idx] = m
				seed_arr[idx] = randi() % 256
	pw.set("grid", grid)
	pw.set("color_seed", seed_arr)
	pw.set("paint_pending", true)


static func _gen_factory_starter(pw: Node) -> void:
	# Lattia + hiekkavuori vasemmalla + tasainen alusta konvehtoreille
	_clear(pw)
	# Lattia
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE)
	# Hiekkavuori vasemmassa reunassa (suppilo)
	for i in 60:
		var bw := 60 - i
		_fill(pw, 0, 10 + i, bw, 1, SAND)
	# Kivinen alusta oikealla (konvehtorin pohja)
	_fill(pw, 200, HEIGHT - 20, 200, 3, STONE)
	# Pienet kiviseinät suppiloa varten
	_fill(pw, 60, HEIGHT - 60, 5, 56, STONE)


static func _gen_defense_wave(pw: Node) -> void:
	# Kivilattia + kiviseinä vasemmalla tukikohtana
	_clear(pw)
	# Lattia
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE)
	# Paksu kiviseinä vasemmalla (tukikohta)
	_fill(pw, 0, 0, 20, HEIGHT - 4, STONE)
	# Toinen seinä etummaisempana
	_fill(pw, 60, 80, 12, HEIGHT - 84, STONE)
	# Hiekkavalli etulinjalla
	_fill(pw, 150, HEIGHT - 40, 80, 36, SAND)


static func _gen_water_cave(pw: Node) -> void:
	# Kivinen luola täynnä vettä
	_clear(pw)
	# Ulkoseinät
	_fill(pw, 0, 0, WIDTH, 5, STONE)         # katto
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE) # lattia
	_fill(pw, 0, 0, 5, HEIGHT, STONE)          # vasen seinä
	_fill(pw, WIDTH - 5, 0, 5, HEIGHT, STONE)  # oikea seinä
	# Sisäiset kivipilareita
	_fill(pw, 80, 60, 20, HEIGHT - 64, STONE)
	_fill(pw, 180, 40, 20, HEIGHT - 44, STONE)
	_fill(pw, 300, 70, 20, HEIGHT - 74, STONE)
	# Täytä veden runsaasti luolaan (välikerros)
	_fill(pw, 5, 5, WIDTH - 10, 80, WATER)
	# Alaluolan vesi
	_fill(pw, 5, HEIGHT - 80, WIDTH - 10, 72, WATER)


static func _gen_fire_forest(pw: Node) -> void:
	# Puuryhmiä + öljylammikko — palosimulaatiotesti
	_clear(pw)
	# Lattia
	_fill(pw, 0, HEIGHT - 4, WIDTH, 4, STONE)
	# Puuryhmä 1 — vasen
	_fill(pw, 30, HEIGHT - 60, 6, 56, WOOD)   # runko
	_fill(pw, 15, HEIGHT - 90, 36, 30, WOOD)  # latvus
	# Puuryhmä 2 — keski
	_fill(pw, 150, HEIGHT - 70, 6, 66, WOOD)
	_fill(pw, 130, HEIGHT - 105, 46, 35, WOOD)
	# Puuryhmä 3 — oikea
	_fill(pw, 300, HEIGHT - 55, 6, 51, WOOD)
	_fill(pw, 282, HEIGHT - 82, 42, 27, WOOD)
	# Öljylammikko lattian päällä
	_fill(pw, 80, HEIGHT - 8, 180, 4, OIL)
	# Pienipaloinen tulisytytin öljylammikon vasemmassa reunassa
	_fill(pw, 80, HEIGHT - 10, 4, 4, FIRE)
