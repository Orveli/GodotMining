extends SceneTree

# Yksikkotestit DesignationGridille (scripts/designation_grid.gd).
# Testaa px->solu-mappauksen tarkkuuden (myos solurajat), add=false-nollauksen,
# cell_px_rect-kaanteismappauksen ja version-laskurin.
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_designation_grid.gd

const D_NONE := 0
const D_QUEUED := 1
const D_MINING := 4

# Planeettakoko (mirroroi DesignationGridia): GW=256, GH=28. x wrappaa, y ei.
const GW := 256
const GH := 28

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== DESIGNATIONGRID-TESTIT ===\n")
	_test_paint_sets_queued()
	_test_add_false_clears()
	_test_cell_px_rect_roundtrip()
	_test_version_increments()
	_test_seam_wrap()
	print("\n=== YHTEENVETO ===")
	print("RESULT: %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		print("TEST: FAILED")
	quit(1 if _fail > 0 else 0)


# --- Apurit -----------------------------------------------------------------

func _check(cond: bool, name: String) -> void:
	if cond:
		_pass += 1
		print("  PASS: ", name)
	else:
		_fail += 1
		print("  FAILED: ", name)


func _count_state(desig: DesignationGrid, state: int) -> int:
	var n := 0
	for i in desig.cells.size():
		if desig.cells[i] == state:
			n += 1
	return n


# --- Testi 1: paint_px_rect asettaa oikeat solut QUEUEDiksi -----------------

func _test_paint_sets_queued() -> void:
	print("--- Testi 1: paint_px_rect -> QUEUED oikeisiin soluihin ---")

	# 1a) Yhden solun tarkka osuma: px (32,32)..(47,47) -> vain solu (2,2) (CELL=16).
	var d1 := DesignationGrid.new()
	d1.paint_px_rect(Rect2i(32, 32, 16, 16), true)
	_check(d1.get_cell(2, 2) == D_QUEUED, "1a: solu (2,2) QUEUED")
	_check(d1.get_cell(1, 2) == D_NONE and d1.get_cell(3, 2) == D_NONE
		and d1.get_cell(2, 1) == D_NONE and d1.get_cell(2, 3) == D_NONE,
		"1a: naapurit pysyvat NONE")
	_check(_count_state(d1, D_QUEUED) == 1, "1a: tasan 1 solu QUEUED")

	# 1b) Reunatapaus solurajalla: 2 px leveys x=31..32 ylittaa rajan x=32
	#     -> solusarakkeet 1 (31/16) ja 2 (32/16).
	var d2 := DesignationGrid.new()
	d2.paint_px_rect(Rect2i(31, 0, 2, 16), true)
	_check(d2.get_cell(1, 0) == D_QUEUED and d2.get_cell(2, 0) == D_QUEUED,
		"1b: solurajan ylitys osuu sarakkeisiin 1 ja 2")
	_check(d2.get_cell(0, 0) == D_NONE and d2.get_cell(3, 0) == D_NONE,
		"1b: viereiset sarakkeet 0 ja 3 pysyvat NONE")
	_check(_count_state(d2, D_QUEUED) == 2, "1b: tasan 2 solua QUEUED")

	# 1c) Monisolun suorakulmio: px (0,0)..(47,31) -> solut (0..2, 0..1) = 6 kpl (CELL=16).
	var d3 := DesignationGrid.new()
	d3.paint_px_rect(Rect2i(0, 0, 48, 32), true)
	_check(_count_state(d3, D_QUEUED) == 6, "1c: 3x2 = 6 solua QUEUED")
	_check(d3.get_cell(0, 0) == D_QUEUED and d3.get_cell(2, 1) == D_QUEUED,
		"1c: kulmasolut (0,0) ja (2,1) QUEUED")
	_check(d3.get_cell(3, 0) == D_NONE and d3.get_cell(0, 2) == D_NONE,
		"1c: alueen ulkopuoliset solut NONE")


# --- Testi 2: add=false nollaa mihin tahansa tilaan -------------------------

func _test_add_false_clears() -> void:
	print("\n--- Testi 2: add=false nollaa D_NONEksi ---")

	# QUEUED-alue -> add=false nollaa.
	var d1 := DesignationGrid.new()
	d1.paint_px_rect(Rect2i(0, 0, 48, 32), true)
	_check(_count_state(d1, D_QUEUED) == 6, "2: esiehto 6 solua QUEUED")
	d1.paint_px_rect(Rect2i(0, 0, 48, 32), false)
	_check(not d1.any_active(), "2: add=false nollasi kaikki (any_active=false)")
	_check(d1.get_cell(0, 0) == D_NONE and d1.get_cell(2, 1) == D_NONE,
		"2: yksittaiset solut D_NONE")

	# Ei-QUEUED tila (D_MINING) -> add=false nollaa myos sen.
	var d2 := DesignationGrid.new()
	d2.set_cell(5, 5, D_MINING)
	_check(d2.get_cell(5, 5) == D_MINING, "2: esiehto solu (5,5) MINING")
	# Solu (5,5) px-alue (80,80)..(95,95) (CELL=16).
	d2.paint_px_rect(Rect2i(80, 80, 16, 16), false)
	_check(d2.get_cell(5, 5) == D_NONE, "2: add=false nollaa myos MINING-tilan")


# --- Testi 3: cell_px_rect kaanteismappaus ----------------------------------

func _test_cell_px_rect_roundtrip() -> void:
	print("\n--- Testi 3: cell_px_rect kaanteismappaus ---")

	var d := DesignationGrid.new()

	# Suora tarkistus: solu (7,9) -> px (112,144,16,16) (CELL=16).
	var r := d.cell_px_rect(7, 9)
	_check(r == Rect2i(112, 144, 16, 16), "3: cell_px_rect(7,9) == Rect2i(112,144,16,16)")

	# Round-trip: paint(cell_px_rect(7,9)) osuu tasan soluun (7,9).
	d.paint_px_rect(d.cell_px_rect(7, 9), true)
	_check(d.get_cell(7, 9) == D_QUEUED, "3: round-trip osuu soluun (7,9)")
	_check(_count_state(d, D_QUEUED) == 1, "3: vain 1 solu QUEUED round-tripissa")

	# Reunasolu (GW-1, GH-1) = (255,27) -> px (4080,432,16,16) (CELL=16).
	var d2 := DesignationGrid.new()
	var r2 := d2.cell_px_rect(GW - 1, GH - 1)
	_check(r2 == Rect2i(4080, 432, 16, 16), "3: cell_px_rect(255,27) == Rect2i(4080,432,16,16)")
	d2.paint_px_rect(d2.cell_px_rect(GW - 1, GH - 1), true)
	_check(d2.get_cell(GW - 1, GH - 1) == D_QUEUED, "3: reunasolu round-trip QUEUED")
	_check(_count_state(d2, D_QUEUED) == 1, "3: reunasolun round-trip tasan 1 QUEUED")


# --- Testi 4: version-laskuri ------------------------------------------------

func _test_version_increments() -> void:
	print("\n--- Testi 4: version kasvaa muutoksista ---")

	var d := DesignationGrid.new()
	_check(d.version == 0, "4: alkuversio 0")

	# set_cell muutos -> +1.
	d.set_cell(0, 0, D_QUEUED)
	_check(d.version == 1, "4: set_cell muutos -> version 1")

	# set_cell sama arvo -> ei muutosta.
	d.set_cell(0, 0, D_QUEUED)
	_check(d.version == 1, "4: set_cell sama arvo ei kasvata versiota")

	# set_cell takaisin NONEksi -> +1.
	d.set_cell(0, 0, D_NONE)
	_check(d.version == 2, "4: set_cell NONE-muutos -> version 2")

	# Planeetta: y-rajojen ulkopuolinen set_cell -> ei muutosta (y ei wrappaa).
	# (x-wrap testataan erikseen _test_seam_wrapissa; x=-1/x=GW EIVAT ole rajan yli vaan wrapaavat.)
	d.set_cell(0, GH, D_QUEUED)
	d.set_cell(0, -1, D_QUEUED)
	_check(d.version == 2, "4: y-rajojen ulkopuoliset set_cellit eivat kasvata versiota")

	# paint_px_rect joka muuttaa soluja -> +1 (yksi inkrementti koko rectille).
	d.paint_px_rect(Rect2i(0, 0, 48, 32), true)
	_check(d.version == 3, "4: paint_px_rect (muutos) -> version 3, yksi inkrementti")

	# paint_px_rect uudelleen samaan (kaikki jo QUEUED) -> ei muutosta.
	d.paint_px_rect(Rect2i(0, 0, 48, 32), true)
	_check(d.version == 3, "4: paint_px_rect ilman muutosta ei kasvata versiota")

	# paint_px_rect add=false (nollaa) -> +1.
	d.paint_px_rect(Rect2i(0, 0, 48, 32), false)
	_check(d.version == 4, "4: paint_px_rect add=false (muutos) -> version 4")

	# paint_px_rect add=false uudelleen (ei mitaan nollattavaa) -> ei muutosta.
	d.paint_px_rect(Rect2i(0, 0, 48, 32), false)
	_check(d.version == 4, "4: paint_px_rect add=false ilman muutosta ei kasvata versiota")


# --- Testi 5: x wrappaa sauman yli (get/set/paint toroidaalisia) -------------

func _test_seam_wrap() -> void:
	print("\n--- Testi 5: x wrappaa (sauman yli) ---")

	# get/set wrap: sarake GW osuu sarakkeeseen 0, sarake -1 sarakkeeseen GW-1.
	var d := DesignationGrid.new()
	d.set_cell(GW, 3, D_QUEUED)
	_check(d.get_cell(0, 3) == D_QUEUED, "5: set_cell(GW,3) wrappaa sarakkeeseen 0")
	_check(d.get_cell(GW, 3) == D_QUEUED, "5: get_cell(GW,3) lukee saman wrapatun solun")
	d.set_cell(-1, 3, D_MINING)
	_check(d.get_cell(GW - 1, 3) == D_MINING, "5: set_cell(-1,3) wrappaa sarakkeeseen GW-1")

	# paint sauman yli: px x=-16..15 (solut -1 ja 0) -> wrap: GW-1 ja 0.
	var d2 := DesignationGrid.new()
	d2.paint_px_rect(Rect2i(-16, 48, 32, 16), true)
	_check(d2.get_cell(GW - 1, 3) == D_QUEUED and d2.get_cell(0, 3) == D_QUEUED,
		"5: paint sauman yli osuu sarakkeisiin GW-1 ja 0")
	_check(_count_state(d2, D_QUEUED) == 2, "5: sauman yli veto tasan 2 solua")
	_check(d2.get_cell(GW / 2, 3) == D_NONE, "5: sauman vastapuoli (GW/2) pysyy NONE")
