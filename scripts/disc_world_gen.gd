class_name DiscWorldGen
extends RefCounted

# Kiekkoplaneetan maailmageneraattori (docs/SPEC_disc_planet.md, Vaihe 2A).
#
# Tuottaa yhden PackedInt32Array-gridin, jossa jokainen solu on pakattu muotoon
#   (seed << 8) | material_id
# aivan kuten simulation.glsl / world_gen.gd:n soluformaatti. Ylatavun seed antaa
# renderoinnille per-solu-variaation.
#
# Kerrokset lasketaan etaisyyden r = DiscGeom.radius_of mukaan (syvyys d = r_planet - r):
#   r > r_planet             -> EMPTY (avaruus)
#   r_planet-dirt < r        -> DIRT  (ohut pintakerros)
#   r_core   < r < ...       -> STONE + malmisuonet syvyyden mukaan
#   r < r_core               -> BEDROCK (tuhoamaton ydin)
#
# Malmit sijoitetaan blob-suonina FastNoiseLitella (prototyyppitaso riittaa):
# jokaisella malmilla oma noise-kentta + syvyysvyohyke, joten syvemmalla loytyy
# arvokkaampaa (IRON matala, COAL keski, GOLD syva, COPPER/RARE_EARTH syvimmalla).
#
# Determinismi: sama seed_val (+ sama n) -> identtinen grid. Seed vaikuttaa
# noise-kenttiin ja per-solu-seediin, ei mihinkaan ei-deterministiseen lahteeseen.
#
# Geometria haetaan jaetusta perustasta (scripts/disc_geom.gd). Preloadataan
# eksplisiittisella polulla, jotta luokka toimii myos ilman class-cache-importtia.

const Geom = preload("res://scripts/disc_geom.gd")

# --- Kerrospaksuudet taydella 1408-gridilla (skaalataan n:n mukaan) ---
const DIRT_THICKNESS_FULL := 24.0   # pintamullan paksuus px (r_planet-skaalassa)

# --- Malmivyohykkeet: normalisoitu kivisyvyys dn in [0,1] (0 = pinnan alla,
# 1 = ytimen reunalla). Vyohykkeet tarkistetaan matalimmasta syvimpaan ja
# ensimmainen osuma voittaa (pieni limitys pehmentaa rajoja luonnollisesti). ---
# Rakenne: [material, dn_min, dn_max, noise_threshold(0..255), noise_offset]
# Threshold on korkea matalille (harvat isot suonet) ja matalampi syville
# (pienempi pinta-ala ytimen lahella -> tarvitaan tiheampi jotta osuus > 0.5 %).
const ORE_TABLE := [
	[Geom.MAT_IRON_ORE,   0.00, 0.38, 190, 11],
	[Geom.MAT_COAL,       0.34, 0.56, 176, 23],
	[Geom.MAT_GOLD_ORE,   0.52, 0.70, 166, 37],
	[Geom.MAT_COPPER,     0.66, 0.85, 156, 53],
	[Geom.MAT_RARE_EARTH, 0.82, 1.00, 148, 71],
]

# Malminoise-taajuus taydella gridilla. Skaalataan 1/s:lla jotta blobien
# suhteellinen koko (period / n) pysyy samana pienemmillakin grideilla.
const ORE_NOISE_FREQ_FULL := 0.045


# Generoi kiekkomaailma. Palauttaa n*n-kokoisen PackedInt32Arrayn.
# Solu = (seed << 8) | material_id. Tyhjat (avaruus) solut ovat 0.
static func generate(seed_val: int, n: int = Geom.GRID_N) -> PackedInt32Array:
	var grid := PackedInt32Array()
	grid.resize(n * n)  # resize nollaa -> koko avaruus on valmiiksi EMPTY (0)

	# Skaalaa sateet gridin koon mukaan (testit ajavat pienella n:lla nopeuden vuoksi).
	var s := float(n) / float(Geom.GRID_N)
	var r_planet := float(Geom.R_PLANET) * s
	var r_core := float(Geom.R_CORE) * s
	var dirt_thickness := DIRT_THICKNESS_FULL * s
	# Kiven ylareunan sade (mullan alla) ja kiven radiaalinen laajuus (dn-normalisointiin).
	var r_stone_top := r_planet - dirt_thickness
	var stone_span := maxf(r_stone_top - r_core, 1.0)

	# Malminoise-kentat: yksi L8-kuva per malmi. Taajuus skaalataan 1/s:lla.
	var ore_freq := ORE_NOISE_FREQ_FULL / maxf(s, 0.0001)
	var ore_noise: Array[PackedByteArray] = []
	for ore in ORE_TABLE:
		ore_noise.append(_noise_bytes(seed_val + int(ore[4]), ore_freq, n))

	# Paalapikaynti: solukeskipiste-symmetria kuten DiscGeom (dxc = 2x-(n-1)).
	# Inline-matikka (ei per-solu-funktiokutsua) — identtinen DiscGeom.radius_of:n kanssa.
	var n1 := n - 1
	for y in n:
		var dyc := 2 * y - n1
		var dyc2 := dyc * dyc
		var row := y * n
		for x in n:
			var dxc := 2 * x - n1
			var r := sqrt(float(dxc * dxc + dyc2)) * 0.5
			if r > r_planet:
				continue  # avaruus -> jaa EMPTY (0)

			var idx := row + x
			var mat: int

			if r < r_core:
				mat = Geom.MAT_BEDROCK
			else:
				var d := r_planet - r
				if d < dirt_thickness:
					mat = Geom.MAT_DIRT
				else:
					# Kivi + mahdollinen malmisuoni syvyysvyohykkeen mukaan.
					mat = Geom.MAT_STONE
					var dn := (d - dirt_thickness) / stone_span  # 0 = kiven ylareuna, 1 = ydin
					for oi in ORE_TABLE.size():
						var ore = ORE_TABLE[oi]
						if dn >= ore[1] and dn < ore[2] and ore_noise[oi][idx] > int(ore[3]):
							mat = ore[0]
							break

			grid[idx] = (_seed_byte(idx, seed_val) << 8) | mat

	return grid


# --- Apurit -----------------------------------------------------------------

# Deterministinen per-solu-seedtavu (0..255) idx:sta ja world-seedista. Antaa
# valkoista kohinaa (naapurisolut eri seedeja) renderoinnin variaatiota varten.
static func _seed_byte(idx: int, seed_val: int) -> int:
	var h := idx * 374761393 + seed_val * 2246822519 + 3266489917
	h = (h ^ (h >> 15)) * 2654435761
	h = h ^ (h >> 13)
	return h & 0xFF


# Rakenna FastNoiseLite-kentta ja palauta L8-tavut (0..255) n*n-gridille.
static func _noise_bytes(seed_val: int, freq: float, n: int) -> PackedByteArray:
	var nz := FastNoiseLite.new()
	nz.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	nz.fractal_type = FastNoiseLite.FRACTAL_FBM
	nz.fractal_octaves = 3
	nz.frequency = freq
	nz.seed = seed_val
	var img := nz.get_image(n, n)
	if img.get_format() != Image.FORMAT_L8:
		img.convert(Image.FORMAT_L8)
	return img.get_data()
