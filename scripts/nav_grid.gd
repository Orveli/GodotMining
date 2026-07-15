# scripts/nav_grid.gd
# Karkea navigaatiogridi lentaville boteille + A*-reititys.
# Solu = 16x16 px -> 104x60 = 6240 solmua (per-pikseli-A* olisi 1.6 M solmua = mahdoton).
# Solu on OPEN jos vahintaan 70 % sen 256 pikselista on lapaisevia (EMPTY/WATER/STEAM/FIRE).
# Lapaisevyys johdetaan CPU:lla `grid`:sta; ei lasketa joka frame vaan dirty-flag-pohjaisesti:
# louhinta/fysiikka merkitsee muuttuneet alueet mark_dirty_px_rect():lla, update_dirty()
# laskee vain likaiset solut uudelleen. Full-rebuild vain worldgenin jalkeen.
class_name NavGrid
extends RefCounted

const CELL := 16           # solun sivu pikseleina
const NW := 104            # soluja leveyssuunnassa (104*16 = 1664 px)
const NH := 60             # soluja korkeussuunnassa (60*16 = 960 px)

const SIM_W := NW * CELL   # 1664 — CA-gridin leveys (grid-indeksointi: y*SIM_W + x)
const SIM_H := NH * CELL   # 960  — CA-gridin korkeus
const PIXELS_PER_CELL := CELL * CELL  # 256

# Kuinka monen solun sateelta lahto/kohde snapataan lahimpaan OPEN-soluun.
const SNAP_RADIUS := 3

const SQRT2 := 1.4142135623730951

# A*-naapurisuunnat: 4 kardinaalia + 4 diagonaalia (diagonaali = molemmat != 0).
const _DX := [1, -1, 0, 0, 1, 1, -1, -1]
const _DY := [0, 0, 1, -1, 1, -1, 1, -1]

# Heap-avaimen koodaus: (int(f * F_SCALE) << 16) | node.
# Nain prioriteetti on upotettu heap-alkioon -> lazy-deletion ei karsi stale-f:sta.
const F_SCALE := 1024
const NODE_MASK := 0xFFFF   # node < 6240 mahtuu 16 bittiin

# Lapaisevyyskartta, indeksi cy*NW+cx. 1 = OPEN, 0 = SOLID.
var _open: PackedByteArray

# Likaiset solut (navsolu-indeksi -> true) update_dirty()-osittaispaivitysta varten.
var _dirty: Dictionary = {}

# A*-työpuskurit — allokoidaan kerran, nollataan fill():lla per haku (ei silmukan sisalla).
var _g: PackedFloat32Array       # paras tunnettu kustannus lahdosta
var _came: PackedInt32Array      # edeltaja polun rekonstruktioon
var _closed: PackedByteArray     # kasitellyt solmut


func _init() -> void:
	_open = PackedByteArray()
	_open.resize(NW * NH)
	_open.fill(0)


# --- Lapaisevyyden laskenta ------------------------------------------------

func rebuild_full(grid: PackedByteArray) -> void:
	# Laskee koko lapaisevyyskartan gridista. Kutsu worldgenin jalkeen.
	if _open.size() != NW * NH:
		_open.resize(NW * NH)
	for cy in NH:
		var row := cy * NW
		for cx in NW:
			_open[row + cx] = 1 if _cell_is_open(grid, cx, cy) else 0
	_dirty.clear()


func mark_dirty_px_rect(r: Rect2i) -> void:
	# Merkitsee pikselisuorakulmion peittamat navsolut likaisiksi.
	if r.size.x <= 0 or r.size.y <= 0:
		return
	var px0 := r.position.x
	var py0 := r.position.y
	var px1 := r.position.x + r.size.x - 1
	var py1 := r.position.y + r.size.y - 1
	if px1 < 0 or py1 < 0 or px0 >= SIM_W or py0 >= SIM_H:
		return
	var cx0 := clampi(px0 / CELL, 0, NW - 1)
	var cy0 := clampi(py0 / CELL, 0, NH - 1)
	var cx1 := clampi(px1 / CELL, 0, NW - 1)
	var cy1 := clampi(py1 / CELL, 0, NH - 1)
	for cy in range(cy0, cy1 + 1):
		var row := cy * NW
		for cx in range(cx0, cx1 + 1):
			_dirty[row + cx] = true


