class_name DiscCpuCa
extends RefCounted

# CPU-referenssi kiekkoplaneetan sektorigravitaatio-CA:lle (docs/SPEC_disc_planet.md Vaihe 1B).
# Peilaa simulation_disc.glsl:n sääntöjä sektorikannan (DiscGeom.down_of/perp_of) kautta,
# mutta EI atomiikkaa: yksinkertainen solujärjestysiteraatio. Ei tarvitse olla bitilleen sama
# kuin GPU — determinismi (sama seed/frame -> sama grid) ja oikea gravitaatiosuunta riittävät.
#
# Soluformaatti: (seed << 8) | material_id, kuten world_gen.gd / simulation.glsl. Siirroissa
# koko uint32 liikkuu (seed säilyy). disc_world.gd kutsuu tätä headless-fallbackissa.
#
# API:
#   var ca := DiscCpuCa.new()
#   ca.step(grid, n, frame)   # gridiä muokataan paikallaan; frame -> deterministinen RNG
#
# n saa olla mikä tahansa parillinen gridkoko (n-agnostinen). Testeissä käytetään pientä n:ää.

const MASK_LOW := 0xFF                # materiaalitavu
const CLEAR_MAT := 0xFFFFFF00         # nollaa materiaalitavun, säilyttää seedin

# Prosessointijärjestys välimuistissa: solut säteen mukaan NOUSEVASTI (keskipiste ensin).
# Näin alempi (keskustaa lähempi) solu käsitellään ennen ylempää -> jauhepatja romahtaa
# oikein yhden solun/askel eikä duplikoidu (kuten "pohjalta ylös" tasaisessa gravitaatiossa).
var _order: PackedInt32Array = PackedInt32Array()
var _order_n: int = -1


# Rakenna (tai palauta välimuistista) säde-nouseva prosessointijärjestys gridkoolle n.
func _ensure_order(n: int) -> void:
	if _order_n == n and _order.size() == n * n:
		return
	var total := n * n
	# Bittimäärä indeksin pakkaamiseen avaimen alaosaan.
	var idx_bits := 0
	while (1 << idx_bits) < total:
		idx_bits += 1
	# Pakkaa (r^2 << idx_bits) | idx -> lajittele nousevasti -> ensisijaisesti r^2, toissijaisesti idx.
	var packed := PackedInt64Array()
	packed.resize(total)
	for i in total:
		var x := i % n
		var y := i / n
		var dx := DiscGeom.dxc(x, n)
		var dy := DiscGeom.dyc(y, n)
		var rsq := dx * dx + dy * dy
		packed[i] = (rsq << idx_bits) | i
	packed.sort()
	_order.resize(total)
	var mask := (1 << idx_bits) - 1
	for i in total:
		_order[i] = int(packed[i] & mask)
	_order_n = n


# 32-bittinen sekoitushash (sama muoto kuin simulation_disc.glsl:n hash()). Käytetään
# per-solu-deterministiseen suunta-arvontaan iteraatiojärjestyksestä riippumatta.
func _hash32(v: int) -> int:
	var x := v & 0xFFFFFFFF
	x ^= x >> 17
	x = (x * 0xbf58476d) & 0xFFFFFFFF
	x ^= x >> 13
	x = (x * 0x94d049bb) & 0xFFFFFFFF
	x ^= x >> 16
	return x & 0xFFFFFFFF


# Per-solu deterministinen sivusuunnan etumerkki (+1 / -1).
func _dir_of(x: int, y: int, frame: int) -> int:
	var h := _hash32(x * 374761393 + y * 668265263 + frame * 48271)
	return 1 if (h & 1) != 0 else -1


func _is_powder(mat: int) -> bool:
	return mat == DiscGeom.MAT_SAND or mat == DiscGeom.MAT_ASH or mat == DiscGeom.MAT_DIRT \
		or mat == DiscGeom.MAT_GRAVEL or mat == DiscGeom.MAT_IRON_ORE or mat == DiscGeom.MAT_GOLD_ORE \
		or mat == DiscGeom.MAT_COAL or mat == DiscGeom.MAT_COPPER or mat == DiscGeom.MAT_RARE_EARTH


