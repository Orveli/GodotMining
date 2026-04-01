# Connected Component Labeling — Union-Find-toteutus
# Tunnistaa yhtenäiset materiaalialueet gridissä
class_name CCL

# Union-Find -tietorakenne (path compression + union by rank)
var parent: PackedInt32Array
var rank: PackedInt32Array


func _init(size: int) -> void:
	parent.resize(size)
	rank.resize(size)
	for i in size:
		parent[i] = i
		rank[i] = 0


func find(x: int) -> int:
	# Path compression
	var root := x
	while parent[root] != root:
		root = parent[root]
	# Tiivistä polku
	while parent[x] != root:
		var next := parent[x]
		parent[x] = root
		x = next
	return root


func union(a: int, b: int) -> void:
	var ra := find(a)
	var rb := find(b)
	if ra == rb:
		return
	# Union by rank
	if rank[ra] < rank[rb]:
		parent[ra] = rb
	elif rank[ra] > rank[rb]:
		parent[rb] = ra
	else:
		parent[rb] = ra
		rank[ra] += 1


# Nopea BFS-pohjainen komponenttilöytö — ei allokoi Union-Find-rakennetta koko gridille.
# Käyttää PackedByteArray visited-taulukona, O(N) ilman PackedInt32Array-initialisointia.
static func find_components_fast(grid: PackedByteArray, width: int, height: int, target_material: int) -> Dictionary:
	var total := width * height
	var visited := PackedByteArray()
	visited.resize(total)
	visited.fill(0)

	var components: Dictionary = {}
	var comp_id := 0

	for y in height:
		var row := y * width
		for x in width:
			var idx := row + x
			if grid[idx] != target_material or visited[idx] != 0:
				continue
			# BFS tästä pisteestä
			var component: Array[Vector2i] = []
			var queue: Array[int] = [idx]
			var head := 0
			visited[idx] = 1
			while head < queue.size():
				var ci: int = queue[head]
				head += 1
				var cx: int = ci % width
				var cy: int = ci / width
				component.append(Vector2i(cx, cy))
				if cx > 0 and visited[ci - 1] == 0 and grid[ci - 1] == target_material:
					visited[ci - 1] = 1
					queue.append(ci - 1)
				if cx < width - 1 and visited[ci + 1] == 0 and grid[ci + 1] == target_material:
					visited[ci + 1] = 1
					queue.append(ci + 1)
				if cy > 0 and visited[ci - width] == 0 and grid[ci - width] == target_material:
					visited[ci - width] = 1
					queue.append(ci - width)
				if cy < height - 1 and visited[ci + width] == 0 and grid[ci + width] == target_material:
					visited[ci + width] = 1
					queue.append(ci + width)
			if not component.is_empty():
				components[comp_id] = component
				comp_id += 1

	return components


# Etsi yhtenäiset komponentit tietylle materiaalille gridistä
# Palauttaa Dictionary: component_id → Array[Vector2i] (pikselien maailmakoordinaatit)
static func find_components(grid: PackedByteArray, width: int, height: int, target_material: int) -> Dictionary:
	var total := width * height
	var uf := CCL.new(total)

	# Vaihe 1: Yhdistä vierekkäiset samanmateriaalin pikselit
	for y in height:
		var row := y * width
		for x in width:
			var idx := row + x
			if grid[idx] != target_material:
				continue

			# Vasen naapuri
			if x > 0 and grid[idx - 1] == target_material:
				uf.union(idx, idx - 1)
			# Ylänaapuri
			if y > 0 and grid[idx - width] == target_material:
				uf.union(idx, idx - width)

	# Vaihe 2: Kerää komponentit
	var components: Dictionary = {}  # root → Array[Vector2i]
	for y in height:
		var row := y * width
		for x in width:
			var idx := row + x
			if grid[idx] != target_material:
				continue
			var root := uf.find(idx)
			if not components.has(root):
				components[root] = [] as Array[Vector2i]
			components[root].append(Vector2i(x, y))

	return components


# Tarkista yhden kappaleen yhteys — onko se vielä yhtenäinen?
# pixels = kappaleen pikselit maailmakoordinaateissa
# Palauttaa Array of Array[Vector2i] — jokainen on yksi yhtenäinen komponentti
# Käyttää AABB-pohjaista flat PackedByteArray:ta Dictionary-haun sijaan (merkittävästi nopeampaa)
static func check_connectivity(pixels: Array[Vector2i]) -> Array:
	if pixels.is_empty():
		return []

	# Laske pikselien AABB
	var min_x := pixels[0].x
	var min_y := pixels[0].y
	var max_x := pixels[0].x
	var max_y := pixels[0].y
	for p in pixels:
		if p.x < min_x: min_x = p.x
		if p.y < min_y: min_y = p.y
		if p.x > max_x: max_x = p.x
		if p.y > max_y: max_y = p.y

	var flat_w: int = max_x - min_x + 1
	var flat_h: int = max_y - min_y + 1

	# Merkitse kappaleen pikselit flat arrayhyn (1 = kuuluu kappaleeseen)
	var pixel_flat := PackedByteArray()
	pixel_flat.resize(flat_w * flat_h)
	for p in pixels:
		pixel_flat[(p.y - min_y) * flat_w + (p.x - min_x)] = 1

	# Visited-array — nolla = ei käyty, ykkönen = käyty
	var visited_flat := PackedByteArray()
	visited_flat.resize(flat_w * flat_h)

	var components: Array = []

	for p in pixels:
		var start_idx: int = (p.y - min_y) * flat_w + (p.x - min_x)
		if visited_flat[start_idx] != 0:
			continue

		# BFS flat-indekseillä — ei Vector2i-allokointia jonossa
		var component_indices: Array[int] = []
		var queue: Array[int] = [start_idx]
		var head := 0
		visited_flat[start_idx] = 1

		while head < queue.size():
			var cur_idx: int = queue[head]
			head += 1
			component_indices.append(cur_idx)

			# Muunna flat-indeksi suhteellisiksi koordinaateiksi
			var lx: int = cur_idx % flat_w
			var ly: int = cur_idx / flat_w

			# Vasen
			if lx > 0:
				var ni: int = cur_idx - 1
				if pixel_flat[ni] != 0 and visited_flat[ni] == 0:
					visited_flat[ni] = 1
					queue.append(ni)
			# Oikea
			if lx < flat_w - 1:
				var ni: int = cur_idx + 1
				if pixel_flat[ni] != 0 and visited_flat[ni] == 0:
					visited_flat[ni] = 1
					queue.append(ni)
			# Ylös
			if ly > 0:
				var ni: int = cur_idx - flat_w
				if pixel_flat[ni] != 0 and visited_flat[ni] == 0:
					visited_flat[ni] = 1
					queue.append(ni)
			# Alas
			if ly < flat_h - 1:
				var ni: int = cur_idx + flat_w
				if pixel_flat[ni] != 0 and visited_flat[ni] == 0:
					visited_flat[ni] = 1
					queue.append(ni)

		# Muunna flat-indeksit takaisin Vector2i-maailmakoordinaateiksi
		var component: Array[Vector2i] = []
		component.resize(component_indices.size())
		for i in component_indices.size():
			var fi: int = component_indices[i]
			component[i] = Vector2i(fi % flat_w + min_x, fi / flat_w + min_y)

		components.append(component)

	return components
