# Headless testi LightField-moduulille (itsenäinen, ei riipu pixel_world.gd:stä).
# Käyttö: godot --headless --script scripts/light_field_test.gd
# Tallentaa: debug_lightfield.png
#
# HUOM: tämä testi käyttää synteettistä testimaastoa (ei WorldGen.generate()-kutsua),
# jotta moduuli pysyy täysin itsenäisenä eikä riipu rinnakkain muokattavasta
# world_gen.gd:stä.
extends SceneTree

const LightFieldScript := preload("res://scripts/light_field.gd")

const W := 1664
const H := 960

# Materiaalit (paikallinen kopio — ei importoida pixel_world.gd:tä)
const MAT_EMPTY := 0
const MAT_STONE := 3
const MAT_BEDROCK := 19

const SURFACE_Y := 400          # Maanpinnan y-taso (kaikki tämän yläpuolella = taivas)
const BEDROCK_ROWS := 8         # Pohjakivikerroksen paksuus alareunassa

# Pystykuilut pinnalta alaspäin (leveys 21px, keskitetty näihin x-koordinaatteihin)
const SHAFT_XS := [200, 500, 900, 1300]
const SHAFT_DEPTH := 700        # Kuilujen syvyys (y)

# Vaakatunneli kuilusta (SHAFT_XS[1] = 500) erilliseen kammioon — kammio EI ole
# minkään kuilun suoraan alla, joten sen valon on tultava emitteristä (lampusta/botista),
# ei suoraan taivaalta.
const TUNNEL_Y := 700
const CHAMBER_X := 780
const CHAMBER_R := 55


func _init() -> void:
	print("=== LightField headless-testi ===")

	var grid := _build_synthetic_grid()

	var lf = LightFieldScript.new()
	lf.setup(W, H)
	print("Setup: LW=%d LH=%d (DS=%d, sim=%dx%d)" % [lf.lw, lf.lh, LightFieldScript.DS, W, H])

	# Kammiossa kiinteä lamppu (ei taivasyhteyttä). Lisäksi "botti" joka kävelee
	# alas kuilua x=1300 frame kerrallaan — simuloi tutkimuksen etenemistä ja
	# näyttää että explored-muisti kasvaa monotonisesti eikä koskaan pienene.
	var lamp_emitter := {"position": Vector2i(CHAMBER_X, TUNNEL_Y), "radius": 70.0, "intensity": 1.0}

	var frame_count := 6
	var total_usec := 0
	var prev_explored := 0
	for i in frame_count:
		var bot_y: int = SURFACE_Y + 20 + i * 100  # botti laskeutuu kuiluun syvemmälle joka frame
		var bot_emitter := {"position": Vector2i(SHAFT_XS[3], bot_y), "radius": 40.0, "intensity": 0.8}
		var emitters: Array = [bot_emitter, lamp_emitter]

		var t0 := Time.get_ticks_usec()
		lf.update(grid, emitters)
		var t1 := Time.get_ticks_usec()
		total_usec += (t1 - t0)

		var explored_now := _count_explored(lf)
		print("Frame %d: %.3f ms  (botti y=%d, tutkittu=%d, +%d)" % [
			i, float(t1 - t0) / 1000.0, bot_y, explored_now, explored_now - prev_explored])
		prev_explored = explored_now

	var avg_ms := float(total_usec) / float(frame_count) / 1000.0
	print("Keskimääräinen update()-aika: %.3f ms/frame" % avg_ms)

	_print_stats(lf)
	_print_sample_points(lf)
	_save_debug_png(lf)
	_test_boundaries(lf, grid)

	print("=== Testi valmis, ei kaatumista ===")
	quit()


# Rakentaa yksinkertaisen synteettisen maaston:
# - taivas (EMPTY) pinnan yläpuolella
# - kiveä (STONE) pinnan alla, pohjakivi (BEDROCK) aivan pohjassa
# - 4 pystykuilua pinnalta syvyyteen SHAFT_DEPTH (yhtenäisesti avoimia — taivasyhteys)
# - 1 vaakatunneli + kammio joka EI ole minkään kuilun suoraan alla (vain emitteri valaisee)
func _build_synthetic_grid() -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(W * H)

	for y in H:
		var row_mat := MAT_EMPTY
		if y >= H - BEDROCK_ROWS:
			row_mat = MAT_BEDROCK
		elif y >= SURFACE_Y:
			row_mat = MAT_STONE
		if row_mat != MAT_EMPTY:
			for x in W:
				grid[y * W + x] = row_mat

	# Pystykuilut (leveys 21px — kattaa aina vähintään 2-3 DS=8-näytesaraketta
	# näytteistyskohdasta riippumatta, kuten oikeasti kaivetut, useita pikseleitä
	# leveät kuilut pelissä) pinnalta SHAFT_DEPTH:iin — täysin avoimia
	for sx in SHAFT_XS:
		for y in range(SURFACE_Y, SHAFT_DEPTH):
			for dx in range(-10, 11):
				var x: int = sx + dx
				if x >= 0 and x < W:
					grid[y * W + x] = MAT_EMPTY

	# Vaakatunneli SHAFT_XS[1]:stä CHAMBER_X:ään
	for y in range(TUNNEL_Y - 3, TUNNEL_Y + 3):
		for x in range(SHAFT_XS[1], CHAMBER_X + CHAMBER_R):
			if x >= 0 and x < W:
				grid[y * W + x] = MAT_EMPTY

	# Kammio CHAMBER_X:n ympärillä — ei suoraa taivasyhteyttä (yläpuoli jää kiveksi)
	for y in range(TUNNEL_Y - CHAMBER_R, TUNNEL_Y + CHAMBER_R):
		if y < 0 or y >= H - BEDROCK_ROWS:
			continue
		for x in range(CHAMBER_X - CHAMBER_R, CHAMBER_X + CHAMBER_R):
			if x >= 0 and x < W:
				grid[y * W + x] = MAT_EMPTY

	return grid


