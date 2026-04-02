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
	_test_intake_hiekka_alla()
	_test_intake_ei_hiekkaa()
	_test_update_bottom_putoaminen()
	_test_update_bottom_ei_putoa_kivelle()
	_test_update_bottom_hiekka_alla()
	_test_shaft_launch()
	_test_launch_direction()
	_test_check_intact_ehja()
	_test_check_intact_rikki()
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


# Apufunktio: luo launcher ja kirjoita se gridiin
func _make_launcher(start: Vector2i, end: Vector2i, dir: float) -> LauncherScript:
	var launcher := LauncherScript.new()
	launcher.build_structure(start, end, dir)
	launcher.write_to_grid(grid, color_seed, W)
	return launcher


# TESTI 1: Rakentaako build_structure oikein?
func _test_build_structure() -> void:
	print("--- Testi 1: Rakenteen rakentaminen ---")
	var launcher := LauncherScript.new()
	launcher.build_structure(Vector2i(150, 100), Vector2i(150, 50), 1.0)

	if launcher.structure_pixels.is_empty():
		_fail_msg("structure_pixels tyhjä!")
	else:
		_ok("structure_pixels: %d pikseliä" % launcher.structure_pixels.size())

	if launcher.start_pos == Vector2i(150, 100):
		_ok("start_pos asetettu oikein: %s" % str(launcher.start_pos))
	else:
		_fail_msg("start_pos väärä: %s (odotettu (150, 100))" % str(launcher.start_pos))

	if launcher.end_pos == Vector2i(150, 50):
		_ok("end_pos asetettu oikein: %s" % str(launcher.end_pos))
	else:
		_fail_msg("end_pos väärä: %s (odotettu (150, 50))" % str(launcher.end_pos))

	if launcher.barrel_tip == Vector2i.ZERO:
		_fail_msg("barrel_tip ei asetettu!")
	else:
		_ok("barrel_tip asetettu: %s" % str(launcher.barrel_tip))

	if launcher.barrel_tip.x <= 150:
		_fail_msg("barrel_tip väärällä puolella (x=%d, odotettu > 150)" % launcher.barrel_tip.x)
	else:
		_ok("barrel_tip oikealla puolella (x=%d)" % launcher.barrel_tip.x)

	launcher.free()


