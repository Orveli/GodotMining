# Maailmageneraattori — Terraria-tyylinen kerrosmaailma + worm-luolat
# Pintaprofiili: h*0.45, pieni vaihteluväli ±4 pikseliä
# Kerrokset: taivas → multa (6px) → kivi → syvä kivi
# Järvet: 2-3 kappaletta pinnalla, pyöristetty kaivanto
class_name WorldGen

const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_WATER := 2
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_OIL := 6
const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13

const EDGE_THICKNESS := 2
static var tree_chance: float = 0.10
static var sand_threshold: float = 0.55
static var water_threshold: float = 0.60
static var oil_threshold: float = 0.72
static var worm_freq: float = 0.015
static var chamber_freq: float = 0.01
static var surface_freq: float = 0.02
static var worm_threshold: float = 0.35
static var chamber_threshold: float = 0.30
static var iron_freq: float = 0.12
static var gold_freq: float = 0.15


static func generate(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	var world_seed := randi()

	grid.fill(MAT_EMPTY)
	for i in grid.size():
		color_seed[i] = randi() % 256

	# === Noise-kerrokset ===

	# Worm caves: abs(n1) + abs(n2) → tunneleita missä molemmat lähellä nollaa
	var worm1 := FastNoiseLite.new()
	worm1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	worm1.frequency = WorldGen.worm_freq
	worm1.seed = world_seed

	var worm2 := FastNoiseLite.new()
	worm2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	worm2.frequency = WorldGen.worm_freq
	worm2.seed = world_seed + 1

	# Kammiot
	var chamber := FastNoiseLite.new()
	chamber.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	chamber.frequency = WorldGen.chamber_freq
	chamber.seed = world_seed + 2

	# Pintaprofiili: matala frekvenssi — pitkät loivat mäet
	var surface_low := FastNoiseLite.new()
	surface_low.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_low.frequency = 0.008
	surface_low.seed = world_seed + 3

	# Pintaprofiili: korkea frekvenssi — pienet kivet ja kuopat
	var surface_high := FastNoiseLite.new()
	surface_high.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_high.frequency = 0.05
	surface_high.seed = world_seed + 4

	# Materiaalinoiset
	var sand_noise := FastNoiseLite.new()
	sand_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	sand_noise.frequency = 0.07
	sand_noise.seed = world_seed + 10

	var water_noise := FastNoiseLite.new()
	water_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	water_noise.frequency = 0.06
	water_noise.seed = world_seed + 20

	var oil_noise := FastNoiseLite.new()
	oil_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	oil_noise.frequency = 0.08
	oil_noise.seed = world_seed + 30

	var iron_noise := FastNoiseLite.new()
	iron_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	iron_noise.frequency = WorldGen.iron_freq
	iron_noise.seed = world_seed + 40

	var gold_noise := FastNoiseLite.new()
	gold_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gold_noise.frequency = WorldGen.gold_freq
	gold_noise.seed = world_seed + 50

	# === Maanpintaprofiili ===
	# Pohja h*0.45, pienet aallot kahdella noise-kerroksella (max ±4-5 pikseliä)
	var surface_y := PackedFloat32Array()
	surface_y.resize(w)
	var base_y := float(h) * 0.45
	for x in w:
		var noise_low := surface_low.get_noise_2d(float(x), 0.0)
		var noise_high := surface_high.get_noise_2d(float(x), 0.0)
		surface_y[x] = base_y + noise_low * 3.0 + noise_high * 1.5

	# === Vaihe 1: Kerrokset + worm-luolat ===
	var worm_t := WorldGen.worm_threshold
	var chamber_t := WorldGen.chamber_threshold

	for y in h:
		for x in w:
			var idx := y * w + x
			var sy := surface_y[x]

			# Taivas: maan yläpuolella = tyhjää
			if float(y) < sy:
				continue

			# Syvyys maanpinnasta (0.0 = pinta, ~0.55 = pohja kun pinta on 0.45)
			var depth := (float(y) - sy) / float(h)

			# Multakerros: pintakerros ennen kiveä (6 pikseliä)
			if float(y) < sy + 6.0:
				grid[idx] = MAT_DIRT
				continue

			# Worm-luolat: ei kaiverra ihan pintaan (depth > 0.05)
			if depth > 0.05:
				var w1 := absf(worm1.get_noise_2d(float(x), float(y)))
				var w2 := absf(worm2.get_noise_2d(float(x), float(y)))
				var worm_val := w1 + w2

				# Kammiot: vain riittävällä syvyydellä (depth > 0.15)
				var is_chamber := false
				if depth > 0.15:
					var ch := chamber.get_noise_2d(float(x), float(y))
					is_chamber = ch > chamber_t

				# Syvemmällä hieman tiiviimpi
				worm_val += depth * 0.06

				# Tunneli TAI kammio = tyhjää, muuten kiveä
				if worm_val < worm_t or is_chamber:
					continue  # Jää tyhjäksi

			# Kivi täyttää loput
			grid[idx] = MAT_STONE

	# === Vaihe 2: Reunat (vasen/oikea/ala — ylä auki) ===
	_enforce_edges(grid, w, h)

	# === Vaihe 3: Pienet erilliset luolat → täytä kivellä ===
	_fill_tiny_caves(grid, w, h)

	# === Vaihe 3b: Poista leijuvat kivisaarekkeet ===
	_remove_floating_stone(grid, w, h)

	# === Vaihe 4: Järvet pinnalle ===
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed + 200
	_place_lakes(grid, w, h, rng, surface_y)

	# === Vaihe 5: Materiaalit kiveen ===
	_place_materials(grid, sand_noise, oil_noise, iron_noise, gold_noise, w, h)

	# === Vaihe 6: Vesitaskut (maanalaiset, depth > 0.20) ===
	_place_water_pools(grid, water_noise, w, h)

	# === Vaihe 7: Puut ===
	_grow_trees(grid, w, h, world_seed)

	# Tilastot
	var empty_count := 0
	for i in grid.size():
		if grid[i] == MAT_EMPTY:
			empty_count += 1
	var ratio := float(empty_count) / float(w * h) * 100.0
	print("Maailma generoitu (seed: %d, tyhjää: %.0f%%)" % [world_seed, ratio])


# Reunakivi: vasen, oikea, ala — ylä auki
static func _enforce_edges(grid: PackedByteArray, w: int, h: int) -> void:
	for y in h:
		for x in w:
			if x < EDGE_THICKNESS or x >= w - EDGE_THICKNESS:
				if float(y) > float(h) * 0.45:  # Vain maan alla
					grid[y * w + x] = MAT_STONE
			if y >= h - EDGE_THICKNESS:
				grid[y * w + x] = MAT_STONE


# Täytä pienet erilliset tyhjät alueet kivellä (< 100 pikseliä)
static func _fill_tiny_caves(grid: PackedByteArray, w: int, h: int) -> void:
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)

	for y in h:
		for x in w:
			var idx := y * w + x
			if grid[idx] != MAT_EMPTY or visited[idx] != 0:
				continue

			# BFS flood fill
			var region: Array[int] = []
			var queue: Array[int] = [idx]
			visited[idx] = 1

			while not queue.is_empty():
				var ci: int = queue.pop_back()
				region.append(ci)
				var cx: int = ci % w
				var cy: int = ci / w
				if cx < w - 1:
					var ni: int = ci + 1
					if visited[ni] == 0 and grid[ni] == MAT_EMPTY:
						visited[ni] = 1
						queue.append(ni)
				if cx > 0:
					var ni: int = ci - 1
					if visited[ni] == 0 and grid[ni] == MAT_EMPTY:
						visited[ni] = 1
						queue.append(ni)
				if cy < h - 1:
					var ni: int = ci + w
					if visited[ni] == 0 and grid[ni] == MAT_EMPTY:
						visited[ni] = 1
						queue.append(ni)
				if cy > 0:
					var ni: int = ci - w
					if visited[ni] == 0 and grid[ni] == MAT_EMPTY:
						visited[ni] = 1
						queue.append(ni)

			# Pienet irralliset tyhjät alueet → täytä kivellä
			if region.size() < 100:
				for ri in region:
					grid[ri] = MAT_STONE


