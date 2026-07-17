# Headless maailmageneraattori-testi
# Käyttö: godot --headless --script scripts/worldgen_test.gd
# Tallentaa: debug_worldgen_preview.png
# Tulostaa: kokonaistilastot, tehdasalustan/pinnan mittaukset, malmisuonten
# tilastot + syvyysjakauma per vyöhyke, ja assert-tyyliset läpäisytarkistukset.
extends SceneTree

const W := 1664
const H := 960

# Materiaalit → värit (sama kuin pixel_render.gdshader)
const MAT_COLORS: Dictionary = {
	0:  Color("#141420"),  # EMPTY
	1:  Color("#DBC773"),  # SAND
	2:  Color("#3366D9"),  # WATER
	3:  Color("#808085"),  # STONE
	4:  Color("#734720"),  # WOOD
	5:  Color("#FF8019"),  # FIRE
	6:  Color("#332619"),  # OIL
	7:  Color("#CCD9E6"),  # STEAM
	8:  Color("#59544C"),  # ASH
	9:  Color("#734720"),  # WOOD_FALLING
	11: Color("#735129"),  # DIRT
	12: Color("#8C6B61"),  # IRON_ORE
	13: Color("#B8A640"),  # GOLD_ORE
	16: Color("#2E2B35"),  # COAL
	18: Color("#6E6E73"),  # GRAVEL
	19: Color("#3A3550"),  # BEDROCK (tumma violetti — reunojen tarkistus)
	20: Color("#B87347"),  # COPPER (patinoitunut oranssiruskea)
	21: Color("#59BFA6"),  # RARE_EARTH (hohtava sinivihreä)
}

# Malmit joita seurataan syvyysvyöhykkeittäin (nimi + ID) — jakaumataulukkoon ja assertteihin
const ORES: Array = [
	["COAL", 16],
	["IRON_ORE", 12],
	["COPPER", 20],
	["GOLD_ORE", 13],
	["RARE_EARTH", 21],
]

# Normalisointiperusta (sama kuin world_gen.gd:n max_dp)
const MAX_DP := float(H) * 0.60