func _count_explored(lf) -> int:
	var explored_count := 0
	for f in lf.explored:
		if f > 0.0:
			explored_count += 1
	return explored_count


func _print_stats(lf) -> void:
	var min_v := 255
	var max_v := 0
	var total := 0
	for b in lf.light:
		var v: int = b
		if v < min_v:
			min_v = v
		if v > max_v:
			max_v = v
		total += v
	var avg := float(total) / float(lf.light.size())
	var explored_count := _count_explored(lf)

	print("Valo: min=%d max=%d avg=%.1f (asteikko 0..255)" % [min_v, max_v, avg])
	print("Tutkittu: %d / %d solua (%.1f%%)" % [
		explored_count, lf.explored.size(),
		100.0 * float(explored_count) / float(lf.explored.size())])


# Näytepisteet joilla varmistetaan käyttäytyminen sanallisesti (silmäiltävissä konsolista).
func _print_sample_points(lf) -> void:
	print("--- Näytepisteet (sim-koord -> light 0..255) ---")
	var points := {
		"taivas (50,100)": Vector2i(50, 100),
		"kuilu keskellä, syvällä (200,650)": Vector2i(200, 650),
		"kiinteä kivi kuilujen välissä (350,500)": Vector2i(350, 500),
		"kammio (ei taivasyhteyttä, vain lamppu) (%d,%d)" % [CHAMBER_X, TUNNEL_Y]: Vector2i(CHAMBER_X, TUNNEL_Y),
		"syvä tutkimaton kivi, kaukana kaikesta (1000,850)": Vector2i(1000, 850),
	}
	for label in points.keys():
		var p: Vector2i = points[label]
		var lx: int = mini(p.x / LightFieldScript.DS, lf.lw - 1)
		var ly: int = mini(p.y / LightFieldScript.DS, lf.lh - 1)
		var v: int = lf.light[ly * lf.lw + lx]
		print("  %s: %d" % [label, v])

	print("--- Kuilun (x=200) profiili syvyyden mukaan ---")
	for y in [400, 450, 500, 550, 600, 650, 690]:
		var lx: int = mini(200 / LightFieldScript.DS, lf.lw - 1)
		var ly: int = mini(y / LightFieldScript.DS, lf.lh - 1)
		var v: int = lf.light[ly * lf.lw + lx]
		print("  x=200 y=%d: %d" % [y, v])
	print("--- Kuilun (x=900) profiili syvyyden mukaan ---")
	for y in [400, 450, 500, 550, 600, 650, 690]:
		var lx: int = mini(900 / LightFieldScript.DS, lf.lw - 1)
		var ly: int = mini(y / LightFieldScript.DS, lf.lh - 1)
		var v: int = lf.light[ly * lf.lw + lx]
		print("  x=900 y=%d: %d" % [y, v])


func _save_debug_png(lf) -> void:
	var img := Image.create(W, H, false, Image.FORMAT_RGB8)
	for y in H:
		var ly: int = mini(y / LightFieldScript.DS, lf.lh - 1)
		for x in W:
			var lx: int = mini(x / LightFieldScript.DS, lf.lw - 1)
			var v: int = lf.light[ly * lf.lw + lx]
			var g := float(v) / 255.0
			img.set_pixel(x, y, Color(g, g, g))
	var path := "debug_lightfield.png"
	img.save_png(path)
	print("Tallennettu: " + path)


# Reunatestit: x=0, x=W-1, y=0, y=H-1 — varmistaa ettei indeksointi kaadu.
func _test_boundaries(lf, grid: PackedByteArray) -> void:
	var edge_emitters: Array = [
		{"position": Vector2i(0, 0), "radius": 30.0, "intensity": 1.0},
		{"position": Vector2i(W - 1, H - 1), "radius": 30.0, "intensity": 1.0},
		{"position": Vector2i(0, H - 1), "radius": 20.0, "intensity": 0.5},
		{"position": Vector2i(W - 1, 0), "radius": 20.0, "intensity": 0.5},
		{"position": Vector2i(0, 0), "radius": 0.0, "intensity": 1.0},  # nolla-säde — ei saa kaataa
	]
	lf.update(grid, edge_emitters)
	lf.update(grid, [])  # tyhjä emitter-lista
	print("Reunatesti OK (x=0/%d, y=0/%d, tyhjä emitter-lista — ei kaatunut)" % [W - 1, H - 1])
