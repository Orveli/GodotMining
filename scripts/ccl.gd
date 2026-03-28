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
static func check_connectivity(pixels: Array[Vector2i]) -> Array:
	if pixels.is_empty():
		return []

	# Luo pikselijoukko nopeaa hakua varten
	var pixel_set: Dictionary = {}
	for p in pixels:
		pixel_set[p] = true

	var visited: Dictionary = {}
	var components: Array = []

	for p in pixels:
		if visited.has(p):
			continue

		# BFS tästä pikselistä (indeksipohjainen jono suorituskyvyn vuoksi)
		var component: Array[Vector2i] = []
		var queue: Array[Vector2i] = [p]
		var head := 0
		visited[p] = true

		while head < queue.size():
			var current := queue[head]
			head += 1
			component.append(current)

			# 4-suuntaiset naapurit
			var neighbors: Array[Vector2i] = [
				Vector2i(current.x - 1, current.y),
				Vector2i(current.x + 1, current.y),
				Vector2i(current.x, current.y - 1),
				Vector2i(current.x, current.y + 1),
			]

			for n in neighbors:
				if pixel_set.has(n) and not visited.has(n):
					visited[n] = true
					queue.append(n)

		components.append(component)

	return components