func _is_liquid(mat: int) -> bool:
	return mat == DiscGeom.MAT_WATER or mat == DiscGeom.MAT_OIL


func _in_bounds(x: int, y: int, n: int) -> bool:
	return x >= 0 and x < n and y >= 0 and y < n


# Siirrä lähde tyhjään kohdesoluun (koko uint32 seedeineen). Palauttaa true jos siirtyi.
# moved[dst] estää jo tällä framella täytetyn solun uudelleenkäsittelyn (yksi askel/frame).
func _try_move_empty(grid: PackedInt32Array, moved: PackedByteArray, src: int, nx: int, ny: int, n: int) -> bool:
	if not _in_bounds(nx, ny, n):
		return false
	var dst := ny * n + nx
	if moved[dst] != 0:
		return false
	if (grid[dst] & MASK_LOW) != DiscGeom.MAT_EMPTY:
		return false
	grid[dst] = grid[src]
	grid[src] = DiscGeom.MAT_EMPTY
	moved[dst] = 1
	return true


# Jauheelle: siirrä tyhjään TAI vaihda nesteen kanssa (jauhe uppoaa nesteen läpi).
func _try_move_or_sink(grid: PackedInt32Array, moved: PackedByteArray, src: int, nx: int, ny: int, n: int) -> bool:
	if not _in_bounds(nx, ny, n):
		return false
	var dst := ny * n + nx
	if moved[dst] != 0:
		return false
	var dm: int = grid[dst] & MASK_LOW
	if dm == DiscGeom.MAT_EMPTY:
		grid[dst] = grid[src]
		grid[src] = DiscGeom.MAT_EMPTY
		moved[dst] = 1
		return true
	if dm == DiscGeom.MAT_WATER or dm == DiscGeom.MAT_OIL:
		# Vaihda koko solut (molemmat seedit säilyvät)
		var tmp: int = grid[dst]
		grid[dst] = grid[src]
		grid[src] = tmp
		moved[dst] = 1
		moved[src] = 1  # alle noussut neste ei liiku uudelleen tällä framella
		return true
	return false


