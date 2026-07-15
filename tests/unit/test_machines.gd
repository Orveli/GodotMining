extends SceneTree

# Kone- ja hihnatesti — testaa CPU-logiikkaa ilman GPU:ta (headless-yhteensopiva).
# Kattaa:
#  - conveyor_belt._is_movable: malmit/jauheet/nesteet liikkuvat, harkot eivät
#  - furnace/crusher.get_input_dump: reseptin input-materiaalien bittimaski + intake-rect
#  - furnace/crusher.get_intake_center / get_output_center: keskipisteiden sijainti

const ConveyorScript := preload("res://scripts/conveyor_belt.gd")
const FurnaceScript := preload("res://scripts/furnace.gd")
const CrusherScript := preload("res://scripts/crusher.gd")

# Materiaali-ID:t
const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_WATER := 2
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_OIL := 6
const MAT_STEAM := 7
const MAT_ASH := 8
const MAT_GLASS := 10
const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13
const MAT_IRON := 14
const MAT_GOLD := 15
const MAT_COAL := 16
const MAT_GRAVEL := 18
const MAT_BEDROCK := 19
const MAT_COPPER := 20
const MAT_RARE_EARTH := 21

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== KONE- JA HIHNATESTI ===\n")
	_test_conveyor_movable()
	_test_conveyor_not_movable()
	_test_furnace_input_dump()
	_test_crusher_input_dump()
	_test_furnace_centers()
	_test_crusher_centers()
	print("\n=== KONE- JA HIHNATESTI VALMIS: passed=%d failed=%d ===" % [_pass, _fail])
	quit()


func _ok(msg: String) -> void:
	print("  OK: " + msg)
	_pass += 1


func _fail_msg(msg: String) -> void:
	print("  TEST: FAIL — " + msg)
	_fail += 1


# TESTI 1: Hihna siirtää malmit, jauheet ja nesteet
func _test_conveyor_movable() -> void:
	print("--- Testi 1: Hihna siirtää malmit, jauheet ja nesteet ---")
	var belt := ConveyorScript.new()
	var movable := {
		"SAND": MAT_SAND, "WATER": MAT_WATER, "OIL": MAT_OIL, "STEAM": MAT_STEAM,
		"ASH": MAT_ASH, "GLASS": MAT_GLASS, "DIRT": MAT_DIRT, "IRON_ORE": MAT_IRON_ORE,
		"GOLD_ORE": MAT_GOLD_ORE, "COAL": MAT_COAL, "GRAVEL": MAT_GRAVEL,
		"COPPER": MAT_COPPER, "RARE_EARTH": MAT_RARE_EARTH,
	}
	for mat_name in movable.keys():
		var mid: int = movable[mat_name]
		if belt._is_movable(mid):
			_ok("%s (id=%d) liikkuu hihnalla" % [mat_name, mid])
		else:
			_fail_msg("%s (id=%d) EI liiku hihnalla vaikka pitäisi" % [mat_name, mid])
	belt.free()


# TESTI 2: Hihna EI siirrä harkkoja (rigid bodyt) eikä kiinteitä materiaaleja
func _test_conveyor_not_movable() -> void:
	print("\n--- Testi 2: Hihna EI siirrä harkkoja eikä kiinteitä ---")
	var belt := ConveyorScript.new()
	var not_movable := {
		"EMPTY": MAT_EMPTY, "STONE": MAT_STONE, "WOOD": MAT_WOOD,
		"IRON (harkko)": MAT_IRON, "GOLD (harkko)": MAT_GOLD, "BEDROCK": MAT_BEDROCK,
	}
	for mat_name in not_movable.keys():
		var mid: int = not_movable[mat_name]
		if not belt._is_movable(mid):
			_ok("%s (id=%d) pysyy paikallaan hihnalla" % [mat_name, mid])
		else:
			_fail_msg("%s (id=%d) liikkuu hihnalla vaikka EI pitäisi" % [mat_name, mid])
	belt.free()


