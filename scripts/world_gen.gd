# Maailmageneraattori
# Maailman koko: 1664×960 pikseliä
# Pipeline:
#   Phase 1: _generate_terrain()          → surface_y
#   Phase 2: _generate_caves()            → cave_paths
#   Phase 3: resurssit (hiekka, mineraalit, luolareunit, järvet)
#   Phase 4: _grow_vegetation()           → ruoho + pensaat
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
const MAT_BEDROCK      := 19  # Pohjakivi — tuhoamaton reunakerros

const EDGE_THICKNESS := 2

# Kertymien lukumäärä — enemmän ja tasaisemmin jaettu
static var coal_count:  int = 10
static var iron_count:  int = 10
static var gold_count:  int = 6
static var oil_count:   int = 5
static var water_count: int = 5
static var sand_count:  int = 6

# Mineraalien syvyysalueet — laajennettu pintaan asti
static var coal_depth:     float = 0.10   # Hiiltä jo pintakerroksen alla
static var coal_depth_max: float = 1.0
static var iron_depth:     float = 0.05   # Rautaa lähes pinnalta
static var iron_depth_max: float = 0.80
static var gold_depth:     float = 0.45   # Kultaa vasta syvemmältä
static var gold_depth_max: float = 1.0
static var oil_depth:      float = 0.30   # Öljyä jo välimaastosta
static var oil_depth_max:  float = 1.0
static var sand_depth:     float = 0.0
static var sand_depth_max: float = 0.25

# Kertymien säderajat — siistit pyöreät blobeja
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

# Satunnainen kokovaihtelu per kertymiä (0=kiinteä, 1=±100%)
static var size_variance: float = 0.25
# Ellipsin epäsymmetria ja reunan epäsäännöllisyys — pienempi = siistimpi/pyöreämpi
static var perturb_strength: float = 0.18

# Multakerroksen paksuus (px)
static var dirt_thickness: int = 5

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

	# Phase 2: Luolat — poistettu käytöstä
	var cave_paths: Array = []
	# var cave_paths := _generate_caves(grid, w, h, surface_y, rng)

	# max_dp = arvioidun pinnan alapuolinen pikselimäärä (normalisointiperustan varten)
	var max_dp := float(h) * 0.60

	# Phase 3: Resurssit — arvokkain ensin (ei ylikirjoita)
	_place_surface_sand(grid, w, h, surface_y, rng)
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_OIL,
		oil_count, oil_depth, oil_depth_max,
		oil_r_min, oil_r_max, max_dp)
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_GOLD_ORE,
		gold_count, gold_depth, gold_depth_max,
		gold_r_min, gold_r_max, max_dp)
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_WATER,
		water_count, 0.20, 0.70, 8.0, 16.0, max_dp)
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_IRON_ORE,
		iron_count, iron_depth, iron_depth_max,
		iron_r_min, iron_r_max, max_dp)
	_place_deposit_set(grid, w, h, surface_y, rng, perturb_data, MAT_COAL,
		coal_count, coal_depth, coal_depth_max,
		coal_r_min, coal_r_max, max_dp)
	_place_cave_edge_deposits(grid, w, h, surface_y, rng, perturb_data, cave_paths)
	rng.seed = world_seed + 201
	_place_lakes(grid, w, h, rng, surface_y)

	# Phase 4: Kasvillisuus
	_grow_vegetation(grid, w, h, rng)

	var empty_count := 0
	for i in grid.size():
		if grid[i] == MAT_EMPTY:
			empty_count += 1
	print("Maailma generoitu (seed:%d tyhjää:%.0f%%)" % [world_seed,
		float(empty_count) / float(w * h) * 100.0])


# ============================================================
# Phase 1: Maaston luonti
# Kolme FastNoiseLite-kerrosta eri taajuuksilla
# ============================================================
static func _generate_terrain(grid: PackedByteArray, w: int, h: int,
		world_seed: int) -> PackedFloat32Array:
	var noise_low  := _make_noise(world_seed + 1, 0.003, 1)  # Alhainen taajuus
	var noise_mid  := _make_noise(world_seed + 2, 0.012, 2)  # Keski taajuus
	var noise_high := _make_noise(world_seed + 3, 0.05,  2)  # Korkea taajuus

	var base_y := float(h) * 0.40
	var surface_y := PackedFloat32Array()
	surface_y.resize(w)

	for x in w:
		var fx := float(x)
		var low  := noise_low.get_noise_2d(fx, 0.0)
		var mid  := noise_mid.get_noise_2d(fx, 0.0)
		var high := noise_high.get_noise_2d(fx, 0.0)
		# Isot amplitudit → näkyvät vuoret ja laaksot (960px korkea maailma)
		surface_y[x] = clampf(base_y + low * 90.0 + mid * 35.0 + high * 6.0,
			40.0, float(h) * 0.62)

	# Täytä maailma maastoprofiililla
	for y in h:
		for x in w:
			var idx := y * w + x
			var sy  := surface_y[x]
			if float(y) < sy:
				continue
			elif float(y) < sy + float(dirt_thickness):
				grid[idx] = MAT_DIRT
			else:
				grid[idx] = MAT_STONE

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


static func _enforce_edges(grid: PackedByteArray, w: int, h: int) -> void:
	# Kirjoitetaan bedrockia reunoihin ja pohjaan (ei kivi — bedrock on tuhoamaton)
	for y in h:
		for x in w:
			if x < EDGE_THICKNESS or x >= w - EDGE_THICKNESS:
				if float(y) > float(h) * 0.40:
					grid[y * w + x] = MAT_BEDROCK
			if y >= h - EDGE_THICKNESS:
				grid[y * w + x] = MAT_BEDROCK


# Järvet: 2 kpl, reunamarginaalilla
static func _place_lakes(grid: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, surface_y: PackedFloat32Array) -> void:
	var margin      := 30
	var min_spacing := lake_w_max
	var placed: Array[int] = []

	var attempts := 0
	while placed.size() < lake_count and attempts < 300:
		attempts += 1
		var cx: int = rng.randi_range(margin, w - margin - 1)

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
