extends SceneTree

# Yksikkotestit CCL:n toroidaaliselle (planeetta) x-wrapille.
# Kappale joka koskettaa saraketta x=0 ja x=W-1 samalla rivilla on YKSI komponentti.
# Testaa seka find_components_fast (BFS) etta find_components (Union-Find).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_ccl_wrap.gd

const W := 16
const H := 8
const MAT_EMPTY := 0
const MAT_STONE := 3

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== CCL-WRAP-TESTIT ===\n")
	_test_seam_adjacency()
	_test_no_false_merge()
	_test_bar_across_seam()
	print("\n=== YHTEENVETO ===")
	print("RESULT: %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		print("TEST: FAILED")
	quit(1 if _fail > 0 else 0)


func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: ", name)
	else:
		_fail += 1
		print("  FAILED: ", name)


func _new_grid() -> PackedByteArray:
	var g := PackedByteArray()
	g.resize(W * H)
	g.fill(MAT_EMPTY)
	return g


func _set(g: PackedByteArray, x: int, y: int, mat: int) -> void:
	g[y * W + x] = mat


# Kaksi kiveä vastakkaisilla reunoilla samalla rivilla = naapureita sauman yli = 1 komponentti.
func _test_seam_adjacency() -> void:
	print("--- Testi 1: sauman yli naapuruus ---")
	var g := _new_grid()
	_set(g, 0, 3, MAT_STONE)
	_set(g, W - 1, 3, MAT_STONE)

	var fast := CCL.find_components_fast(g, W, H, MAT_STONE)
	_check(fast.size() == 1, "find_components_fast: 1 komponentti (sauman yli)")
	if fast.size() == 1:
		var comp: Array = fast[fast.keys()[0]]
		_check(comp.size() == 2, "find_components_fast: komponentissa 2 pikselia")

	var uf := CCL.find_components(g, W, H, MAT_STONE)
	_check(uf.size() == 1, "find_components (Union-Find): 1 komponentti (sauman yli)")


# Kaksi kiveä vastakkaisilla reunoilla ERI riveilla EIVAT ole naapureita = 2 komponenttia.
func _test_no_false_merge() -> void:
	print("--- Testi 2: eri rivit eivat yhdisty ---")
	var g := _new_grid()
	_set(g, 0, 2, MAT_STONE)
	_set(g, W - 1, 5, MAT_STONE)

	var fast := CCL.find_components_fast(g, W, H, MAT_STONE)
	_check(fast.size() == 2, "find_components_fast: 2 komponenttia (ei virheellista yhdistysta)")

	var uf := CCL.find_components(g, W, H, MAT_STONE)
	_check(uf.size() == 2, "find_components (Union-Find): 2 komponenttia")


# Vaakapalkki joka jatkuu sauman yli {W-2, W-1, 0, 1} = 1 komponentti, 4 pikselia.
func _test_bar_across_seam() -> void:
	print("--- Testi 3: vaakapalkki sauman yli ---")
	var g := _new_grid()
	_set(g, W - 2, 3, MAT_STONE)
	_set(g, W - 1, 3, MAT_STONE)
	_set(g, 0, 3, MAT_STONE)
	_set(g, 1, 3, MAT_STONE)

	var fast := CCL.find_components_fast(g, W, H, MAT_STONE)
	_check(fast.size() == 1, "find_components_fast: 1 komponentti (palkki sauman yli)")
	if fast.size() == 1:
		var comp: Array = fast[fast.keys()[0]]
		_check(comp.size() == 4, "find_components_fast: komponentissa 4 pikselia")

	var uf := CCL.find_components(g, W, H, MAT_STONE)
	_check(uf.size() == 1, "find_components (Union-Find): 1 komponentti (palkki sauman yli)")
