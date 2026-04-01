extends SceneTree

# Linko-yksikkötesti — testaa Launcher-logiikkaa ilman GPU:ta
# Käyttää suurta delta-arvoa ajan nopeuttamiseen

const LauncherScript := preload("res://scripts/launcher.gd")

const W := 320
const H := 180
const TOTAL := W * H
const MAT_SAND := 1
const MAT_STONE := 3

var grid: PackedByteArray
var color_seed: PackedByteArray
var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== LINKO-TESTI ===\n")
	_test_build_structure()
	_test_check_intact()
	_test_intake()
	_test_shaft_launch()
	_test_launch_direction()
	print("\n=== LINKO-TESTI VALMIS: passed=%d failed=%d ===" % [_pass, _fail])
	quit()


func _setup_grid() -> void:
	grid = PackedByteArray()
	grid.resize(TOTAL)
	grid.fill(0)
	color_seed = PackedByteArray()
	color_seed.resize(TOTAL)
	for i in TOTAL:
		color_seed[i] = randi() % 256


func _ok(msg: String) -> void:
	print("  OK: " + msg)
	_pass += 1


func _fail_msg(msg: String) -> void:
	print("  TEST: FAIL — " + msg)
	_fail += 1


# TESTI 1: Rakentaako build_structure oikein?
func _test_build_structure() -> void:
	print("--- Testi 1: Rakenteen rakentaminen ---")
	var launcher := LauncherScript.new()
	launcher.build_structure(Vector2i(150, 100), Vector2i(150, 50), 1.0)

	if launcher.structure_pixels.is_empty():
		_fail_msg("structure_pixels tyhjä!")
	else:
		_ok("structure_pixels: %d pikseliä" % launcher.structure_pixels.size())

	if launcher.intake_pixels.is_empty():
		_fail_msg("intake_pixels tyhjä!")
	else:
		_ok("intake_pixels: %d pikseliä" % launcher.intake_pixels.size())

	if launcher.barrel_tip == Vector2i.ZERO:
		_fail_msg("barrel_tip ei asetettu!")
	else:
		_ok("barrel_tip asetettu: %s" % str(launcher.barrel_tip))

	# barrel_tip pitäisi olla kuilun yläpuolella ja oikealla (dir=1.0)
	if launcher.barrel_tip.x <= 150:
		_fail_msg("barrel_tip väärällä puolella (x=%d, odotettu > 150)" % launcher.barrel_tip.x)
	else:
		_ok("barrel_tip oikealla puolella (x=%d)" % launcher.barrel_tip.x)

	launcher.free()


# TESTI 2: check_intact — tunnistaa rakenteen tuhoutumisen
func _test_check_intact() -> void:
	print("\n--- Testi 2: check_intact ---")
	_setup_grid()
	var launcher := LauncherScript.new()
	launcher.build_structure(Vector2i(150, 100), Vector2i(150, 50), 1.0)
	launcher.write_to_grid(grid, color_seed, W)

	if not launcher.check_intact(grid, W):
		_fail_msg("check_intact false heti rakentamisen jälkeen!")
	else:
		_ok("check_intact true rakentamisen jälkeen")

	# Tuhoa yksi rakennepikseli
	var p := launcher.structure_pixels[0]
	grid[p.y * W + p.x] = 0

	if launcher.check_intact(grid, W):
		_fail_msg("check_intact true vaikka rakennepikseli tuhottu!")
	else:
		_ok("check_intact false kun rakennepikseli tuhottu")

	launcher.free()


# TESTI 3: Imeminen — materiaali katoaa gridistä ja ilmestyy kuiluun
func _test_intake() -> void:
	print("\n--- Testi 3: Imeminen intake-alueelta ---")
	_setup_grid()
	var launcher := LauncherScript.new()
	launcher.build_structure(Vector2i(150, 100), Vector2i(150, 50), 1.0)
	launcher.write_to_grid(grid, color_seed, W)

	# Laita hiekkaa intake-alueen pikseleihin
	var placed := 0
	for p in launcher.intake_pixels:
		if grid[p.y * W + p.x] == 0:  # tyhjä ruutu
			grid[p.y * W + p.x] = MAT_SAND
			placed += 1
			if placed >= 4:
				break

	if placed == 0:
		_fail_msg("Ei voitu sijoittaa hiekkaa intake-alueelle!")
		launcher.free()
		return

	var sand_before := _count_mat(MAT_SAND)
	launcher.update_launcher(grid, W, 0.1)
	var sand_in_grid := _count_mat(MAT_SAND)
	var sand_in_shaft := launcher.shaft_pixels.size()

	if sand_in_grid < sand_before:
		_ok("Hiekka imetty gridistä (gridissä: %d → %d)" % [sand_before, sand_in_grid])
	else:
		_fail_msg("Hiekkaa ei imetty gridistä (gridissä: %d, sijoitettu: %d)" % [sand_in_grid, placed])

	if sand_in_shaft > 0:
		_ok("Kuilussa %d pikseliä" % sand_in_shaft)
	else:
		_fail_msg("Kuilussa ei pikseleitä imemisen jälkeen!")

	launcher.free()


