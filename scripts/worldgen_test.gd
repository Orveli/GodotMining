# Headless maailmageneraattori-testi
# Käyttö: godot --headless --script scripts/worldgen_test.gd
# Tallentaa: debug_worldgen_preview.png
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

	var max_dp := float(H) * 0.60
	var ore_names: Dictionary = {12: "IRON_ORE", 13: "GOLD_ORE", 16: "COAL", 20: "COPPER", 21: "RARE_EARTH"}
	var ore_stats: Dictionary = {}
	for x in range(4, W - 4):
		var sy: int = surface_approx[x]
		if sy >= H:
			continue
		for y in range(sy, H):
			var m: int = grid[y * W + x]
			if ore_names.has(m):
				var dn: float = float(y - sy) / max_dp
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
