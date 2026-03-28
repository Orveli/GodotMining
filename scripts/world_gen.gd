# Maailmageneraattori — Worm cave -tekniikka
# abs(noise1) + abs(noise2) luo luonnollisesti yhtenäisiä tunneleita
class_name WorldGen

const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_WATER := 2
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_OIL := 6

const EDGE_THICKNESS := 2
const TREE_CHANCE := 0.10
const SAND_THRESHOLD := 0.55
const WATER_THRESHOLD := 0.60
const OIL_THRESHOLD := 0.72


static func generate(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	var world_seed := randi()

	grid.fill(MAT_EMPTY)
	for i in grid.size():
		color_seed[i] = randi() % 256

	# === Noise-kerrokset ===

	# Worm caves: abs(n1) + abs(n2) → tunneleita missä molemmat lähellä nollaa
	# Matala frekvenssi = isot, selkeät tunnelit (ei detailispagettia)
	var worm1 := FastNoiseLite.new()
	worm1.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	worm1.frequency = 0.015
	worm1.seed = world_seed

	var worm2 := FastNoiseLite.new()
	worm2.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	worm2.frequency = 0.015
	worm2.seed = world_seed + 1

	# Kammiot
	var chamber := FastNoiseLite.new()
	chamber.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	chamber.frequency = 0.01
	chamber.seed = world_seed + 2

	# Maanpintaprofiili
	var surface_n := FastNoiseLite.new()
	surface_n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	surface_n.frequency = 0.02
	surface_n.seed = world_seed + 3

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

	# === Maanpintaprofiili ===
	var surface_y := PackedFloat32Array()
	surface_y.resize(w)
	for x in w:
		var sv := surface_n.get_noise_2d(float(x), 0.0) * 0.12
		surface_y[x] = float(h) * (0.25 + sv)

	# === Vaihe 1: Kivi + worm-luolat ===
	# Kynnys: pienempi = kapeammat tunnelit, suurempi = avoimemmat
	var WORM_THRESHOLD := 0.35
	var CHAMBER_THRESHOLD := 0.30

	for y in h:
		for x in w:
			var idx := y * w + x
			var sy := surface_y[x]

			# Taivas: kaiken yläpuolella = tyhjää
			if float(y) < sy:
				continue

			# Syvyys maanpinnasta (0.0 = pinta, ~0.75 = pohja)
			var depth := (float(y) - sy) / float(h)

			# Worm-arvo: matala = tunneli, korkea = kiveä
			var w1 := absf(worm1.get_noise_2d(float(x), float(y)))
			var w2 := absf(worm2.get_noise_2d(float(x), float(y)))
			var worm_val := w1 + w2

			# Kammiot: isot avoimet tilat
			var ch := chamber.get_noise_2d(float(x), float(y))
			var is_chamber := ch > CHAMBER_THRESHOLD

			# Pintakerros: avoimempi (luonnollinen siirtymä taivaasta maahan)
			if depth < 0.06:
				worm_val -= (0.06 - depth) * 2.0

			# Syvemmällä hieman tiiviimpi
			worm_val += depth * 0.06

			# Tunneli TAI kammio = tyhjää, muuten kiveä
			if worm_val < WORM_THRESHOLD or is_chamber:
				continue  # Jää tyhjäksi
			else:
				grid[idx] = MAT_STONE

	# === Vaihe 2: Reunat (vasen/oikea/ala — ylä auki) ===
	_enforce_edges(grid, w, h)

	# === Vaihe 3: Pienet erilliset luolat → täytä kivellä ===
	# Worm caves ovat jo yhtenäisiä — täytetään vain pienet irralliset taskut
	_fill_tiny_caves(grid, w, h)

	# === Vaihe 3b: Poista leijuvat kivisaarekkeet ===
	_remove_floating_stone(grid, w, h)

	# === Vaihe 4: Materiaalit kiveen ===
	_place_materials(grid, sand_noise, oil_noise, w, h)

	# === Vaihe 5: Vesitaskut ===
	_place_water_pools(grid, water_noise, w, h)

	# === Vaihe 6: Puut ===
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
				if float(y) > float(h) * 0.25:  # Vain maan alla
					grid[y * w + x] = MAT_STONE
			if y >= h - EDGE_THICKNESS:
				grid[y * w + x] = MAT_STONE


# Täytä pienet erilliset tyhjät alueet kivellä (< 30 pikseliä)
# Ei kaiverra tunneleita — worm caves hoitaa yhtenäisyyden
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
				# Naapurit (4-suuntainen)
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


# Materiaalit: hiekka ja öljy kiveen
static func _place_materials(grid: PackedByteArray, sand_noise: FastNoiseLite,
		oil_noise: FastNoiseLite, w: int, h: int) -> void:
	for y in range(h - 1, -1, -1):  # Alhaalta ylös
		for x in w:
			var idx := y * w + x
			if grid[idx] != MAT_STONE:
				continue

			# Hiekka: painotettu alaspäin, vain jos alla tukea
			var sv: float = sand_noise.get_noise_2d(float(x), float(y))
			var y_bias: float = float(y) / float(h) * 0.15
			if sv + y_bias > SAND_THRESHOLD:
				if y >= h - 1:
					grid[idx] = MAT_SAND
				elif grid[(y + 1) * w + x] == MAT_STONE or grid[(y + 1) * w + x] == MAT_SAND:
					grid[idx] = MAT_SAND
				continue

			# Öljy: harvinainen, vain ympäröity
			var ov: float = oil_noise.get_noise_2d(float(x), float(y))
			if ov > OIL_THRESHOLD:
				if y < h - 1 and grid[(y + 1) * w + x] != MAT_EMPTY:
					grid[idx] = MAT_OIL


# Vesitaskut luolien pohjille
static func _place_water_pools(grid: PackedByteArray, water_noise: FastNoiseLite,
		w: int, h: int) -> void:
	for y in range(h - EDGE_THICKNESS - 1, 1, -1):
		for x in range(EDGE_THICKNESS + 1, w - EDGE_THICKNESS - 1):
			var idx := y * w + x
			if grid[idx] != MAT_EMPTY:
				continue
			var below_idx := (y + 1) * w + x
			if y + 1 >= h or grid[below_idx] == MAT_EMPTY:
				continue
			var wv: float = water_noise.get_noise_2d(float(x), float(y))
			if wv > WATER_THRESHOLD:
				for dy in range(0, 5):
					var wy := y - dy
					if wy < 1:
						break
					var widx := wy * w + x
					if grid[widx] != MAT_EMPTY:
						break
					grid[widx] = MAT_WATER


# Puut kivi/hiekkapinnoilta + stalaktiitit katosta
static func _grow_trees(grid: PackedByteArray, w: int, h: int, seed_val: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val + 100

	# Puut ylöspäin
	for x in range(EDGE_THICKNESS + 2, w - EDGE_THICKNESS - 2):
		for y in range(1, h - EDGE_THICKNESS - 1):
			var idx := y * w + x
			if grid[idx] != MAT_EMPTY:
				continue
			var below := (y + 1) * w + x
			if y + 1 >= h:
				continue
			if grid[below] != MAT_STONE and grid[below] != MAT_SAND:
				continue
			if rng.randf() > TREE_CHANCE:
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
			if rng.randf() > TREE_CHANCE * 0.5:
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