# TESTI 3: Furnace get_input_dump — maski SAND|IRON_ORE|GOLD_ORE, ei uusia reseptejä
func _test_furnace_input_dump() -> void:
	print("\n--- Testi 3: Furnace get_input_dump — maski SAND|IRON_ORE|GOLD_ORE ---")
	var furnace := FurnaceScript.new()
	furnace.setup(Vector2i(100, 100))
	var dump: Dictionary = furnace.get_input_dump()
	var expected_mask := (1 << MAT_SAND) | (1 << MAT_IRON_ORE) | (1 << MAT_GOLD_ORE)
	var mask: int = dump.get("filter_mask", 0)
	if mask == expected_mask:
		_ok("filter_mask oikein: %d (SAND|IRON_ORE|GOLD_ORE)" % mask)
	else:
		_fail_msg("filter_mask väärä: %d (odotettu %d)" % [mask, expected_mask])
	# COPPER/RARE_EARTH myydään raakana — ei saa vuotaa reseptimaskiin
	if (mask & (1 << MAT_COPPER)) == 0 and (mask & (1 << MAT_RARE_EARTH)) == 0:
		_ok("COPPER/RARE_EARTH eivät ole reseptin inputeina")
	else:
		_fail_msg("COPPER/RARE_EARTH vuoti maskiin — ei uusia reseptejä sallittu")
	var rect: Rect2i = dump.get("rect", Rect2i())
	if rect.size.x > 0 and rect.size.y > 0 and rect.position.y < furnace.grid_pos.y:
		_ok("rect on koneen yläpuolella: %s" % str(rect))
	else:
		_fail_msg("rect virheellinen: %s (grid_pos.y=%d)" % [str(rect), furnace.grid_pos.y])
	furnace.free()


# TESTI 4: Crusher get_input_dump — maski GRAVEL
func _test_crusher_input_dump() -> void:
	print("\n--- Testi 4: Crusher get_input_dump — maski GRAVEL ---")
	var crusher := CrusherScript.new()
	crusher.setup(Vector2i(200, 120))
	var dump: Dictionary = crusher.get_input_dump()
	var expected_mask := (1 << MAT_GRAVEL)
	var mask: int = dump.get("filter_mask", 0)
	if mask == expected_mask:
		_ok("filter_mask oikein: %d (GRAVEL)" % mask)
	else:
		_fail_msg("filter_mask väärä: %d (odotettu %d)" % [mask, expected_mask])
	var rect: Rect2i = dump.get("rect", Rect2i())
	if rect.size.x > 0 and rect.size.y > 0 and rect.position.y < crusher.grid_pos.y:
		_ok("rect on koneen yläpuolella: %s" % str(rect))
	else:
		_fail_msg("rect virheellinen: %s (grid_pos.y=%d)" % [str(rect), crusher.grid_pos.y])
	crusher.free()


# TESTI 5: Furnace intake/output-keskipisteet
func _test_furnace_centers() -> void:
	print("\n--- Testi 5: Furnace intake/output-keskipisteet ---")
	var furnace := FurnaceScript.new()
	furnace.setup(Vector2i(100, 100))
	var intake: Vector2i = furnace.get_intake_center()
	var output: Vector2i = furnace.get_output_center()
	if intake.y == furnace.grid_pos.y - 1:
		_ok("intake yläpuolella: %s" % str(intake))
	else:
		_fail_msg("intake väärällä rivillä: %s (grid_pos.y=%d)" % [str(intake), furnace.grid_pos.y])
	if output.y > intake.y:
		_ok("output intaken alapuolella: %s" % str(output))
	else:
		_fail_msg("output ei ole intaken alapuolella: %s" % str(output))
	furnace.free()


# TESTI 6: Crusher intake/output-keskipisteet
func _test_crusher_centers() -> void:
	print("\n--- Testi 6: Crusher intake/output-keskipisteet ---")
	var crusher := CrusherScript.new()
	crusher.setup(Vector2i(200, 120))
	var intake: Vector2i = crusher.get_intake_center()
	var output: Vector2i = crusher.get_output_center()
	if intake.y == crusher.grid_pos.y - 1:
		_ok("intake yläpuolella: %s" % str(intake))
	else:
		_fail_msg("intake väärällä rivillä: %s (grid_pos.y=%d)" % [str(intake), crusher.grid_pos.y])
	if output.y > intake.y:
		_ok("output intaken alapuolella: %s" % str(output))
	else:
		_fail_msg("output ei ole intaken alapuolella: %s" % str(output))
	crusher.free()
