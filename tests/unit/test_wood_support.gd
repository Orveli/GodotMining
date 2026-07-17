extends SceneTree

# Yksikkotestit WoodSupportin toroidaaliselle (planeetta) x-wrapille.
# Sauman yli tuettu puu EI muutu WOOD_FALLINGiksi. Tuki (STONE) sarakkeessa x=0,
# puu sarakkeessa x=W-1 -> puu koskettaa tukea sauman yli (x=W-1:n oikea naapuri = x=0).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_wood_support.gd

const W := 16
const H := 8
const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_WOOD_FALLING := 9

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== WOOD_SUPPORT-WRAP-TESTIT ===\n")
	_test_supported_across_seam()
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


func _at(g: PackedByteArray, x: int, y: int) -> int:
	return g[y * W + x]


# Tuki x=0:ssa; puu x=W-1 ja x=W-2 (BFS-ketju). Puun on pysyttava WOODina sauman yli
# tuettuna. Erillinen tuettomaton puu keskella (x=5) putoaa -> WOOD_FALLING (kontrolli).
func _test_supported_across_seam() -> void:
	print("--- Testi: sauman yli tuettu puu ei putoa ---")
	var g := _new_grid()
	# Tuki: kivi sarakkeessa x=0 rivilla 3 (ei maapohja, keskella korkeutta).
	g[3 * W + 0] = MAT_STONE
	# Puuketju sauman toisella puolella: x=W-1 (koskettaa kiveä sauman yli) ja x=W-2.
	g[3 * W + (W - 1)] = MAT_WOOD
	g[3 * W + (W - 2)] = MAT_WOOD
	# Kontrolli: irrallinen tueton puu keskella -> putoaa.
	g[3 * W + 5] = MAT_WOOD

	var changed := WoodSupport.check_support(g, W, H)

	_check(_at(g, W - 1, 3) == MAT_WOOD, "sauman yli koskettava puu pysyy WOODina")
	_check(_at(g, W - 2, 3) == MAT_WOOD, "BFS-tuki leviaa sauman yli viereiseen puuhun")
	_check(_at(g, 5, 3) == MAT_WOOD_FALLING, "irrallinen puu putoaa (kontrolli)")
	_check(changed, "check_support raportoi muutoksen (kontrollipuu putosi)")
