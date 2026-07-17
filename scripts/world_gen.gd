# Maailmageneraattori
# Maailman koko: 1664×960 pikseliä
# Pipeline:
#   Phase 1: _generate_terrain()          → surface_y (ruudukkoon snapattu kivipinta)
#   Phase 2: _generate_caves()            → cave_paths (poistettu käytöstä)
#   Phase 3: resurssit (mineraalit, luolareunit, järvet — EI hiekkaa)
#   Phase 4: kasvillisuus — poistettu käytöstä (kivipinnalla ei kasvualustaa)
class_name WorldGen

const MAT_EMPTY        := 0
const MAT_SAND         := 1
const MAT_WATER        := 2
const MAT_STONE        := 3
const MAT_WOOD         := 4
const MAT_FIRE         := 5
const MAT_OIL          := 6
const MAT_STEAM        := 7
const MAT_ASH          := 8
const MAT_WOOD_FALLING := 9
const MAT_DIRT         := 11
const MAT_IRON_ORE     := 12
const MAT_GOLD_ORE     := 13
const MAT_COAL         := 16
const MAT_GRAVEL       := 18  # Sora — kiven murskautuessa syntyvä jauhe
const MAT_BEDROCK      := 19  # Pohjakivi — tuhoamaton reunakerros
const MAT_COPPER       := 20  # Kupari — malmisuoni, keskisyvä
const MAT_RARE_EARTH   := 21  # Rare earth — malmisuoni, syvin ja arvokkain

const EDGE_THICKNESS := 2

# --- Planeetta (rullattu maailma, SPEC_planet P2) ---
# x = kulma planeetan ympäri → wräppää (x=0 ja x=w-1 ovat naapureita),
# y = syvyys kohti ydintä → EI wräppää.
# Korkeuskohina näytteistetään ympyrältä tällä säteellä, jotta pinnan profiili
# on jatkuva x-akselin ympäri (gx=0 ja gx=gw-1 vierekkäin ympyrällä → sauma
# on huomaamaton). Isompi säde = tiheämpi vaihtelu planeetan ympäri.
const NOISE_CIRCLE_R := 220.0
# Bedrock-ydinrenkaan alku suhteessa korkeuteen: syvimmät (1-CORE_BEDROCK_FRAC)
# osuus riveistä on tuhoamatonta ydinkuorta. v1: bedrock alkaa 85 % syvyydestä.
const CORE_BEDROCK_FRAC := 0.85


# Wräppää x-koordinaatin välille [0, w). Toimii myös negatiivisille.
# Paikallinen apuri (vastaa PlanetGeom.wrap_x-konventiota, P1) — pidetään
# world_gen.gd itsenäisenä ennen merge-junaa, ei riippuvuutta planet_geom.gd:hen.
static func _wrap_x(x: int, w: int) -> int:
	return ((x % w) + w) % w

# Kertymien lukumäärä — enemmän ja tasaisemmin jaettu
# (coal/iron/gold: nyt suonien lukumäärä _place_vein_set():lle, ei enää blobeja)
static var coal_count:  int = 12
static var iron_count:  int = 10
static var gold_count:  int = 5
static var oil_count:   int = 5
static var water_count: int = 5
static var sand_count:  int = 6
static var copper_count:      int = 7  # Uusi malmi — suoni
static var rare_earth_count:  int = 3  # Uusi malmi — suoni, harvinaisin

# Mineraalien syvyysalueet — laajennettu pintaan asti
# (coal/iron/gold: suonen ALOITUSpisteen syvyysvyöhyke, ks. _place_vein_set)
static var coal_depth:     float = 0.00   # Hiiltä jo pinnasta asti
static var coal_depth_max: float = 0.35
static var iron_depth:     float = 0.10   # Rautaa lähes pinnalta
static var iron_depth_max: float = 0.55
static var gold_depth:     float = 0.55   # Kultaa vasta syvemmältä
static var gold_depth_max: float = 0.90
static var oil_depth:      float = 0.30   # Öljyä jo välimaastosta
static var oil_depth_max:  float = 1.0
static var sand_depth:     float = 0.0
static var sand_depth_max: float = 0.25
static var copper_depth:      float = 0.35
static var copper_depth_max:  float = 0.75
static var rare_earth_depth:      float = 0.75
static var rare_earth_depth_max:  float = 1.0

# Kertymien säderajat — käytössä enää vain blobiksi jäävillä aineilla (öljy/hiekka).
# coal/iron/gold -säteet säilytetään debug_menu-yhteensopivuuden vuoksi mutta eivät
# enää vaikuta generointiin (korvattu suonien thickness/vein_len-arvoilla alla).
static var coal_r_min:  float = 16.0
static var coal_r_max:  float = 45.0
static var iron_r_min:  float = 14.0
static var iron_r_max:  float = 42.0
static var gold_r_min:  float = 16.0
static var gold_r_max:  float = 60.0
static var oil_r_min:   float = 14.0
static var oil_r_max:   float = 50.0
static var sand_r_min:  float = 14.0
static var sand_r_max:  float = 26.0

# Suonien pituus (askelta) ja paksuus (px) — data-driven per malmi (spec 1.3)
static var coal_vein_len_min:  int = 40
static var coal_vein_len_max:  int = 70
static var coal_thickness_min: float = 2.0
static var coal_thickness_max: float = 3.0
static var iron_vein_len_min:  int = 35
static var iron_vein_len_max:  int = 60
static var iron_thickness_min: float = 2.0
static var iron_thickness_max: float = 3.0
static var copper_vein_len_min:  int = 30
static var copper_vein_len_max:  int = 50
static var copper_thickness_min: float = 2.0
static var copper_thickness_max: float = 2.0
static var gold_vein_len_min:  int = 25
static var gold_vein_len_max:  int = 40
static var gold_thickness_min: float = 1.0
static var gold_thickness_max: float = 2.0
static var rare_earth_vein_len_min:  int = 20
static var rare_earth_vein_len_max:  int = 35
static var rare_earth_thickness_min: float = 1.0
static var rare_earth_thickness_max: float = 2.0

# Suonen mutkittelu (heading += randf_range(-x,x) per askel) ja haaroitustodennäköisyys
static var vein_wiggle: float = 0.35
static var vein_branch_chance: float = 0.06