# Poista pienet kivisaarekkeet jotka eivät kosketa reunoja
static func _remove_floating_stone(grid: PackedByteArray, w: int, h: int) -> void:
	var visited := PackedByteArray()
	visited.resize(w * h)
	visited.fill(0)

	for y in h:
		for x in w:
			var idx := y * w + x
			if grid[idx] != MAT_STONE or visited[idx] != 0:
				continue

			# BFS: etsi yhtenäinen kivialue
			var region: Array[int] = []
			var queue: Array[int] = [idx]
			visited[idx] = 1
			var touches_edge := false

			while not queue.is_empty():
				var ci: int = queue.pop_back()
				region.append(ci)
				var cx: int = ci % w
				var cy: int = ci / w
				# Koskettaako reunaa (vasen/oikea/ala)?
				if cx <= EDGE_THICKNESS or cx >= w - EDGE_THICKNESS - 1 or cy >= h - EDGE_THICKNESS - 1:
					touches_edge = true
				if cx < w - 1:
					var ni: int = ci + 1
					if visited[ni] == 0 and grid[ni] == MAT_STONE:
						visited[ni] = 1
						queue.append(ni)
				if cx > 0:
					var ni: int = ci - 1
					if visited[ni] == 0 and grid[ni] == MAT_STONE:
						visited[ni] = 1
						queue.append(ni)
				if cy < h - 1:
					var ni: int = ci + w
					if visited[ni] == 0 and grid[ni] == MAT_STONE:
						visited[ni] = 1
						queue.append(ni)
				if cy > 0:
					var ni: int = ci - w
					if visited[ni] == 0 and grid[ni] == MAT_STONE:
						visited[ni] = 1
						queue.append(ni)

			# Irralliset saarekkeet → tyhjäksi
			if not touches_edge:
				for ri in region:
					grid[ri] = MAT_EMPTY