# TESTI 4: Kuilunousu ja laukaus — nopeutettu aika (delta=2.0)
func _test_shaft_launch() -> void:
	print("\n--- Testi 4: Kuilunousu ja laukaus (nopeutettu aika) ---")
	_setup_grid()
	var launcher := LauncherScript.new()
	# Lyhyt kuilu: 40px korkeus, riittää testiin
	launcher.build_structure(Vector2i(150, 100), Vector2i(150, 60), 1.0)
	launcher.write_to_grid(grid, color_seed, W)

	# Laita hiekkaa intake-alueelle
	var placed := 0
	for p in launcher.intake_pixels:
		if grid[p.y * W + p.x] == 0:
			grid[p.y * W + p.x] = MAT_SAND
			placed += 1
			if placed >= 3:
				break

	# Ime kuiluun
	launcher.update_launcher(grid, W, 0.1)
	var in_shaft := launcher.shaft_pixels.size()
	print("  Kuilussa ennen laukaisua: %d pikseliä" % in_shaft)

	if in_shaft == 0:
		_fail_msg("Kuilussa ei pikseleitä — imeminen ei toiminut!")
		launcher.free()
		return

	# Nopeutettu aika: delta=2.0
	# SHAFT_SPEED=180 px/s → 2.0s = 360px nousu → ylittää 40px kuilun yhdessä askeleessa
	var launched := launcher.update_shaft(grid, W, H, 2.0)

	if launched.size() > 0:
		_ok("%d pikseliä laukaistiin barrel_tip=%s" % [launched.size(), str(launched[0]["pos"])])
	else:
		# Kokeile vielä toisella askeleella
		launched = launcher.update_shaft(grid, W, H, 2.0)
		if launched.size() > 0:
			_ok("%d pikseliä laukaistiin (2. askel)" % launched.size())
		else:
			_fail_msg("Yhtään pikseliä ei laukaisttu!")

	launcher.free()


# TESTI 5: Lentääkö oikeaan suuntaan molemmilla dir-arvoilla?
func _test_launch_direction() -> void:
	print("\n--- Testi 5: Lentosuunta (oikea ja vasen) ---")

	for dir in [1.0, -1.0]:
		_setup_grid()
		var launcher := LauncherScript.new()
		launcher.build_structure(Vector2i(150, 100), Vector2i(150, 60), dir)
		launcher.write_to_grid(grid, color_seed, W)

		# Laita hiekkaa ja ime kuiluun
		for p in launcher.intake_pixels.slice(0, 3):
			if grid[p.y * W + p.x] == 0:
				grid[p.y * W + p.x] = MAT_SAND
		launcher.update_launcher(grid, W, 0.1)

		if launcher.shaft_pixels.is_empty():
			_fail_msg("dir=%s: kuilussa ei pikseleitä!" % str(dir))
			launcher.free()
			continue

		# Nopeutettu laukaus
		var launched := launcher.update_shaft(grid, W, H, 2.0)
		if launched.is_empty():
			launched = launcher.update_shaft(grid, W, H, 2.0)

		if launched.is_empty():
			_fail_msg("dir=%s: ei laukaisua!" % str(dir))
			launcher.free()
			continue

		var vel: Vector2 = launched[0]["vel"]
		var correct_x := vel.x > 0 if dir > 0 else vel.x < 0
		if correct_x:
			_ok("dir=%s: lentää oikeaan suuntaan (vel.x=%.1f)" % [str(dir), vel.x])
		else:
			_fail_msg("dir=%s: väärä lentosuunta! vel.x=%.1f" % [str(dir), vel.x])

		# Pitäisi lentää ylöspäin (vel.y < 0)
		if vel.y < 0:
			_ok("dir=%s: lentää ylöspäin (vel.y=%.1f)" % [str(dir), vel.y])
		else:
			_fail_msg("dir=%s: ei lennä ylöspäin! vel.y=%.1f" % [str(dir), vel.y])

		launcher.free()


func _count_mat(mat: int) -> int:
	var count := 0
	for i in TOTAL:
		if grid[i] == mat:
			count += 1
	return count