func _init() -> void:
	var grid := PackedByteArray()
	grid.resize(W * H)
	var color_seed := PackedByteArray()
	color_seed.resize(W * H)

	print("Generoidaan maailma %dx%d..." % [W, H])
	WorldGen.generate(grid, color_seed, W, H)

	# Laske tilastot
	var counts: Dictionary = {}
	for i in grid.size():
		var m: int = grid[i]
		counts[m] = counts.get(m, 0) + 1

	var stone_pct := float(counts.get(3, 0)) / float(W * H) * 100.0
	var empty_pct := float(counts.get(0, 0)) / float(W * H) * 100.0
	var cave_pct  := 0.0
	# Laske luola% vain maan sisältä (ei taivas)
	var underground := 0
	var underground_empty := 0
	for y in H:
		for x in W:
			var idx := y * W + x
			# Yksinkertainen heuristiikka: kivi tai mineraali tai tyhjä kiven alapuolella
			var mat := grid[idx]
			if mat != 0 or (y > 50 and grid[maxi(0, (y-10)) * W + x] != 0):
				underground += 1
				if mat == 0:
					underground_empty += 1
	if underground > 0:
		cave_pct = float(underground_empty) / float(underground) * 100.0

	print("Kivi: %.1f%%  Tyhjää: %.1f%%  Luola-arvio: %.1f%%" % [stone_pct, empty_pct, cave_pct])

	# --- Pinnan korkeusvaihtelun mittaus ---
	# Etsi ylin ei-tyhjä ei-bedrock pikseli per sarake (= maanpinta)
	var surf_min := H
	var surf_max := 0
	var plat := WorldGen.get_platform_rect()
	for x in range(4, W - 4):
		# Ohita tehdasalustan sarakkeet erillistä mittausta varten
		if x >= plat.position.x and x < plat.position.x + plat.size.x:
			continue
		for y in range(0, H):
			var m: int = grid[y * W + x]
			if m != 0 and m != 19:
				if y < surf_min:
					surf_min = y
				if y > surf_max:
					surf_max = y
				break
	print("Pinnan y-vaihtelu (ei alusta): min=%d max=%d vaihtelu=%d px" % [surf_min, surf_max, surf_max - surf_min])
	print("Tehdasalusta: x=%d..%d  pinta y=%d  leveys=%d" % [
		plat.position.x, plat.position.x + plat.size.x, plat.position.y, plat.size.x])

	# --- Malmisuonten tilastot: esiintymä + syvyysvyöhyke (0=pinta -> 1=pohja) ---
	# Käytetään samaa syvyysnormalisoinnin perustaa kuin world_gen.gd:n max_dp.
	var surface_approx := PackedInt32Array()
	surface_approx.resize(W)
	surface_approx.fill(H)
	for x in range(4, W - 4):
		for y in range(0, H):
			var m0: int = grid[y * W + x]
			if m0 != 0 and m0 != 19:
				surface_approx[x] = y
				break

	var ore_names: Dictionary = {12: "IRON_ORE", 13: "GOLD_ORE", 16: "COAL", 20: "COPPER", 21: "RARE_EARTH"}
	var ore_stats: Dictionary = {}
	for x in range(4, W - 4):
		var sy: int = surface_approx[x]
		if sy >= H:
			continue
		for y in range(sy, H):
			var m: int = grid[y * W + x]
			if ore_names.has(m):
				var dn: float = float(y - sy) / MAX_DP
				if not ore_stats.has(m):
					ore_stats[m] = {"count": 0, "sum": 0.0, "min": 1e9, "max": -1e9}
				var st: Dictionary = ore_stats[m]
				st["count"] = int(st["count"]) + 1
				st["sum"] = float(st["sum"]) + dn
				st["min"] = minf(st["min"], dn)
				st["max"] = maxf(st["max"], dn)
				ore_stats[m] = st

	print("--- Malmisuonet (syvyys normalisoitu 0=pinta, 1=pohja) ---")
	for mid in [12, 13, 16, 20, 21]:
		var name: String = ore_names[mid]
		if ore_stats.has(mid):
			var st: Dictionary = ore_stats[mid]
			var cnt: int = st["count"]
			var pct := float(cnt) / float(W * H) * 100.0
			print("%s (id=%d): %d px (%.3f%%)  syvyys min=%.2f max=%.2f ka=%.2f" % [
				name, mid, cnt, pct, st["min"], st["max"], float(st["sum"]) / float(cnt)])
		else:
			print("%s (id=%d): 0 px — EI ESIINNY" % [name, mid])

	# --- Suonijakauma syvyysvyöhykkeittäin (taulukko) ---
	# Vyöhykkeet: normalisoitu syvyys 0.0=pinta .. 1.0=pohja (MAX_DP-perustan mukaan)
	var zone_bounds: Array = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]
	var zone_count := zone_bounds.size() - 1  # 5 vyöhykettä 0.0–1.0
	var zone_hits: Dictionary = {}   # id -> Array(zone_count+1), viimeinen = >1.0 (bedrockin lähellä)
	for entry in ORES:
		var oid: int = entry[1]
		var z := []
		for _i in range(zone_count + 1):
			z.append(0)
		zone_hits[oid] = z

	for x in range(4, W - 4):
		var sy2: int = surface_approx[x]
		if sy2 >= H:
			continue
		for y in range(sy2, H):
			var m2: int = grid[y * W + x]
			if not zone_hits.has(m2):
				continue
			var dn2: float = float(y - sy2) / MAX_DP
			var placed := false
			for zi in zone_count:
				if dn2 < zone_bounds[zi + 1]:
					zone_hits[m2][zi] += 1
					placed = true
					break
			if not placed:
				zone_hits[m2][zone_count] += 1

	print("\n=== MALMISUONTEN JAKAUMA (px per syvyysvyöhyke) ===")
	var header := "%-12s" % "Aine"
	for zi in zone_count:
		header += "%12s" % ("[%.1f-%.1f]" % [zone_bounds[zi], zone_bounds[zi + 1]])
	header += "%12s%10s" % [">1.0", "yht."]
	print(header)
	for entry in ORES:
		var ename: String = entry[0]
		var eid: int = entry[1]
		var row := "%-12s" % ename
		var z: Array = zone_hits[eid]
		var tot := 0
		for v in z:
			tot += v
		for zi in zone_count:
			row += "%12d" % z[zi]
		row += "%12d%10d" % [z[zone_count], tot]
		print(row)

	# --- Assertit ---
	print("\n=== ASSERTIT ===")
	var all_pass := true

	# 1. Jokaista malmia syntyy > 0 px
	for entry in ORES:
		var aname: String = entry[0]
		var aid: int = entry[1]
		var acnt: int = ore_stats[aid]["count"] if ore_stats.has(aid) else 0
		var ok: bool = acnt > 0
		all_pass = all_pass and ok
		print("  [%s] %s: %d px" % ["OK" if ok else "FAIL", aname, acnt])

	# 2. RARE_EARTH ei koskaan ylimmässä 60 %:ssa (norm. syvyys < 0.60)
	var rare_min: float = ore_stats[21]["min"] if ore_stats.has(21) else 999.0
	var rare_ok: bool = ore_stats.has(21) and rare_min >= 0.60
	all_pass = all_pass and rare_ok
	print("  [%s] RARE_EARTH matalin syvyys: %.2f (vaadittu >= 0.60)" %
		["OK" if rare_ok else "FAIL", rare_min])

	# 3. GOLD_ORE ei ylimmässä kolmanneksessa (norm. syvyys < 0.35)
	var gold_min: float = ore_stats[13]["min"] if ore_stats.has(13) else 999.0
	var gold_ok: bool = ore_stats.has(13) and gold_min >= 0.35
	all_pass = all_pass and gold_ok
	print("  [%s] GOLD_ORE matalin syvyys: %.2f (vaadittu >= 0.35)" %
		["OK" if gold_ok else "FAIL", gold_min])

	# 4. Ei tuntematonta materiaalia (magenta previewissä)
	var unknown := 0
	for m in counts.keys():
		if not MAT_COLORS.has(m):
			unknown += counts[m]
	var unknown_ok: bool = unknown == 0
	all_pass = all_pass and unknown_ok
	print("  [%s] Tuntemattomia (magenta) pikseleitä: %d" %
		["OK" if unknown_ok else "FAIL", unknown])

	# 5. M5: starter-rautasuoni alustan oikean reunan viereen matalaan syvyyteen.
	# Laske IRON_ORE alustan viereisella matalalla alueella (nakyva louhintakohde).
	var sv_x0: int = plat.position.x + plat.size.x            # alustan oikea reuna
	var sv_x1: int = mini(sv_x0 + 140, W)                     # + suonen alue
	var sv_y0: int = maxi(plat.position.y - 40, 0)            # hieman pinnan ylapuolelta
	var sv_y1: int = mini(plat.position.y + 90, H)            # matalaan syvyyteen
	var starter_iron := 0
	for sy_i in range(sv_y0, sv_y1):
		for sx_i in range(sv_x0, sv_x1):
			if grid[sy_i * W + sx_i] == 12:
				starter_iron += 1
	var starter_ok: bool = starter_iron > 0
	all_pass = all_pass and starter_ok
	print("  [%s] Starter-rautasuoni alustan vieressa (x=%d..%d y=%d..%d): %d px IRON_ORE" %
		["OK" if starter_ok else "FAIL", sv_x0, sv_x1, sv_y0, sv_y1, starter_iron])

	print("\nTULOS: %s" % ("KAIKKI OK" if all_pass else "VIRHEITÄ"))

	# Renderöi PNG
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		for x in W:
			var mat: int = grid[y * W + x]
			var col: Color
			if MAT_COLORS.has(mat):
				col = MAT_COLORS[mat]
			else:
				col = Color(1.0, 0.0, 1.0)  # Tuntematon materiaali = magenta
			img.set_pixel(x, y, col)

	var path := "debug_worldgen_preview.png"
	img.save_png(path)
	print("Tallennettu: " + path)
	quit()