# Järvet pinnalle: 2-3 pyöristettyä kaivantoa täytetty vedellä
static func _place_lakes(grid: PackedByteArray, w: int, h: int,
		rng: RandomNumberGenerator, surface_y: PackedFloat32Array) -> void:
	var lake_count := rng.randi_range(2, 3)
	var min_spacing := 60  # Vähintään 60 pikseliä järvien välillä
	var margin := 30       # Ei reunojen lähellä

	var placed_centers: Array[int] = []

	var attempts := 0
	while placed_centers.size() < lake_count and attempts < 200:
		attempts += 1
		var cx: int = rng.randi_range(margin, w - margin - 1)

		# Tarkista etäisyys aiempiin järviin
		var too_close := false
		for prev_cx in placed_centers:
			if abs(cx - prev_cx) < min_spacing:
				too_close = true
				break
		if too_close:
			continue

		# Järven koko
		var lake_w: int = rng.randi_range(20, 35)
		var lake_d: int = rng.randi_range(8, 15)
		var radius: float = float(lake_w) / 2.0

		# Kaivan kuoppa pintaan ja täytän vedellä
		for dx in range(-int(radius), int(radius) + 1):
			var lx: int = cx + dx
			if lx < EDGE_THICKNESS or lx >= w - EDGE_THICKNESS:
				continue

			# Pyöristetty syvyys: parabolinen muoto
			var t := float(dx) / radius
			var col_depth: int = int(float(lake_d) * (1.0 - t * t))
			if col_depth <= 0:
				continue

			var surface: int = int(surface_y[lx])

			# Kaiva tyhjäksi pintakerroksesta alaspäin
			for dy in range(0, col_depth):
				var ly: int = surface + dy
				if ly < 0 or ly >= h:
					continue
				var lidx := ly * w + lx
				grid[lidx] = MAT_EMPTY

			# Täytä vedellä (ylin pikseli jää tyhjäksi ilmakuplaksi; täytetään pohjasta)
			for dy in range(1, col_depth):
				var ly: int = surface + dy
				if ly < 0 or ly >= h:
					continue
				var lidx := ly * w + lx
				grid[lidx] = MAT_WATER

		placed_centers.append(cx)


# Materiaalit: hiekka, öljy, malmi — multakerros säilyy koskemattomana
static func _place_materials(grid: PackedByteArray, sand_noise: FastNoiseLite,
		oil_noise: FastNoiseLite, iron_noise: FastNoiseLite, gold_noise: FastNoiseLite,
		w: int, h: int) -> void:
	for y in range(h - 1, -1, -1):  # Alhaalta ylös
		for x in w:
			var idx := y * w + x

			# Multakerros säilyy koskemattomana — ei ylikirjoiteta
			if grid[idx] == MAT_DIRT:
				continue

			if grid[idx] != MAT_STONE:
				continue

			# Syvyys maanpinnasta (0.0 = pinta, ~0.55 = pohja)
			var depth := float(y) / float(h)

			# Hiekka: vain syvemmällä (depth > 0.15), painotettu alaspäin
			if depth > 0.15:
				var sv: float = sand_noise.get_noise_2d(float(x), float(y))
				var y_bias: float = float(y) / float(h) * 0.15
				if sv + y_bias > WorldGen.sand_threshold:
					if y >= h - 1:
						grid[idx] = MAT_SAND
					elif grid[(y + 1) * w + x] == MAT_STONE or grid[(y + 1) * w + x] == MAT_SAND:
						grid[idx] = MAT_SAND
					continue

			# Öljy: vain syvällä (depth > 0.30)
			if depth > 0.30:
				var ov: float = oil_noise.get_noise_2d(float(x), float(y))
				if ov > WorldGen.oil_threshold:
					if y < h - 1 and grid[(y + 1) * w + x] != MAT_EMPTY:
						grid[idx] = MAT_OIL
					continue

			# Rautamalmi: depth > 0.15
			if depth > 0.15:
				var iv: float = iron_noise.get_noise_2d(float(x), float(y))
				if iv > 0.65:
					grid[idx] = MAT_IRON_ORE
					continue

			# Kultamalmi: depth > 0.40, ylikirjoittaa rautamalmin
			if depth > 0.40:
				var gv: float = gold_noise.get_noise_2d(float(x), float(y))
				if gv > 0.75:
					grid[idx] = MAT_GOLD_ORE