# TESTI 2: Intake toimii — hiekka alla imetään kuiluun
func _test_intake_hiekka_alla() -> void:
	print("\n--- Testi 2: Intake toimii — hiekka alla imetään kuiluun ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 100), Vector2i(150, 50), 1.0)

	# Sijoita hiekkaa intake-alueelle (dy=2..6 jalustasta, sarakkeet start_pos.x..+3)
	var placed := 0
	for x in range(launcher.start_pos.x, launcher.start_pos.x + 4):
		for dy in range(2, 7):
			var py := launcher.start_pos.y + dy
			var idx := py * W + x
			if idx >= 0 and idx < grid.size() and grid[idx] == 0:
				grid[idx] = MAT_SAND
				placed += 1
				if placed >= 4:
					break
		if placed >= 4:
			break

	if placed == 0:
		_fail_msg("Ei voitu sijoittaa hiekkaa intake-alueelle!")
		launcher.free()
		return

	var sand_before := _count_mat(MAT_SAND)
	launcher.cooldown_timer = 0.0
	launcher.update_launcher(grid, W, 0.1)
	var sand_in_grid := _count_mat(MAT_SAND)
	var sand_in_shaft := launcher.shaft_pixels.size()

	if sand_in_grid < sand_before:
		_ok("Hiekka imetty gridistä (gridissä: %d → %d)" % [sand_before, sand_in_grid])
	else:
		_fail_msg("Hiekkaa ei imetty gridistä (gridissä: %d, sijoitettu: %d)" % [sand_in_grid, placed])

	if sand_in_shaft > 0:
		_ok("Kuilussa %d pikseliä imemisen jälkeen" % sand_in_shaft)
	else:
		_fail_msg("Kuilussa ei pikseleitä imemisen jälkeen!")

	launcher.free()


# TESTI 3: Intake ei toimi ilman hiekkaa — shaft_pixels pysyy tyhjänä
func _test_intake_ei_hiekkaa() -> void:
	print("\n--- Testi 3: Intake ei toimi ilman hiekkaa ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 100), Vector2i(150, 50), 1.0)

	# Ei sijoiteta hiekkaa — pelkkä tyhjä grid + rakennepikselit
	var shaft_ennen := launcher.shaft_pixels.size()
	launcher.cooldown_timer = 0.0
	launcher.update_launcher(grid, W, 0.1)
	var shaft_jalkeen := launcher.shaft_pixels.size()

	if shaft_ennen == 0 and shaft_jalkeen == 0:
		_ok("Ilman hiekkaa shaft_pixels pysyi tyhjänä (%d → %d)" % [shaft_ennen, shaft_jalkeen])
	else:
		_fail_msg("shaft_pixels kasvoi ilman hiekkaa! (%d → %d)" % [shaft_ennen, shaft_jalkeen])

	launcher.free()


# TESTI 4: update_bottom putoaminen — alla tyhjää → start_pos.y kasvaa
func _test_update_bottom_putoaminen() -> void:
	print("\n--- Testi 4: update_bottom — alla tyhjää → launcher putoaa ---")
	_setup_grid()
	# Launcher melko ylhäällä, alla ei mitään — pitää pudota
	var launcher := _make_launcher(Vector2i(150, 60), Vector2i(150, 20), 1.0)

	var y_ennen := launcher.start_pos.y
	var liikuttu := launcher.update_bottom(grid, W, 0)

	if liikuttu:
		_ok("update_bottom palautti true (liikuttu)")
	else:
		_fail_msg("update_bottom palautti false vaikka alla tyhjää")

	if launcher.start_pos.y > y_ennen:
		_ok("start_pos.y kasvoi: %d → %d (putoaminen OK)" % [y_ennen, launcher.start_pos.y])
	else:
		_fail_msg("start_pos.y ei kasvanut: %d → %d" % [y_ennen, launcher.start_pos.y])

	launcher.free()


# TESTI 5: update_bottom ei putoa kiven päälle — alla kiveä → pysyy paikallaan
func _test_update_bottom_ei_putoa_kivelle() -> void:
	print("\n--- Testi 5: update_bottom — alla kiveä → pysyy paikallaan ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 60), Vector2i(150, 20), 1.0)

	# Aseta kiveä suoraan jalustasta kaksi riviä alle (below_y = start_pos.y + 2)
	var below_y := launcher.start_pos.y + 2
	for x in range(launcher.start_pos.x, launcher.start_pos.x + 4):
		var idx := below_y * W + x
		if idx >= 0 and idx < grid.size():
			grid[idx] = MAT_STONE

	var y_ennen := launcher.start_pos.y
	var liikuttu := launcher.update_bottom(grid, W, 0)

	if not liikuttu:
		_ok("update_bottom palautti false — ei putoamista kiven päälle")
	else:
		_fail_msg("update_bottom palautti true vaikka alla on kiveä!")

	if launcher.start_pos.y == y_ennen:
		_ok("start_pos.y pysyi: %d (ei putoamista)" % y_ennen)
	else:
		_fail_msg("start_pos.y muuttui vaikka alla on kiveä: %d → %d" % [y_ennen, launcher.start_pos.y])

	launcher.free()


# TESTI 6: update_bottom hiekka alla — ei putoa läpi, mutta voi imeä
# ODOTETTU TULOS: putoaminen estyy (OK), imeminen toimii (FAIL — bugi: intake saattaa jäädä toimimatta)
func _test_update_bottom_hiekka_alla() -> void:
	print("\n--- Testi 6: update_bottom — alla hiekkaa → ei putoa, mutta imee ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 60), Vector2i(150, 20), 1.0)

	# Aseta hiekkaa suoraan jalustasta kaksi riviä alle (sama kuin intake syvyys dy=2)
	var below_y := launcher.start_pos.y + 2
	for x in range(launcher.start_pos.x, launcher.start_pos.x + 4):
		var idx := below_y * W + x
		if idx >= 0 and idx < grid.size():
			grid[idx] = MAT_SAND

	var sand_placed := _count_mat(MAT_SAND)
	var y_ennen := launcher.start_pos.y

	# 1) Putoaminen pitää estyä hiekan takia
	var liikuttu := launcher.update_bottom(grid, W, 0)

	if not liikuttu:
		_ok("Putoaminen estyi hiekan takia (update_bottom=false)")
	else:
		_fail_msg("Launcher putosi hiekan läpi! (update_bottom=true, y: %d → %d)" % [y_ennen, launcher.start_pos.y])

	if launcher.start_pos.y == y_ennen:
		_ok("start_pos.y pysyi: %d" % y_ennen)
	else:
		_fail_msg("start_pos.y muuttui hiekan läpi: %d → %d" % [y_ennen, launcher.start_pos.y])

	# 2) Imeminen pitää silti toimia vaikka hiekka on suoraan alla
	# Tämä testi TULEE FAILAAMAAN jos intake ei tunnista hiekkaa dy=2:ssa
	launcher.cooldown_timer = 0.0
	launcher.update_launcher(grid, W, 0.1)
	var shaft_size := launcher.shaft_pixels.size()
	var sand_jalkeen := _count_mat(MAT_SAND)

	if shaft_size > 0:
		_ok("Imeminen toimii hiekan ollessa suoraan alla (shaft: %d pikseliä)" % shaft_size)
	else:
		_fail_msg("Imeminen ei toimi hiekan ollessa suoraan alla — launcher jäi jumiin! (shaft tyhjä, sand: %d → %d)" % [sand_placed, sand_jalkeen])

	launcher.free()


# TESTI 7: Kuilunousu ja laukaus — nopeutettu aika (delta=2.0)
func _test_shaft_launch() -> void:
	print("\n--- Testi 7: Kuilunousu ja laukaus (nopeutettu aika) ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 100), Vector2i(150, 60), 1.0)

	# Sijoita hiekkaa intake-alueelle
	var placed := 0
	for x in range(launcher.start_pos.x, launcher.start_pos.x + 4):
		for dy in range(2, 7):
			var py := launcher.start_pos.y + dy
			var idx := py * W + x
			if idx >= 0 and idx < grid.size() and grid[idx] == 0:
				grid[idx] = MAT_SAND
				placed += 1
				if placed >= 3:
					break
		if placed >= 3:
			break

	launcher.cooldown_timer = 0.0
	launcher.update_launcher(grid, W, 0.1)
	var in_shaft := launcher.shaft_pixels.size()
	print("  Kuilussa ennen laukaisua: %d pikseliä" % in_shaft)

	if in_shaft == 0:
		_fail_msg("Kuilussa ei pikseleitä — imeminen ei toiminut!")
		launcher.free()
		return

	# Nopeutettu aika: delta=2.0 → SHAFT_SPEED=180 px/s → 360px → ylittää 40px kuilun
	var launched := launcher.update_shaft(grid, W, H, 2.0)
	if launched.is_empty():
		launched = launcher.update_shaft(grid, W, H, 2.0)

	if launched.size() > 0:
		_ok("%d pikseliä laukaistiin barrel_tip=%s" % [launched.size(), str(launched[0]["pos"])])
	else:
		_fail_msg("Yhtään pikseliä ei laukaisttu!")

	launcher.free()


# TESTI 8: Lentääkö oikeaan suuntaan molemmilla dir-arvoilla?
func _test_launch_direction() -> void:
	print("\n--- Testi 8: Lentosuunta (oikea ja vasen) ---")

	for dir in [1.0, -1.0]:
		_setup_grid()
		var launcher := _make_launcher(Vector2i(150, 100), Vector2i(150, 60), dir)

		var placed_dir := 0
		for x in range(launcher.start_pos.x, launcher.start_pos.x + 4):
			for dy in range(2, 7):
				var py := launcher.start_pos.y + dy
				var idx := py * W + x
				if idx >= 0 and idx < grid.size() and grid[idx] == 0:
					grid[idx] = MAT_SAND
					placed_dir += 1
					if placed_dir >= 3:
						break
			if placed_dir >= 3:
				break

		launcher.cooldown_timer = 0.0
		launcher.update_launcher(grid, W, 0.1)

		if launcher.shaft_pixels.is_empty():
			_fail_msg("dir=%s: kuilussa ei pikseleitä!" % str(dir))
			launcher.free()
			continue

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

		if vel.y < 0:
			_ok("dir=%s: lentää ylöspäin (vel.y=%.1f)" % [str(dir), vel.y])
		else:
			_fail_msg("dir=%s: ei lennä ylöspäin! vel.y=%.1f" % [str(dir), vel.y])

		launcher.free()


# TESTI 9: check_intact ehjä rakenne — kaikki structure_pixels ovat kiveä gridissä → pitäisi palauttaa true
# ODOTETTU TULOS: PASS (check_intact on stub joka palauttaa aina true)
func _test_check_intact_ehja() -> void:
	print("\n--- Testi 9: check_intact — ehjä rakenne (kaikki kivipikselit paikallaan) ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 100), Vector2i(150, 50), 1.0)

	# Varmista että kaikki structure_pixels ovat MAT_STONE gridissä
	var all_stone := true
	for p: Vector2i in launcher.structure_pixels:
		var idx := p.y * W + p.x
		if idx < 0 or idx >= grid.size() or grid[idx] != MAT_STONE:
			all_stone = false
			break

	if all_stone:
		_ok("Kaikki %d structure_pixels ovat kiveä gridissä" % launcher.structure_pixels.size())
	else:
		_fail_msg("Jotkut structure_pixels eivät ole kiveä — write_to_grid ongelma!")

	# check_intact pitäisi palauttaa true ehjälle rakenteelle
	# Tällä hetkellä check_intact on stub joka palauttaa aina true — testi menee läpi
	var intact := launcher.check_intact(grid, W)
	if intact:
		_ok("check_intact palautti true ehjälle rakenteelle")
	else:
		_fail_msg("check_intact palautti false vaikka rakenne on ehjä!")

	launcher.free()


# TESTI 10: check_intact rikkinäinen rakenne — osa rakenteesta poistettu → pitäisi palauttaa false
# ODOTETTU TULOS: FAIL — check_intact on stub joka palauttaa aina true, ei tunnista rikkinäistä rakennetta
func _test_check_intact_rikki() -> void:
	print("\n--- Testi 10: check_intact — rikkinäinen rakenne (ODOTETTTU FAIL: stub) ---")
	_setup_grid()
	var launcher := _make_launcher(Vector2i(150, 100), Vector2i(150, 50), 1.0)

	# Poista puolet structure_pixels-pikselistä gridistä (simuloi räjähdys/kaivaus)
	var removed := 0
	var target := launcher.structure_pixels.size() / 2
	for p: Vector2i in launcher.structure_pixels:
		if removed >= target:
			break
		var idx := p.y * W + p.x
		if idx >= 0 and idx < grid.size():
			grid[idx] = 0  # Tyhjennetään
			removed += 1

	print("  Poistettu %d/%d rakennepikseleistä gridistä" % [removed, launcher.structure_pixels.size()])

	# check_intact pitäisi havaita rikkinäinen rakenne ja palauttaa false
	# TÄMÄ FAILAA: stub palauttaa aina true
	var intact := launcher.check_intact(grid, W)
	if not intact:
		_ok("check_intact palautti false rikkinäiselle rakenteelle (toimii oikein)")
	else:
		_fail_msg("check_intact palautti true vaikka %d pikseliä puuttuu — stub ei tunnista rikkoutumista!" % removed)

	launcher.free()


func _count_mat(mat: int) -> int:
	var count := 0
	for i in TOTAL:
		if grid[i] == mat:
			count += 1
	return count