# Satunnainen kokovaihtelu per kertymiä (0=kiinteä, 1=±100%)
static var size_variance: float = 0.25
# Ellipsin epäsymmetria ja reunan epäsäännöllisyys — pienempi = siistimpi/pyöreämpi
static var perturb_strength: float = 0.18

# Multakerroksen paksuus (px)
static var dirt_thickness: int = 5

# ============================================================
# Tehdasalusta (factory platform) — tasainen alue kartan keskellä
# pinnan tasossa, jonne base + koneet sijoitetaan (GDD luku 5.2).
# Nämä lasketaan uudelleen generate():ssa todellisen w/h:n mukaan.
# Oletukset vastaavat 1664×960-maailmaa.
# ============================================================
static var platform_w: int = 300          # alustan leveys px
static var platform_x0: int = 682         # vasen reuna px (w/2 - platform_w/2)
static var platform_y: int = 384          # alustan PINNAN y-taso px (h*0.40)
static var platform_thickness: int = 6    # ohut STONE-perustus alustan alla px

# Yhteensopivuusmuuttujat debug_menu.gd:lle (ei käytetä itse generoinnissa)
static var surface_height_ratio: float = 0.40  # Approx pinnan korkeus normalisoituna
static var dune_threshold: float = 0.52         # Ei aktiivinen — hiekkavyöt kovakoodattu
static var dune_max_height: int = 5             # Ei aktiivinen
static var tree_chance: float = 0.0             # Puut toteutetaan myöhemmin

# Luolastoparametrit (domain-warped noise threshold)
static var cave_threshold_min: float = 0.45   # Threshold pinnalla — cv < -threshold (isompi = vähemmän)
static var cave_threshold_max: float = 0.22   # Threshold pohjassa (pienempi = enemmän luolia syvällä)
static var cave_warp_str:      float = 38.0   # Domain warp -voima (px) — isompi = enemmän mutkia

# Järvien asetukset
static var lake_count: int = 2
static var lake_w_min: int = 80
static var lake_w_max: int = 130
static var lake_d_min: int = 30
static var lake_d_max: int = 50


static func generate(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	var world_seed := randi()
	grid.fill(MAT_EMPTY)
	for i in grid.size():
		color_seed[i] = randi() % 256

	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 100

	# Perturbaatiodata — orgaaniset reunat
	var perturb_data: PackedByteArray = _noise_to_bytes(_make_noise(world_seed + 5, 0.04, 2), w, h)

	# Phase 1: Maasto
	var surface_y := _generate_terrain(grid, w, h, world_seed)

	# Bedrock-ydinrengas: syvimmät rivit tuhoamattomaksi ydinkuoreksi ENNEN
	# malmien/suonien sijoitusta → suonet carvaavat vain STONEen ja pysähtyvät
	# renkaaseen (eivät ylikirjoita bedrockia; renkaan alle ei jää mineraaleja).
	_enforce_core(grid, w, h)

	# Phase 2: Luolat — poistettu käytöstä
	var cave_paths: Array = []
	# var cave_paths := _generate_caves(grid, w, h, surface_y, rng)

	# max_dp = arvioidun pinnan alapuolinen pikselimäärä (normalisointiperustan varten)
	var max_dp := float(h) * 0.60

	# Phase 3: Resurssit — arvokkain ensin (ei ylikirjoita)
	# Malmit (COAL/IRON_ORE/COPPER/GOLD_ORE/RARE_EARTH) sijoitetaan mutkittelevina
	# suonina (_place_vein_set) — syvemmällä = arvokkaampaa. Vesi/öljy pysyvät
	# ellipsiblobeina (_place_deposit_set). Hiekka on poistettu pelistä.
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_OIL,
		oil_count, oil_depth, oil_depth_max,
		oil_r_min, oil_r_max, max_dp)
	_place_vein_set(grid, w, h, surface_y, rng, perturb_data, MAT_RARE_EARTH,
		rare_earth_count, rare_earth_depth, rare_earth_depth_max,
		rare_earth_vein_len_min, rare_earth_vein_len_max,
		rare_earth_thickness_min, rare_earth_thickness_max, max_dp)
	_place_vein_set(grid, w, h, surface_y, rng, perturb_data, MAT_GOLD_ORE,
		gold_count, gold_depth, gold_depth_max,
		gold_vein_len_min, gold_vein_len_max,
		gold_thickness_min, gold_thickness_max, max_dp)
	_place_vein_set(grid, w, h, surface_y, rng, perturb_data, MAT_COPPER,
		copper_count, copper_depth, copper_depth_max,
		copper_vein_len_min, copper_vein_len_max,
		copper_thickness_min, copper_thickness_max, max_dp)
	# Vesitaskut vain syvälle (min 0.35 norm. syvyys) — pintakerros pysyy kuivana kivenä.
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_WATER,
		water_count, 0.35, 0.70, 8.0, 16.0, max_dp)
	_place_vein_set(grid, w, h, surface_y, rng, perturb_data, MAT_IRON_ORE,
		iron_count, iron_depth, iron_depth_max,
		iron_vein_len_min, iron_vein_len_max,
		iron_thickness_min, iron_thickness_max, max_dp)
	_place_vein_set(grid, w, h, surface_y, rng, perturb_data, MAT_COAL,
		coal_count, coal_depth, coal_depth_max,
		coal_vein_len_min, coal_vein_len_max,
		coal_thickness_min, coal_thickness_max, max_dp)
	_place_cave_edge_deposits(grid, w, h, surface_y, rng, perturb_data, cave_paths)
	# Järvet poistettu käytöstä: _place_lakes sijoitti vesialtaita suoraan pintaan.
	# Pintakerros pysyy nyt pelkkänä kiinteänä kivenä (ei pintavettä eikä hiekkaa).
	# rng.seed = world_seed + 201
	# _place_lakes(grid, w, h, rng, surface_y)

	# Phase 4: Kasvillisuus — poistettu käytöstä. Pinta on pelkkää kiveä, joten
	# ruoholle/pensaille ei ole multa-kasvualustaa (_grow_vegetation etsii MAT_DIRT).

	# Viimeistely: leimaa puhdas tehdasalusta (poistaa mahdolliset malmit/
	# kasvit alustan päältä ja varmistaa ehjän STONE-perustuksen)
	_stamp_platform(grid, w, h)

	# M5: takuu-rautasuoni alustan kylkeen pintaan — kokenut pelaaja näkee heti
	# näkyvän louhintakohteen johon vetää kaivuualueen (SPEC_seed_ship M5).
	_place_starter_iron_vein(grid, w, h, surface_y, perturb_data, rng)

	var empty_count := 0
	for i in grid.size():
		if grid[i] == MAT_EMPTY:
			empty_count += 1
	print("Maailma generoitu (seed:%d tyhjää:%.0f%%)" % [world_seed,
		float(empty_count) / float(w * h) * 100.0])


