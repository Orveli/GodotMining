# scripts/wood_support.gd
# Tarkistaa puupikseleiden tuen ja muuttaa tuettomat putoaviksi
class_name WoodSupport

# Tarkista puun tuki ja muuta tuettomat MAT_WOOD -> MAT_WOOD_FALLING
static func check_support(grid: PackedByteArray, width: int, height: int) -> bool:
	# Palauttaa true jos muutoksia tehtiin
	var total := width * height
	var supported := PackedByteArray()
	supported.resize(total)
	supported.fill(0)

	# BFS-jono
	var queue: Array[int] = []

	# Vaihe 1: Etsi tukipisteet — puupikselit jotka koskettavat tukea
	# Tuki = STONE (3), maanpohja (y == height-1), tai toinen tuettu materiaali
	for y in height:
		var row := y * width
		for x in width:
			var idx := row + x
			var mat := grid[idx]
			if mat != 4:  # MAT_WOOD = 4
				continue

			# Onko tämä puu tuen vieressä?
			var has_support := false

			# Maanpohja
			if y == height - 1:
				has_support = true

			# Tarkista naapurit (4-suuntainen) — tuki = STONE tai SAND
			if not has_support and x > 0:
				var n := grid[idx - 1]
				if n == 3 or n == 1:  # STONE tai SAND
					has_support = true
			if not has_support and x < width - 1:
				var n := grid[idx + 1]
				if n == 3 or n == 1:
					has_support = true
			if not has_support and y > 0:
				var n := grid[idx - width]
				if n == 3 or n == 1:
					has_support = true
			if not has_support and y < height - 1:
				var n := grid[idx + width]
				if n == 3 or n == 1:
					has_support = true

			if has_support:
				supported[idx] = 1
				queue.append(idx)

	# Vaihe 2: BFS — levita tuki puupikseleiden lapi
	var head := 0
	while head < queue.size():
		var idx := queue[head]
		head += 1
		var x := idx % width
		var y := idx / width

		# Tarkista naapurit
		var neighbors: Array[int] = []
		if x > 0: neighbors.append(idx - 1)
		if x < width - 1: neighbors.append(idx + 1)
		if y > 0: neighbors.append(idx - width)
		if y < height - 1: neighbors.append(idx + width)

		for n_idx in neighbors:
			if supported[n_idx] == 0 and grid[n_idx] == 4:  # MAT_WOOD
				supported[n_idx] = 1
				queue.append(n_idx)

	# Vaihe 3: Muuta tuettomat puut putoaviksi
	var changed := false
	for i in total:
		if grid[i] == 4 and supported[i] == 0:  # MAT_WOOD ilman tukea
			grid[i] = 9  # MAT_WOOD_FALLING
			changed = true

	return changed