# Yksi CA-askel: muokkaa gridiä paikallaan. frame ohjaa deterministisen RNG:n.
func step(grid: PackedInt32Array, n: int, frame: int) -> void:
	_ensure_order(n)
	var total := n * n
	var moved := PackedByteArray()
	moved.resize(total)
	moved.fill(0)

	# --- Putoavat materiaalit (jauheet, nesteet, WOOD_FALLING): keskusta ensin ---
	for oi in range(total):
		var idx := _order[oi]
		if moved[idx] != 0:
			continue
		var cell := grid[idx]
		var mat: int = cell & MASK_LOW
		if mat == DiscGeom.MAT_EMPTY:
			continue

		var powder := _is_powder(mat)
		var liquid := _is_liquid(mat)
		if not (powder or liquid or mat == DiscGeom.MAT_WOOD_FALLING):
			continue

		var x := idx % n
		var y := idx / n
		var down := DiscGeom.down_of(x, y, n)
		var perp := DiscGeom.perp_of(down)
		var dir := _dir_of(x, y, frame)

		if powder:
			# Suoraan alas (uppoaa nesteeseen)
			if _try_move_or_sink(grid, moved, idx, x + down.x, y + down.y, n):
				continue
			# Diagonaali alas (down + sivusuunta), molemmat perp-suunnat
			if _try_move_or_sink(grid, moved, idx, x + down.x + dir * perp.x, y + down.y + dir * perp.y, n):
				continue
			if _try_move_or_sink(grid, moved, idx, x + down.x - dir * perp.x, y + down.y - dir * perp.y, n):
				continue
			continue

		if mat == DiscGeom.MAT_WOOD_FALLING:
			# Alas / diagonaali vain tyhjään
			if _try_move_empty(grid, moved, idx, x + down.x, y + down.y, n):
				continue
			if _try_move_empty(grid, moved, idx, x + down.x + dir * perp.x, y + down.y + dir * perp.y, n):
				continue
			if _try_move_empty(grid, moved, idx, x + down.x - dir * perp.x, y + down.y - dir * perp.y, n):
				continue
			# Ei liikkunut -> laskeutunut, palaudu WOODiksi (seed säilyy)
			grid[idx] = (cell & CLEAR_MAT) | DiscGeom.MAT_WOOD
			continue

		# --- Neste (vesi, öljy) ---
		# Alas
		if _try_move_empty(grid, moved, idx, x + down.x, y + down.y, n):
			continue
		# Öljy laskeutuu veden läpi (öljy kevyempää -> vaihto alle)
		if mat == DiscGeom.MAT_OIL:
			var bx := x + down.x
			var by := y + down.y
			if _in_bounds(bx, by, n):
				var bdst := by * n + bx
				if moved[bdst] == 0 and (grid[bdst] & MASK_LOW) == DiscGeom.MAT_WATER:
					var tmp: int = grid[bdst]
					grid[bdst] = grid[idx]
					grid[idx] = tmp
					moved[bdst] = 1
					moved[idx] = 1
					continue
			# Öljy nousee ylöspäin (poispäin keskipisteestä) veden läpi
			var ax := x - down.x
			var ay := y - down.y
			if _in_bounds(ax, ay, n):
				var adst := ay * n + ax
				if moved[adst] == 0 and (grid[adst] & MASK_LOW) == DiscGeom.MAT_WATER:
					var tmp2: int = grid[adst]
					grid[adst] = grid[idx]
					grid[idx] = tmp2
					moved[adst] = 1
					moved[idx] = 1
					continue
		# Diagonaali alas
		if _try_move_empty(grid, moved, idx, x + down.x + dir * perp.x, y + down.y + dir * perp.y, n):
			continue
		if _try_move_empty(grid, moved, idx, x + down.x - dir * perp.x, y + down.y - dir * perp.y, n):
			continue
		# Sivulle (perp-suunnassa), spread-cap kuten GLSL:ssä (ei koko kehää, break esteeseen)
		var spread := 64 if mat == DiscGeom.MAT_WATER else 32
		if _spread_side(grid, moved, idx, x, y, perp, dir, spread, mat, n):
			continue
		if _spread_side(grid, moved, idx, x, y, perp, -dir, spread, mat, n):
			continue

	# --- Höyry (STEAM): nousee poispäin keskipisteestä. Kauimmainen ensin (laskeva säde) ---
	for oi in range(total - 1, -1, -1):
		var idx := _order[oi]
		if moved[idx] != 0:
			continue
		if (grid[idx] & MASK_LOW) != DiscGeom.MAT_STEAM:
			continue
		var x := idx % n
		var y := idx / n
		var down := DiscGeom.down_of(x, y, n)
		var perp := DiscGeom.perp_of(down)
		# Nousu satunnaisella sivujitterilla: -down + j*perp, j in {-1,0,1}
		var j := (_hash32(x * 668265263 + y * 374761393 + frame * 40503) % 3) - 1
		if _try_move_empty(grid, moved, idx, x - down.x + j * perp.x, y - down.y + j * perp.y, n):
			continue
		# Sivulle
		var dir := _dir_of(x, y, frame)
		if _try_move_empty(grid, moved, idx, x + dir * perp.x, y + dir * perp.y, n):
			continue


# Nesteen sivulevitys yhteen perp-suuntaan (sign*perp). Skannaa oman nestetyypin läpi
# reunaan asti; siirtyy ensimmäiseen tyhjään. Break vieraaseen materiaaliin tai bounds.
func _spread_side(grid: PackedInt32Array, moved: PackedByteArray, src: int, x: int, y: int, perp: Vector2i, sign: int, spread: int, mat: int, n: int) -> bool:
	for i in range(1, spread + 1):
		var nx := x + i * sign * perp.x
		var ny := y + i * sign * perp.y
		if not _in_bounds(nx, ny, n):
			break
		var sidx := ny * n + nx
		var sm: int = grid[sidx] & MASK_LOW
		if sm == DiscGeom.MAT_EMPTY:
			if moved[sidx] == 0:
				grid[sidx] = grid[src]
				grid[src] = DiscGeom.MAT_EMPTY
				moved[sidx] = 1
				return true
			# Kohde varattu tällä framella: pysähdy kuten esteeseen
			break
		elif sm != mat:
			break  # eri aine tai kiinteä este, lopeta
		# sama nestelaji: jatka skannausta
	return false
