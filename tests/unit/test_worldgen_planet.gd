# Headless P2-yksikkötesti: sylinterijatkuva world gen + bedrock-ydin.
# Aja: godot --headless --path . --script res://tests/unit/test_worldgen_planet.gd
#
# Generoi planeettakokoisen maailman (4096x448) ja assertoi SPEC_planet P2:
#   (a) pinnan korkeusero sarakkeiden x=0 ja x=W-1 valilla <= 1 solu (16 px)
#   (b) ei bedrock-seinaa x-reunoilla pinnan ylapuolella (x-reunabedrock poistettu)
#   (c) bedrock-ydinrengas olemassa syvyydesta CORE_BEDROCK_FRAC*H alas
#   (d) starter-rautasuoni yha alustan vieressa (nakyva IRON_ORE-laikku)
#
# Ajetaan usealla seedilla robustiuden vuoksi. Tulostaa "TEST: PASS/FAIL"
# (run_all.sh greppaa naita).
extends SceneTree

const W := 4096   # planeettaversion sim-leveys (P1: SIM_WIDTH)
const H := 448    # planeettaversion sim-korkeus (P1: SIM_HEIGHT)
const CELL := 16  # designaatio-/navigaatiogridin solukoko px

const MAT_EMPTY    := 0
const MAT_IRON_ORE := 12
const MAT_BEDROCK  := 19

var _fail_count: int = 0


func _init() -> void:
	var seeds: Array[int] = [1, 7, 42, 12345, 99999]
	for s in seeds:
		_run_one(s)

	if _fail_count == 0:
		print("TEST: PASS  (kaikki %d seedia lapaisivat P2-assertit)" % seeds.size())
	else:
		print("TEST: FAIL  (%d tarkistusta epaonnistui)" % _fail_count)
	quit()


func _run_one(world_seed: int) -> void:
	seed(world_seed)  # determinismi: WorldGen.generate kayttaa globaalia randi():a

	var grid := PackedByteArray()
	grid.resize(W * H)
	var color_seed := PackedByteArray()
	color_seed.resize(W * H)

	WorldGen.generate(grid, color_seed, W, H)

	var core_y0 := int(float(H) * WorldGen.CORE_BEDROCK_FRAC)

	# --- (a) sauman korkeusjatkuvuus: x=0 vs x=W-1 ---
	var s0 := _surface_of(grid, 0)
	var s1 := _surface_of(grid, W - 1)
	_check(absi(s0 - s1) <= CELL, world_seed,
		"(a) sauman korkeusero %d px (x=0 sy=%d, x=W-1 sy=%d) > %d px" % [
			absi(s0 - s1), s0, s1, CELL])

	# --- (b) ei x-reunabedrockia pinnan ylapuolella (ydinrenkaan ylapuolella) ---
	# Tarkista molemmat reunavyohykkeet: yhtaan BEDROCKia ei saa olla y < core_y0.
	var edge_bedrock := 0
	for x in range(0, WorldGen.EDGE_THICKNESS):
		for y in range(0, core_y0):
			if grid[y * W + x] == MAT_BEDROCK:
				edge_bedrock += 1
	for x in range(W - WorldGen.EDGE_THICKNESS, W):
		for y in range(0, core_y0):
			if grid[y * W + x] == MAT_BEDROCK:
				edge_bedrock += 1
	_check(edge_bedrock == 0, world_seed,
		"(b) x-reunoilla %d bedrock-solua ydinrenkaan ylapuolella (seina ei poistunut)" % edge_bedrock)

	# --- (c) bedrock-ydinrengas: koko syvin kaista y >= core_y0 on bedrockia ---
	var non_bedrock_in_core := 0
	for y in range(core_y0, H):
		var row := y * W
		for x in W:
			if grid[row + x] != MAT_BEDROCK:
				non_bedrock_in_core += 1
	_check(non_bedrock_in_core == 0, world_seed,
		"(c) ydinrenkaassa (y>=%d) %d ei-bedrock-solua (rengas ei ehja)" % [core_y0, non_bedrock_in_core])
	# Varmista lisaksi ettei rengas ala liian ylhaalta: juuri renkaan ylapuolella
	# (y = core_y0 - 3) EI saa olla pelkkaa bedrockia koko rivilla.
	var above_all_bedrock := true
	var check_row := core_y0 - 3
	for x in W:
		if grid[check_row * W + x] != MAT_BEDROCK:
			above_all_bedrock = false
			break
	_check(not above_all_bedrock, world_seed,
		"(c) bedrock alkaa liian ylhaalta (rivi y=%d jo taynna bedrockia)" % check_row)

	# --- (d) starter-rautasuoni alustan oikealla puolella ---
	# Pintapaljastuma sijoittuu valille [platform_x0+platform_w .. +~44].
	var px0 := WorldGen.platform_x0 + WorldGen.platform_w - 8
	var px1 := WorldGen.platform_x0 + WorldGen.platform_w + 60
	var iron := 0
	for x in range(maxi(px0, 0), mini(px1, W)):
		for y in H:
			if grid[y * W + x] == MAT_IRON_ORE:
				iron += 1
	_check(iron >= 30, world_seed,
		"(d) starter-rautasuoni: vain %d IRON_ORE-solua alustan vieressa (odotettu >= 30)" % iron)


# Pinnan y = ylin ei-tyhja solu sarakkeessa (tai H jos koko sarake tyhja).
func _surface_of(grid: PackedByteArray, x: int) -> int:
	for y in H:
		if grid[y * W + x] != MAT_EMPTY:
			return y
	return H


func _check(ok: bool, world_seed: int, msg: String) -> void:
	if not ok:
		_fail_count += 1
		print("  FAIL [seed %d]: %s" % [world_seed, msg])