# ============================================================
# Phase 1: Maaston luonti — ruudukkoon snapattu kivipinta
#
# Pinta lasketaan designaatio-/navigaatiogridin solukoossa (16 px):
#   1. Loiva matalataajuinen kohina → korkeus per grid-sarake, snapattuna
#      lähimpään solurajaan → tasaiset osuudet asettuvat gridilinjoille.
#   2. Vierekkäisten sarakkeiden korkeusero pakotetaan enintään yhteen soluun,
#      joten kaikki siirtymät ovat 45° viisteitä (puolikkaan solun kolmio) —
#      ei pystysuoria jyrkänteitä. Näin louhinnan aloitus pysyy siistinä
#      ruudukossa, jossa kaikki mukailee gridiä.
#   3. Pinta täytetään pelkällä kivellä (ei multaa, ei hiekkaa).
# ============================================================
static func _generate_terrain(grid: PackedByteArray, w: int, h: int,
		world_seed: int) -> PackedFloat32Array:
	var cell := 16                             # px — sama solukoko kuin DesignationGrid/NavGrid
	var gw := w / cell                         # grid-sarakkeita (1664/16 = 104)

	var base_y := float(h) * 0.40              # 384 px = solurivi 24 (16-jaollinen)
	var base_cell := int(round(base_y / float(cell)))

	# Loiva matalataajuinen profiili → "lähes tasainen" pinta
	var noise := _make_noise(world_seed + 1, 0.003, 2)
	var amp_cells := 2.0                        # korkeusvaihtelu ± ~2 solua (±32 px)

	# Snapattu korkeus (soluina) per grid-sarake.
	# Sylinterijatkuvuus: kohina näytteistetään yksikköympyrältä (cos/sin(ang)),
	# jolloin profiili on periodinen x:n ympäri → gx=0 ja gx=gw-1 ovat vierekkäin
	# ympyrällä eikä saumaan synny korkeushyppäystä (vrt. suora get_noise_2d(cx,0)).
	var top_cell := PackedInt32Array()
	top_cell.resize(gw)
	for gx in gw:
		var ang := float(gx) / float(gw) * TAU
		var nx := cos(ang) * NOISE_CIRCLE_R
		var ny := sin(ang) * NOISE_CIRCLE_R
		var n := noise.get_noise_2d(nx, ny)  # -1..1, jatkuva ympyrällä
		top_cell[gx] = base_cell + int(round(n * amp_cells))

	# --- Tehdasalusta: pakota alustan sarakkeet pinnan perustasoon ---
	platform_y = base_cell * cell
	platform_x0 = w / 2 - platform_w / 2
	var plat_gx0 := maxi(platform_x0 / cell, 0)
	var plat_gx1 := mini((platform_x0 + platform_w) / cell, gw - 1)

	# Pakota vierekkäisten sarakkeiden ero enintään yhteen soluun (45° maksimikaltevuus).
	# Iteroidaan molempiin suuntiin ja pidetään alusta pinnitettynä perustasoon.
	for _pass in 4:
		for gx in range(plat_gx0, plat_gx1 + 1):
			top_cell[gx] = base_cell
		for gx in range(1, gw):
			top_cell[gx] = clampi(top_cell[gx], top_cell[gx - 1] - 1, top_cell[gx - 1] + 1)
		for gx in range(gw - 2, -1, -1):
			top_cell[gx] = clampi(top_cell[gx], top_cell[gx + 1] - 1, top_cell[gx + 1] + 1)
		# Wräppäävä tasoituspari: pakota myös sauman (gx=0 <-> gx=gw-1) korkeusero
		# enintään yhteen soluun, jotta sylinterin ensimmäinen ja viimeinen sarake
		# jatkuvat saumatta (testi: korkeusero x=0 ja x=W-1 välillä ≤ 1 solu).
		top_cell[0] = clampi(top_cell[0], top_cell[gw - 1] - 1, top_cell[gw - 1] + 1)
		top_cell[gw - 1] = clampi(top_cell[gw - 1], top_cell[0] - 1, top_cell[0] + 1)
	for gx in range(plat_gx0, plat_gx1 + 1):
		top_cell[gx] = base_cell

	# --- Per-pikseli pinta: lineaarinen interpolointi sarakkeiden vasempien
	# reunojen korkeuksien välillä → tasaiset osuudet gridilinjoilla,
	# 45° viisteet siirtymissä (viisteen solu jää puoliksi täyteen). ---
	var surface_y := PackedFloat32Array()
	surface_y.resize(w)
	for x in w:
		var gx := x / cell
		var gx1 := mini(gx + 1, gw - 1)
		var frac := float(x - gx * cell) / float(cell)
		var y0 := float(top_cell[gx] * cell)
		var y1 := float(top_cell[gx1] * cell)
		surface_y[x] = round(lerpf(y0, y1, frac))

	# Täytä maailma: pinnasta alaspäin pelkkää kiveä (siisti kivipinta, ei multaa).
	for y in h:
		for x in w:
			if float(y) < surface_y[x]:
				continue
			grid[y * w + x] = MAT_STONE

	_enforce_edges(grid, w, h)
	return surface_y