func update_dirty(grid: PackedByteArray) -> void:
	# Laskee vain likaiset solut uudelleen ja tyhjentaa dirty-joukon.
	if _dirty.is_empty():
		return
	if _open.size() != NW * NH:
		# Turvatarkistus: jos karttaa ei ole viela rakennettu, tee full-rebuild.
		rebuild_full(grid)
		return
	for idx in _dirty:
		var cx: int = idx % NW
		var cy: int = idx / NW
		_open[idx] = 1 if _cell_is_open(grid, cx, cy) else 0
	_dirty.clear()


func _cell_is_open(grid: PackedByteArray, cx: int, cy: int) -> bool:
	# OPEN jos >= 70 % solun 256 pikselista lapaisevaa (EMPTY=0, WATER=2, FIRE=5, STEAM=7).
	var px0 := cx * CELL
	var py0 := cy * CELL
	var passable := 0
	for y in range(py0, py0 + CELL):
		var base := y * SIM_W + px0
		for x in CELL:
			var mat := grid[base + x]
			if mat == 0 or mat == 2 or mat == 5 or mat == 7:
				passable += 1
	# passable / 256 >= 0.70  <=>  passable*100 >= 256*70 (= 17920) -> kynnys 180 pikselia.
	return passable * 100 >= PIXELS_PER_CELL * 70


# --- Kyselyt ---------------------------------------------------------------

func is_open(cx: int, cy: int) -> bool:
	if cx < 0 or cx >= NW or cy < 0 or cy >= NH:
		return false
	return _open[cy * NW + cx] == 1


func is_open_px(p: Vector2) -> bool:
	var c := _cell_of_px(p.x, p.y)
	return is_open(c.x, c.y)


# --- A* --------------------------------------------------------------------

func find_path_px(from_px: Vector2, to_px: Vector2) -> PackedVector2Array:
	# Palauttaa waypointit px-koordinaateissa (navsolujen keskipisteet). Tyhja = ei reittia.
	# Lahto/kohde snapataan lahimpaan OPEN-soluun (max ~SNAP_RADIUS solua).
	# 8-suuntainen A*; diagonaali sallittu vain jos molemmat sivunaapurit OPEN.
	var result := PackedVector2Array()
	if _open.size() != NW * NH:
		return result

	var start_cell := _snap_to_open(_cell_of_px(from_px.x, from_px.y))
	var goal_cell := _snap_to_open(_cell_of_px(to_px.x, to_px.y))
	if start_cell.x < 0 or goal_cell.x < 0:
		return result  # ei OPEN-solua tarpeeksi lahella

	var start := start_cell.y * NW + start_cell.x
	var goal := goal_cell.y * NW + goal_cell.x
	if start == goal:
		result.push_back(_cell_center(goal_cell.x, goal_cell.y))
		return result

	_ensure_scratch()
	_g.fill(INF)
	_came.fill(-1)
	_closed.fill(0)

	var heap: Array = []
	_g[start] = 0.0
	_heap_push(heap, (int(_octile(start_cell.x, start_cell.y, goal_cell.x, goal_cell.y) * F_SCALE) << 16) | start)

	var found := false
	while not heap.is_empty():
		var cur: int = _heap_pop(heap) & NODE_MASK
		if cur == goal:
			found = true
			break
		if _closed[cur] == 1:
			continue  # vanhentunut heap-alkio (lazy deletion)
		_closed[cur] = 1

		var cx: int = cur % NW
		var cy: int = cur / NW
		var g_cur := _g[cur]

		for dir in 8:
			var ncx: int = cx + _DX[dir]
			var ncy: int = cy + _DY[dir]
			if ncx < 0 or ncx >= NW or ncy < 0 or ncy >= NH:
				continue
			var nidx := ncy * NW + ncx
			if _open[nidx] == 0 or _closed[nidx] == 1:
				continue

			var diagonal: bool = _DX[dir] != 0 and _DY[dir] != 0
			if diagonal:
				# Diagonaali vain jos molemmat sivunaapurit ovat OPEN (ei kulmien lapi).
				if _open[cy * NW + ncx] == 0 or _open[ncy * NW + cx] == 0:
					continue

			var tentative := g_cur + (SQRT2 if diagonal else 1.0)
			if tentative < _g[nidx]:
				_g[nidx] = tentative
				_came[nidx] = cur
				var f := tentative + _octile(ncx, ncy, goal_cell.x, goal_cell.y)
				_heap_push(heap, (int(f * F_SCALE) << 16) | nidx)

	if not found:
		return result

	# Rekonstruoi solupolku goal -> start ja kaanna.
	var cells_path: Array[Vector2i] = []
	var node := goal
	while node != -1:
		cells_path.append(Vector2i(node % NW, node / NW))
		if node == start:
			break
		node = _came[node]
	cells_path.reverse()

	# Kevyt suoristus: poista kollineaariset valipisteet (sailyta paatepisteet ja kaanteet).
	var simplified := _simplify(cells_path)

	# Jata lahtosolu pois (botti on jo siella) — output alkaa seuraavasta waypointista.
	var first := 1 if simplified.size() >= 2 else 0
	for i in range(first, simplified.size()):
		var c: Vector2i = simplified[i]
		result.push_back(_cell_center(c.x, c.y))
	return result