# Vesitaskut luolien pohjille — vain syvemmällä (depth > 0.20)
static func _place_water_pools(grid: PackedByteArray, water_noise: FastNoiseLite,
		w: int, h: int) -> void:
	# Depth 0.20 vastaa y = h * 0.20 = 36 pikseliä ylhäältä
	var min_y: int = int(float(h) * 0.20)
	for y in range(h - EDGE_THICKNESS - 1, min_y, -1):
		for x in range(EDGE_THICKNESS + 1, w - EDGE_THICKNESS - 1):
			var idx := y * w + x
			if grid[idx] != MAT_EMPTY:
				continue
			var below_idx := (y + 1) * w + x
			if y + 1 >= h or grid[below_idx] == MAT_EMPTY:
				continue
			var wv: float = water_noise.get_noise_2d(float(x), float(y))
			if wv > WorldGen.water_threshold:
				for dy in range(0, 5):
					var wy := y - dy
					if wy < 1:
						break
					var widx := wy * w + x
					if grid[widx] != MAT_EMPTY:
						break
					grid[widx] = MAT_WATER


# Puut kivi/hiekka/multapinnoilta ylöspäin + stalaktiitit katosta
static func _grow_trees(grid: PackedByteArray, w: int, h: int, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 100

	# Puut ylöspäin: kasvavat mullan, kiven tai hiekan päältä
	for x in range(EDGE_THICKNESS + 2, w - EDGE_THICKNESS - 2):
		for y in range(1, h - EDGE_THICKNESS - 1):
			var idx := y * w + x
			if grid[idx] != MAT_EMPTY:
				continue
			var below := (y + 1) * w + x
			if y + 1 >= h:
				continue
			# Multa mukaan pintamateriaalina
			if grid[below] != MAT_STONE and grid[below] != MAT_SAND and grid[below] != MAT_DIRT:
				continue
			if rng.randf() > WorldGen.tree_chance:
				continue

			var trunk_height := rng.randi_range(3, 7)
			var grew := 0
			for dy in range(0, trunk_height):
				var ty := y - dy
				if ty < 1:
					break
				var tidx := ty * w + x
				if grid[tidx] != MAT_EMPTY:
					break
				grid[tidx] = MAT_WOOD
				grew += 1

			if grew >= 3:
				var branch_y := y - grew + 1
				for bdir in [-1, 1]:
					if rng.randf() < 0.6:
						var blen := rng.randi_range(1, 3)
						for bx in range(1, blen + 1):
							var bxx: int = x + bdir * bx
							if bxx < EDGE_THICKNESS + 1 or bxx >= w - EDGE_THICKNESS - 1:
								break
							var bidx: int = branch_y * w + bxx
							if grid[bidx] != MAT_EMPTY:
								break
							grid[bidx] = MAT_WOOD

	# Stalaktiitit katosta alaspäin
	for x in range(EDGE_THICKNESS + 2, w - EDGE_THICKNESS - 2):
		for y in range(1, h - EDGE_THICKNESS - 1):
			var idx := y * w + x
			if grid[idx] != MAT_EMPTY:
				continue
			var above := (y - 1) * w + x
			if y - 1 < 0:
				continue
			if grid[above] != MAT_STONE:
				continue
			if rng.randf() > WorldGen.tree_chance * 0.5:
				continue
			var root_len := rng.randi_range(2, 5)
			for dy in range(0, root_len):
				var ry := y + dy
				if ry >= h - EDGE_THICKNESS - 1:
					break
				var ridx := ry * w + x
				if grid[ridx] != MAT_EMPTY:
					break
				grid[ridx] = MAT_WOOD
