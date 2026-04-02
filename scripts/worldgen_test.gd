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