func _simplify(path: Array[Vector2i]) -> Array[Vector2i]:
	# Poistaa solmut joissa suunta ei muutu. Vierekkaiset A*-solut eroavat yksikkoaskeleella,
	# joten suuntavektorien yhtasuuruus kertoo kollineaarisuudesta.
	if path.size() <= 2:
		return path
	var out: Array[Vector2i] = [path[0]]
	for i in range(1, path.size() - 1):
		var d1 := path[i] - path[i - 1]
		var d2 := path[i + 1] - path[i]
		if d1 != d2:
			out.append(path[i])
	out.append(path[path.size() - 1])
	return out


func _snap_to_open(cell: Vector2i) -> Vector2i:
	# Palauttaa lahimman OPEN-solun sateelta SNAP_RADIUS, tai (-1,-1) jos ei loydy.
	# Alkuperainen solu clampataan ensin gridiin, jotta reunan yli menevat lahtokohdat
	# mappautuvat reunasoluun.
	var ccx := clampi(cell.x, 0, NW - 1)
	var ccy := clampi(cell.y, 0, NH - 1)
	if _open[ccy * NW + ccx] == 1:
		return Vector2i(ccx, ccy)

	for radius in range(1, SNAP_RADIUS + 1):
		var best := Vector2i(-1, -1)
		var best_d := 1 << 30
		# Skannaa neliokeha sateella `radius`.
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if absi(ox) != radius and absi(oy) != radius:
					continue  # vain keha, ei sisaosaa
				var nx := ccx + ox
				var ny := ccy + oy
				if nx < 0 or nx >= NW or ny < 0 or ny >= NH:
					continue
				if _open[ny * NW + nx] == 1:
					var d := ox * ox + oy * oy
					if d < best_d:
						best_d = d
						best = Vector2i(nx, ny)
		if best.x >= 0:
			return best
	return Vector2i(-1, -1)


func _octile(ax: int, ay: int, bx: int, by: int) -> float:
	# Admissioituva 8-suunnan heuristiikka: (dx+dy) + (sqrt2 - 2)*min(dx,dy).
	var dx := absi(ax - bx)
	var dy := absi(ay - by)
	return float(dx + dy) + (SQRT2 - 2.0) * float(mini(dx, dy))


func _cell_of_px(px: float, py: float) -> Vector2i:
	# Floor-jako, jotta negatiiviset koordinaatit mappautuvat oikeaan (gridin ulkopuoliseen) soluun.
	return Vector2i(floori(px / float(CELL)), floori(py / float(CELL)))


func _cell_center(cx: int, cy: int) -> Vector2:
	return Vector2(float(cx * CELL) + CELL * 0.5, float(cy * CELL) + CELL * 0.5)


func _ensure_scratch() -> void:
	var n := NW * NH
	if _g.size() != n:
		_g.resize(n)
		_came.resize(n)
		_closed.resize(n)


# --- Binaarikeko (min-heap), avaimet koodattu (f<<16)|node ------------------

func _heap_push(heap: Array, key: int) -> void:
	heap.push_back(key)
	var i := heap.size() - 1
	while i > 0:
		var parent := (i - 1) >> 1
		if heap[i] < heap[parent]:
			var tmp: int = heap[i]
			heap[i] = heap[parent]
			heap[parent] = tmp
			i = parent
		else:
			break


func _heap_pop(heap: Array) -> int:
	var top: int = heap[0]
	var last: int = heap.pop_back()
	if not heap.is_empty():
		heap[0] = last
		var i := 0
		var n := heap.size()
		while true:
			var l := 2 * i + 1
			var r := 2 * i + 2
			var smallest := i
			if l < n and heap[l] < heap[smallest]:
				smallest = l
			if r < n and heap[r] < heap[smallest]:
				smallest = r
			if smallest == i:
				break
			var tmp: int = heap[i]
			heap[i] = heap[smallest]
			heap[smallest] = tmp
			i = smallest
	return top