# ============================================================
# Phase 2: Luolastot — domain-warped noise threshold
#
# Sen sijaan että piirretään ympyröitä polun varrelle, käytetään
# 2D noise-kenttää jonka koordinaatit on ensin "vääristetty" toisella
# noise-kentällä (domain warping). Tämä tuottaa automaattisesti
# orgaanisia, mutkittelevia luolastoja ilman näkyviä ympyrä-artefakteja.
#
# abs(cave_noise(warp(x,y))) < threshold → luola
# Threshold kasvaa syvyyden mukaan → enemmän/isompia luolia syvällä.
# ============================================================
static func _generate_caves(grid: PackedByteArray, w: int, h: int,
		surface_y: PackedFloat32Array,
		rng: RandomNumberGenerator) -> Array:

	var cave_pixels: Array[Vector2i] = []

	var edge := EDGE_THICKNESS

	# --- Domain-warped noise threshold ---
	# Kolme noise-kenttää: kaksi warp-kenttää + yksi pääluola-noise
	# Taajuus 1.0 objektissa, skaalataan manuaalisesti → ei double-frequency
	var warp_x := _make_noise(rng.randi(), 1.0, 3)
	var warp_y := _make_noise(rng.randi(), 1.0, 3)
	var cave_n := _make_noise(rng.randi(), 1.0, 4)

	var warp_freq  := 0.005   # warp-kentän taajuus — pehmeät laajat kierteet
	var cave_freq  := 0.009   # pienempi taajuus = isommat luolat
	var warp_str   := cave_warp_str  # domain warp -voima (px)

	for y in range(0, h - edge):
		for x in range(edge, w - edge):
			var sy: float = surface_y[clampi(x, 0, w - 1)]
			# Pintakerros suojattu — ei luolia lähellä pintaa
			if float(y) < sy + 35.0:
				continue

			var depth_t: float = clampf((float(y) - sy) / (float(h) - sy), 0.0, 1.0)

			# Domain warping: warp-koordinaatit ennen päänoiseea
			var fx := float(x) * warp_freq
			var fy := float(y) * warp_freq
			var wx: float = float(x) + warp_x.get_noise_2d(fx,        fy       ) * warp_str
			var wy: float = float(y) + warp_y.get_noise_2d(fx + 31.7, fy + 91.3) * warp_str

			# Pääluola-arvo vääristetyissä koordinaateissa
			var cv: float = cave_n.get_noise_2d(wx * cave_freq, wy * cave_freq)

			# Threshold: matala pinnalla, kasvaa syvyyteen → enemmän tilaa syvällä
			var threshold: float = cave_threshold_min + depth_t * (cave_threshold_max - cave_threshold_min)

			# cv < -threshold: ottaa vain syvimmät kuopat noise-kentästä
			# → isot orgaaniset luolat, ei ohutta verkkoa
			if cv < -threshold:
				var idx := y * w + x
				if grid[idx] == MAT_STONE or grid[idx] == MAT_DIRT:
					grid[idx] = MAT_EMPTY
					cave_pixels.append(Vector2i(x, y))

	# --- Pintasisäänkäynnit: 3 kuilua laaksonpohjissa ---
	# Kaivetaan alas kunnes saavutetaan luola tai max syvyys
	var entry_sections: Array = [[80, 530], [540, 1120], [1130, 1580]]
	for sec in entry_sections:
		var x_min: int = sec[0]
		var x_max: int = sec[1]
		var best_x: int = x_min
		var best_sy := 0.0
		for tx in range(x_min, x_max, 5):
			if surface_y[tx] > best_sy:
				best_sy = surface_y[tx]
				best_x = tx
		var ex: int = clampi(best_x + rng.randi_range(-15, 15), x_min + 4, x_max - 4)
		var ey: int = int(surface_y[clampi(ex, 0, w - 1)])

		# Kiinteä yläosa (suuaukko, 20px)
		for dy in range(0, 20):
			_carve_circle(grid, w, h, ex, ey + dy, 4)

		# Jatka alaspäin kunnes osutaan luolaan
		var max_shaft := int(float(h) * 0.72)
		var py2 := ey + 20
		while py2 < max_shaft:
			var found := false
			for cx2 in range(ex - 8, ex + 9):
				if cx2 >= 0 and cx2 < w and grid[py2 * w + cx2] == MAT_EMPTY:
					found = true
					break
			_carve_circle(grid, w, h, ex, py2, 3)
			cave_pixels.append(Vector2i(ex, py2))
			if found:
				break
			py2 += 1

	return [cave_pixels]


# Apufunktio: carve ympyrä tietyllä säteellä
static func _carve_circle(grid: PackedByteArray, w: int, h: int,
		cx: int, cy: int, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var px := cx + dx
			var py := cy + dy
			if px < EDGE_THICKNESS or px >= w - EDGE_THICKNESS:
				continue
			if py < 0 or py >= h:
				continue
			var pidx := py * w + px
			if grid[pidx] == MAT_STONE or grid[pidx] == MAT_DIRT:
				grid[pidx] = MAT_EMPTY


# ============================================================
# Phase 3a: Pintahiekan sijoitus
# - Pinnan hiekkavyöt sijoittuvat laaksoihin (korkea surface_y)
# - Maanalaisia hiekkatasku pinnalle asti syvemmällä olevissa kuopissa
# ============================================================
static func _place_surface_sand(grid: PackedByteArray, w: int, h: int,
		surface_y: PackedFloat32Array,
		rng: RandomNumberGenerator) -> void:

	# Löydä kaksi laaksonpohjaa (maksimi surface_y = alin pinta = laakso)
	# Etsi paikallisia maksimeja jotka ovat tarpeeksi erillään
	var valley_centers: Array[int] = []
	var search_regions: Array = [[100, 700], [800, 1550]]
	for reg in search_regions:
		var best_x: int = reg[0]
		var best_sy := 0.0
		for x in range(reg[0], reg[1]):
			if surface_y[x] > best_sy:
				best_sy = surface_y[x]
				best_x = x
		# Satunnainen offset jotta ei aina täsmälleen samassa kohdassa
		valley_centers.append(clampi(best_x + rng.randi_range(-60, 60),
			EDGE_THICKNESS + 1, w - EDGE_THICKNESS - 1))

	var dune_noise := _make_noise(rng.randi(), 0.025, 2)

	for cx in valley_centers:
		var belt_w: int = rng.randi_range(130, 220)
		var x_start := clampi(cx - belt_w / 2, EDGE_THICKNESS + 1, w - EDGE_THICKNESS - 1)
		var x_end   := clampi(cx + belt_w / 2, EDGE_THICKNESS + 1, w - EDGE_THICKNESS - 1)

		for x in range(x_start, x_end + 1):
			var sy := int(surface_y[x])

			# Korvaa DIRT ja STONE hiekalla pintakerroksen syvyydeltä
			for dy in range(0, dirt_thickness + 3):
				var py := sy + dy
				if py < 0 or py >= h:
					continue
				var pidx := py * w + x
				if grid[pidx] == MAT_DIRT or grid[pidx] == MAT_STONE:
					grid[pidx] = MAT_SAND

			# Dyynit — noise-korkeus, muodostaa harjanteita laakson reunoilla
			var n_val := (dune_noise.get_noise_2d(float(x), 0.0) + 1.0) * 0.5
			var dune_h := int(n_val * 20.0)
			for dy in range(1, dune_h + 1):
				var py := sy - dy
				if py < 0 or py >= h:
					continue
				if grid[py * w + x] == MAT_EMPTY:
					grid[py * w + x] = MAT_SAND

	# Maanalaiset hiekkatasku — pinnanläheisissä syvyyksissä (0.03–0.25 norm)
	# Sijoitetaan laaksojen alle jotta niistä pääsee kaivamaan ylöspäin
	var max_dp := float(h) * 0.60
	_place_deposit_set(grid, w, h, surface_y, rng, _noise_to_bytes(_make_noise(rng.randi(), 0.04, 2), w, h),
		MAT_SAND, sand_count, 0.03, 0.25, sand_r_min, sand_r_max, max_dp)


# ============================================================
# Phase 3b: Luolien reunojen lähelle sijoitettavat esiintymät
# Per luolasto: öljy- ja hiilitasku syvemmälle osalle
# ============================================================
static func _place_cave_edge_deposits(grid: PackedByteArray, w: int, h: int,
		surface_y: PackedFloat32Array,
		rng: RandomNumberGenerator,
		perturb_data: PackedByteArray,
		cave_paths: Array) -> void:
	for path in cave_paths:
		# Suodata pisteet jotka ovat tarpeeksi syvällä
		var deep_points: Array[Vector2i] = []
		for pt: Vector2i in path:
			if pt.y > int(surface_y[clampi(pt.x, 0, w - 1)]) + 40:
				deep_points.append(pt)

		if deep_points.size() < 5:
			continue  # Ei tarpeeksi syviä pisteitä

		# Valitse öljytasku syvemmältä puoliskolta
		var half_start := deep_points.size() / 2
		var oil_idx := rng.randi_range(half_start, deep_points.size() - 1)
		var oil_pt  := deep_points[oil_idx]
		var oil_r   := rng.randi_range(3, 6)
		_place_single_deposit(grid, w, h, oil_pt.x, oil_pt.y, MAT_OIL, oil_r, perturb_data)

		# Valitse hiilitasku toisesta pisteestä syvemmältä puoliskolta
		var coal_idx := rng.randi_range(half_start, deep_points.size() - 1)
		var coal_pt  := deep_points[coal_idx]
		var coal_r   := rng.randi_range(3, 6)
		_place_single_deposit(grid, w, h, coal_pt.x, coal_pt.y, MAT_COAL, coal_r, perturb_data)


# Pieni ellipsiblob yksittäistä esiintymää varten
static func _place_single_deposit(grid: PackedByteArray, w: int, h: int,
		cx: int, cy: int, mat: int, r: int,
		perturb_data: PackedByteArray) -> void:
	var scan := r + 4
	for dy in range(-scan, scan + 1):
		for dx in range(-scan, scan + 1):
			var px := cx + dx
			var py := cy + dy
			if px < EDGE_THICKNESS or px >= w - EDGE_THICKNESS:
				continue
			if py < 0 or py >= h:
				continue
			var pidx := py * w + px
			if grid[pidx] != MAT_STONE:
				continue
			var fdx := float(dx)
			var fdy := float(dy)
			var ell_dist := sqrt(fdx * fdx + fdy * fdy) / float(r)
			var pn := float(perturb_data[pidx]) / 128.0 - 1.0  # -1..+1
			if ell_dist < 1.0 + pn * perturb_strength:
				grid[pidx] = mat


# ============================================================
# Phase 4: Kasvillisuuden kasvatus
# Ruoho (WOOD-pikselit) ja pensaat (WOOD-blobeja)
# ============================================================
static func _grow_vegetation(grid: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator) -> void:
	# --- Ruoho ---
	for x in range(EDGE_THICKNESS + 1, w - EDGE_THICKNESS - 1):
		# Etsi korkein DIRT-pikseli (pienin y jossa grid == MAT_DIRT)
		var sy := -1
		for y in range(1, h - EDGE_THICKNESS - 1):
			if grid[y * w + x] == MAT_DIRT:
				sy = y
				break

		if sy < 0:
			continue
		# Tarkista ettei ole luolan katto (alla pitää olla maa)
		if sy + 1 < h and grid[(sy + 1) * w + x] == MAT_EMPTY:
			continue

		if rng.randf() < 0.55:
			var korkeus := rng.randi_range(1, 3)
			for dy in range(1, korkeus + 1):
				var py := sy - dy
				if py < 0:
					break
				if grid[py * w + x] == MAT_EMPTY:
					grid[py * w + x] = MAT_WOOD

	# --- Pensaat ---
	var last_bush_x := -100
	for x in range(EDGE_THICKNESS + 2, w - EDGE_THICKNESS - 2):
		# Etsi korkein DIRT
		var sy := -1
		for y in range(1, h - EDGE_THICKNESS - 1):
			if grid[y * w + x] == MAT_DIRT:
				sy = y
				break

		if sy < 0:
			continue
		# Tarkista ettei ole luolan katto
		if sy + 1 < h and grid[(sy + 1) * w + x] == MAT_EMPTY:
			continue
		# Minimietäisyys edelliseen pensaaseen
		if x - last_bush_x < 12:
			continue

		if rng.randf() < 0.08:
			var saade := rng.randi_range(3, 5)
			var bush_h := rng.randi_range(2, 4)

			# Carve blob ellipsinä
			for dy in range(-bush_h, 1):
				for dx in range(-saade, saade + 1):
					var bx := x + dx
					var by := sy + dy
					if bx < EDGE_THICKNESS + 1 or bx >= w - EDGE_THICKNESS - 1:
						continue
					if by < 0 or by >= h:
						continue
					# Elliptinen etäisyystarkistus
					var norm_x := float(dx) / float(saade)
					var norm_y := float(dy) / float(bush_h)
					if sqrt(norm_x * norm_x + norm_y * norm_y) < 1.0:
						if grid[by * w + bx] == MAT_EMPTY:
							grid[by * w + bx] = MAT_WOOD
			last_bush_x = x


# ============================================================
# Apufunktiot (säilytetään identtisinä)
# ============================================================

static func _make_noise(seed_val: int, freq: float, octaves: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_FBM if octaves > 1 else FastNoiseLite.FRACTAL_NONE
	n.fractal_octaves = octaves
	n.frequency = freq
	n.seed = seed_val
	return n


static func _noise_to_bytes(noise: FastNoiseLite, w: int, h: int) -> PackedByteArray:
	var img := noise.get_image(w, h)
	img.convert(Image.FORMAT_L8)
	return img.get_data()


# Sijoita N kertymää orgaanisina ellipsiblobeina
# Koko kasvaa syvyyden kasvaessa (r_min=pinta, r_max=pohja)
static func _place_deposit_set(grid: PackedByteArray, w: int, h: int,
		surface_y: PackedFloat32Array, rng: RandomNumberGenerator,
		perturb_data: PackedByteArray, mat: int,
		count: int, min_dn: float, max_dn: float,
		r_min: float, r_max: float, max_depth_px: float) -> void:

	var eff_w    := w - EDGE_THICKNESS * 4
	var section_w := float(eff_w) / float(count)

	for i in count:
		# X: osiokohtainen — tasainen leveysjakauma
		var x0 := EDGE_THICKNESS * 2 + int(section_w * float(i))
		var x1 := mini(EDGE_THICKNESS * 2 + int(section_w * float(i + 1)) - 1,
			w - EDGE_THICKNESS * 2 - 1)
		var cx := rng.randi_range(x0, x1)

		# Y: satunnainen syvyysvyöhykkeellä
		var dn := rng.randf_range(min_dn, max_dn)
		var sy := surface_y[clampi(cx, 0, w - 1)]
		var cy := clampi(int(sy + dn * max_depth_px), int(sy) + 2, h - EDGE_THICKNESS - 1)

		# Koko kasvaa syvyyden mukaan + satunnainen vaihtelu
		var t      := (dn - min_dn) / maxf(max_dn - min_dn, 0.001)
		var r_base := lerpf(r_min, r_max, t)
		var r      := r_base * (1.0 + rng.randf_range(-size_variance, size_variance))
		r = maxf(r, 3.0)

		# Satunnainen ellipsi — vaihtelevia leveys/korkeus-suhteita
		var ax      := r * rng.randf_range(0.6, 1.8)
		var ay      := r * rng.randf_range(0.5, 1.4)
		var rot     := rng.randf_range(0.0, PI)
		var cos_rot := cos(rot)
		var sin_rot := sin(rot)

		var scan := int(maxf(ax, ay)) + 6
		for dy in range(-scan, scan + 1):
			for dx in range(-scan, scan + 1):
				var px := cx + dx
				var py := cy + dy
				if px < EDGE_THICKNESS or px >= w - EDGE_THICKNESS:
					continue
				if py < 0 or py >= h:
					continue
				var pidx := py * w + px
				if grid[pidx] != MAT_STONE:
					continue

				# Kierretty elliptinen etäisyys
				var fdx := float(dx)
				var fdy := float(dy)
				var rx := fdx * cos_rot + fdy * sin_rot
				var ry := -fdx * sin_rot + fdy * cos_rot
				var ell_dist: float = sqrt((rx / ax) * (rx / ax) + (ry / ay) * (ry / ay))

				# Reunaperturbaatio orgaanista muotoa varten
				var pn := float(perturb_data[pidx]) / 128.0 - 1.0  # -1..+1
				if ell_dist < 1.0 + pn * perturb_strength:
					grid[pidx] = mat


# ============================================================
# Mineraalisuonet — worm-walk-algoritmi (syvyyspohjainen arvo)
# Jokainen suoni alkaa satunnaisesta x-osiosta ja syvyysvyöhykkeen mukaisesta
# y-pisteestä, etenee alaspäin painottuneeseen satunnaissuuntaan mutkitellen,
# ja carvaa ohuen käytävän VAIN kiveen (ei ylikirjoita muita malmeja/multaa/
# bedrockia). Pieni todennäköisyys haaroittua kerran per suoni (branch_depth<1).
# ============================================================
static func _place_vein_set(grid: PackedByteArray, w: int, h: int,
		surface_y: PackedFloat32Array, rng: RandomNumberGenerator,
		perturb_data: PackedByteArray, mat: int,
		count: int, depth_min: float, depth_max: float,
		vein_len_min: int, vein_len_max: int,
		thickness_min: float, thickness_max: float,
		max_depth_px: float) -> void:

	var eff_w      := w - EDGE_THICKNESS * 4
	var section_w  := float(eff_w) / float(count)

	for i in count:
		# Aloitus-x: osiokohtainen — suonet leviävät tasaisesti kartan levyydelle
		var x0 := EDGE_THICKNESS * 2 + int(section_w * float(i))
		var x1 := mini(EDGE_THICKNESS * 2 + int(section_w * float(i + 1)) - 1,
			w - EDGE_THICKNESS * 2 - 1)
		var start_x := rng.randi_range(x0, x1)

		# Aloitus-y: satunnainen syvyysvyöhykkeellä (0=pinta, 1=pohja)
		var dn := rng.randf_range(depth_min, depth_max)
		var sy := surface_y[clampi(start_x, 0, w - 1)]
		var start_y := clampf(sy + dn * max_depth_px, sy + 2.0, float(h - EDGE_THICKNESS - 1))

		# Alaspäin painotettu satunnaissuunta: ~90° (suoraan alas) ± vaihtelu
		var heading := PI * 0.5 + rng.randf_range(-0.9, 0.9)
		var vein_len := rng.randi_range(vein_len_min, vein_len_max)
		var thickness := rng.randf_range(thickness_min, thickness_max)

		_walk_vein(grid, w, h, float(start_x), start_y, heading, vein_len,
			thickness, mat, perturb_data, rng, 0)


# Yksittäisen suonen (tai haaran) kävely: carvaa ellipsipoikkileikkauksen joka
# askeleella, mutkittelee heading-kulmaa satunnaisesti, ja voi haaroittaa
# pienellä todennäköisyydellä (vain kerran, branch_depth < 1).
static func _walk_vein(grid: PackedByteArray, w: int, h: int,
		start_cx: float, start_cy: float, start_heading: float, steps: int,
		thickness: float, mat: int, perturb_data: PackedByteArray,
		rng: RandomNumberGenerator, branch_depth: int) -> void:

	var cx := start_cx
	var cy := start_cy
	var heading := start_heading

	for _step in steps:
		_carve_vein_disc(grid, w, h, cx, cy, thickness, mat, perturb_data)

		# Haaroitus: pieni todennäköisyys, vain kerran per suoni (ei rekursiota loputtomiin)
		if branch_depth < 1 and rng.randf() < vein_branch_chance:
			var sub_len := maxi(6, steps / 2)
			var sub_heading := heading + rng.randf_range(-1.2, 1.2)
			_walk_vein(grid, w, h, cx, cy, sub_heading, sub_len,
				thickness * 0.65, mat, perturb_data, rng, branch_depth + 1)

		# Mutkittelu + eteneminen suuntaan
		heading += rng.randf_range(-vein_wiggle, vein_wiggle)
		cx += cos(heading)
		cy += sin(heading)

		# Clamp reunoihin — lopeta jos suoni ajautuu reunan tai pohjan ulkopuolelle
		if cx < float(EDGE_THICKNESS + 2) or cx >= float(w - EDGE_THICKNESS - 2):
			break
		if cy < 0.0 or cy >= float(h - EDGE_THICKNESS - 2):
			break
		# Lopeta bedrockissa
		if grid[int(cy) * w + int(cx)] == MAT_BEDROCK:
			break


# Carvaa pienen ellipsin (suonen poikkileikkaus) VAIN MAT_STONE-soluihin —
# ei ylikirjoita muita malmeja, multaa, ilmaa tai bedrockia.
static func _carve_vein_disc(grid: PackedByteArray, w: int, h: int,
		cx: float, cy: float, radius: float, mat: int,
		perturb_data: PackedByteArray) -> void:
	var scan := int(ceil(radius)) + 2
	var icx  := int(cx)
	var icy  := int(cy)
	for dy in range(-scan, scan + 1):
		var py := icy + dy
		if py < 0 or py >= h:
			continue
		for dx in range(-scan, scan + 1):
			var px := icx + dx
			if px < EDGE_THICKNESS or px >= w - EDGE_THICKNESS:
				continue
			var pidx := py * w + px
			if grid[pidx] != MAT_STONE:
				continue

			var fdx := float(px) - cx
			var fdy := float(py) - cy
			var dist := sqrt(fdx * fdx + fdy * fdy)

			# Reunaperturbaatio orgaanista muotoa varten (kuten blob-esiintymissä)
			var pn := float(perturb_data[pidx]) / 128.0 - 1.0  # -1..+1
			if dist < radius + pn * perturb_strength * radius:
				grid[pidx] = mat


# ============================================================
# Tehdasalusta: puhdas tasainen alue + ohut STONE-perustus.
# - Yläpuoli tyhjennetään (EMPTY) → siisti ilmatila alustan päälle.
# - Alustan pinnasta platform_thickness px alaspäin = STONE-perustus.
# BEDROCKia ei ylikirjoiteta (reunasuoja).
# ============================================================
static func _stamp_platform(grid: PackedByteArray, w: int, h: int) -> void:
	var x_start := maxi(platform_x0, EDGE_THICKNESS)
	var x_end   := mini(platform_x0 + platform_w, w - EDGE_THICKNESS)
	for x in range(x_start, x_end):
		# Tyhjennä alustan yläpuoli (poistaa kasvit/dyynit/roskat)
		for y in range(0, platform_y):
			var idx := y * w + x
			if grid[idx] != MAT_BEDROCK:
				grid[idx] = MAT_EMPTY
		# STONE-perustus alustan pinnasta alaspäin
		for y in range(platform_y, mini(platform_y + platform_thickness, h)):
			var fidx := y * w + x
			if grid[fidx] != MAT_BEDROCK:
				grid[fidx] = MAT_STONE


# ============================================================
# M5: Takuu-rautasuoni alustan kylkeen pintaan.
# Kokenut pelaaja saa heti näkyvän louhintakohteen: lyhyt IRON_ORE-suoni
# alkaa juuri alustan oikean reunan ULKOPUOLELTA ja ulottuu pinnasta matalaan
# syvyyteen (osittain pinnassa, näkyvissä alustan vierestä). Käyttää samaa
# _walk_vein/_carve_vein_disc-koneistoa kuin muut suonet: carvaa VAIN
# MAT_STONE-soluihin, joten se EI ylikirjoita alustan STONE-perustusta,
# bedrockia eikä muita malmeja. Sijainti on deterministinen (perustuu alustan
# reunaan + pinnan korkeuteen), joten suoni syntyy joka seedillä samaan kohtaan.
# ============================================================
static func _place_starter_iron_vein(grid: PackedByteArray, w: int, h: int,
		surface_y: PackedFloat32Array, perturb_data: PackedByteArray,
		rng: RandomNumberGenerator) -> void:
	# Aloitus-x juuri alustan oikean reunan ulkopuolelta — näkyvä alustan vierestä.
	var start_x := clampi(platform_x0 + platform_w + 40, EDGE_THICKNESS + 4,
		w - EDGE_THICKNESS - 4)
	# Aloita aivan pinnasta (suonen latva näkyy pinnassa) ja kävele alas matalaan
	# syvyyteen. Suonen paksuus 3 px -> latva ulottuu pintakiveen asti.
	var sy := surface_y[clampi(start_x, 0, w - 1)]
	var start_y := clampf(sy + 3.0, sy + 2.0, float(h - EDGE_THICKNESS - 2))
	# Lähes pystysuora (~90° alas) pieni satunnaisvaihtelu -> suoni pysyy alustan
	# vieressä matalalla (surface + ~0…40 px).
	var heading := PI * 0.5 + rng.randf_range(-0.25, 0.25)
	_walk_vein(grid, w, h, float(start_x), start_y, heading, 34, 3.0,
		MAT_IRON_ORE, perturb_data, rng, 0)

	# --- Pintapaljastuma: tiheä IRON_ORE-laikku alustan oikealle puolelle ---
	# Pelkkä suoni on ohut ja osittain pinnan alla; sen viereen lisätään leveä,
	# maanpinnassa NÄKYVÄ malmilaikku josta pelaaja saa heti runsaasti rautaa.
	# Sijainti on kokonaan alustan oikean reunan ULKOPUOLELLA (x > alustan reuna),
	# joten se ei kosketa alustan STONE-perustusta eikä basea. Muoto seuraa
	# maanpintaa (per-sarake surface_y). Korvaa VAIN kiinteät maasolut
	# (STONE/DIRT/GRAVEL) — EI ilmaa (ei kelluvaa malmia) eikä bedrockia.
	var exp_x0 := clampi(platform_x0 + platform_w + 8, EDGE_THICKNESS + 2,
		w - EDGE_THICKNESS - 2)
	var exp_x1 := clampi(platform_x0 + platform_w + 44, EDGE_THICKNESS + 2,
		w - EDGE_THICKNESS - 2)
	for px in range(exp_x0, exp_x1 + 1):
		# Ylin täytettävä rivi = pintakivi (col_sy), jotta laikun latva näkyy pinnassa.
		var col_sy := int(surface_y[clampi(px, 0, w - 1)])
		# Syvyys ~12–16 px + kevyt per-sarake reunakohina (deterministinen rng-virta,
		# kutsutaan aina viimeisenä generointivaiheena → ei häiritse muuta gen:iä).
		var col_depth := 14 + rng.randi_range(-2, 2)
		for dy in range(0, col_depth):
			var py := col_sy + dy
			if py < 0 or py >= h - EDGE_THICKNESS:
				continue
			var pidx := py * w + px
			var cur := grid[pidx]
			if cur == MAT_STONE or cur == MAT_DIRT or cur == MAT_GRAVEL:
				grid[pidx] = MAT_IRON_ORE


# Tehdasalustan alue sim-pikseleinä; position.y = alustan pinnan y-taso.
# Korkeus = ohut STONE-perustus (perustuslaatan paksuus). Integraatio sijoittaa
# basen ja koneet alustan pinnalle (rect.position.y).
static func get_platform_rect() -> Rect2i:
	return Rect2i(platform_x0, platform_y, platform_w, platform_thickness)


static func _enforce_edges(grid: PackedByteArray, w: int, h: int) -> void:
	# Sylinterimaailmassa x wräppää (x=0 ja x=w-1 ovat naapureita), joten
	# pystysuoraa x-reunabedrockia EI kirjoiteta — se loisi näkyvän seinän
	# saumaan. Vain pohjabedrock (alin kerros kohti ydintä) säilyy; varsinainen
	# bedrock-ydinrengas hoidetaan erikseen _enforce_core():ssa.
	for x in w:
		for y in range(h - EDGE_THICKNESS, h):
			grid[y * w + x] = MAT_BEDROCK


# ============================================================
# Bedrock-ydinrengas: syvimmät rivit (CORE_BEDROCK_FRAC..1.0 syvyydestä) ovat
# tuhoamatonta bedrockia. Rullatussa maailmassa tämä on planeetan ydinkuori,
# jonka sisään renderöinti (P5) piirtää irrallisen ydinmöhkäleen. Suonet/blobit
# carvaavat/korvaavat vain MAT_STONEa eivätkä ylikirjoita bedrockia, joten ne
# pysähtyvät luonnostaan renkaan yläreunaan. Ajetaan ENNEN malmivaiheita, jotta
# renkaan alle ei jää mineraaleja.
# ============================================================
static func _enforce_core(grid: PackedByteArray, w: int, h: int) -> void:
	var core_y0 := int(float(h) * CORE_BEDROCK_FRAC)
	for y in range(core_y0, h):
		for x in w:
			grid[y * w + x] = MAT_BEDROCK


# Järvet: 2 kpl, reunamarginaalilla
static func _place_lakes(grid: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, surface_y: PackedFloat32Array) -> void:
	var margin      := 30
	var min_spacing := lake_w_max
	var placed: Array[int] = []

	# Tehdasalustan alue + reunapuskuri — järviä ei sijoiteta tänne
	var plat_lo := platform_x0 - lake_w_max / 2
	var plat_hi := platform_x0 + platform_w + lake_w_max / 2

	var attempts := 0
	while placed.size() < lake_count and attempts < 300:
		attempts += 1
		var cx: int = rng.randi_range(margin, w - margin - 1)

		# Estä järvet tehdasalustan päälle/alle (pidä alusta puhtaana)
		if cx > plat_lo and cx < plat_hi:
			continue

		var too_close := false
		for prev in placed:
			if abs(cx - prev) < min_spacing:
				too_close = true
				break
		if too_close:
			continue

		var lw: int = rng.randi_range(lake_w_min, lake_w_max)
		var ld: int = rng.randi_range(lake_d_min, lake_d_max)
		var radius := float(lw) / 2.0

		for dx in range(-int(radius), int(radius) + 1):
			var lx: int = cx + dx
			if lx < EDGE_THICKNESS or lx >= w - EDGE_THICKNESS:
				continue
			var t      := float(dx) / radius
			var col_d: int = int(float(ld) * (1.0 - t * t))
			if col_d <= 0:
				continue
			var surf: int = int(surface_y[lx])
			for dy in range(0, col_d):
				var ly: int = surf + dy
				if ly >= 0 and ly < h:
					grid[ly * w + lx] = MAT_EMPTY
			for dy in range(1, col_d):
				var ly: int = surf + dy
				if ly >= 0 and ly < h:
					grid[ly * w + lx] = MAT_WATER
		placed.append(cx)
