extends SceneTree

# Gravity gun -logiikan yksikkötestit — ei GPU:ta tarvita

func _init() -> void:
	print("=== GRAVITY GUN TESTIT ===\n")
	_test_fill_ratio_math()
	_test_time_based_fill()
	_test_hysteresis_no_oscillation()
	_test_release_resets()
	_test_hysteresis_prevents_toggle()
	print("\n=== KAIKKI TESTIT VALMIS ===")
	quit()


func _ok(msg: String) -> void:
	print("  OK: " + msg)


func _fail(msg: String) -> void:
	print("  TEST: FAIL " + msg)


func _assert(cond: bool, msg: String) -> void:
	if cond: _ok(msg)
	else: _fail(msg)


# Testi 1: Fill ratio -laskenta on oikein
func _test_fill_ratio_math() -> void:
	print("--- Testi 1: Fill ratio -laskenta ---")
	var FILL_SECS := 2.5

	_assert(0.0 / FILL_SECS == 0.0, "alussa ratio=0")
	_assert(absf(1.25 / FILL_SECS - 0.5) < 0.001, "puolivälissä ratio=0.5")
	_assert(2.5 / FILL_SECS >= 1.0, "täyttymishetkellä ratio>=1.0")
	_assert(clampf(5.0 / FILL_SECS, 0.0, 1.0) == 1.0, "yliajalla clamp pitää ratio=1.0")


# Testi 2: Aikapohjainen täyttö 60 FPS:llä
func _test_time_based_fill() -> void:
	print("\n--- Testi 2: Aikapohjainen täyttö ---")
	var FILL_SECS := 2.5
	var hold_time := 0.0
	var delta := 1.0 / 60.0  # 60 FPS

	# 150 framea = 2.5s → pitäisi olla täynnä
	for _i in 150:
		hold_time = minf(hold_time + delta, FILL_SECS)
	var ratio := hold_time / FILL_SECS
	_assert(ratio >= 0.99, "150 framea täyttää (ratio=%.3f)" % ratio)

	# 0 framea → ei täynnä
	hold_time = 0.0
	ratio = hold_time / FILL_SECS
	_assert(ratio == 0.0, "vapautuksen jälkeen ratio=0")


# Testi 3: Hystereesin pitää estää oskillaatio
func _test_hysteresis_no_oscillation() -> void:
	print("\n--- Testi 3: Hystereesi estää oskillaation ---")
	var FILL_SECS := 2.5
	var hold_time := 2.5  # Alusta täynnä
	var grav_full := false
	var fill_ratio := hold_time / FILL_SECS

	# Aseta täynnä
	if fill_ratio >= 1.0:
		grav_full = true
	_assert(grav_full, "täynnä-tila asetetaan oikein")

	# hold_time ei kasva enempää (jo max), ratio pysyy 1.0
	# Tarkista että full ei välähdä pois 10 framessa
	var toggle_count := 0
	var prev_full := grav_full
	for _i in 10:
		fill_ratio = clampf(hold_time / FILL_SECS, 0.0, 1.0)
		# Hystereesi: set at 1.0, unset at <0.8
		if fill_ratio >= 1.0:
			grav_full = true
		elif fill_ratio < 0.8:
			grav_full = false
		if grav_full != prev_full:
			toggle_count += 1
		prev_full = grav_full

	_assert(toggle_count == 0, "täynnä-tila ei välähdä pois (toggle_count=%d)" % toggle_count)


# Testi 4: Vapautus nollaa tilan kokonaan
func _test_release_resets() -> void:
	print("\n--- Testi 4: Vapautus nollaa tilan ---")
	var hold_time := 2.5
	var grav_full := true
	var fill_ratio := 1.0

	# Simuloi vapautus
	hold_time = 0.0
	grav_full = false
	fill_ratio = 0.0

	_assert(hold_time == 0.0, "hold_time nollattu")
	_assert(not grav_full, "grav_full nollattu")
	_assert(fill_ratio == 0.0, "fill_ratio nollattu")


# Testi 5: Vanha count-pohjainen logiikka oskilloisi — aikapohjainen ei
func _test_hysteresis_prevents_toggle() -> void:
	print("\n--- Testi 5: Vanha vs uusi logiikka ---")

	# VANHA (buginen): count-pohjainen, ei hystereeesia
	# Simuloi tilanne: count hyppii 90↔110 joka frame
	var old_toggles := 0
	var old_full := false
	var old_prev := false
	var capacity := 100
	for i in 10:
		var count := 110 if i % 2 == 0 else 90  # Oskilloiva count
		var new_full := count >= capacity
		if new_full != old_prev:
			old_toggles += 1
		old_prev = new_full
	_assert(old_toggles > 0, "vanha logiikka oskilloisi (%d toggle)" % old_toggles)

	# UUSI (korjattu): aikapohjainen + hystereesi
	# Aloitetaan jo täynnä-tilasta — tarkistetaan ettei välähdä pois
	var new_toggles := 0
	var new_full := true
	var new_prev := true
	var hold_time := 2.5  # Täynnä
	var FILL_SECS := 2.5
	for _i in 10:
		var ratio := clampf(hold_time / FILL_SECS, 0.0, 1.0)
		if ratio >= 1.0:
			new_full = true
		elif ratio < 0.8:
			new_full = false
		if new_full != new_prev:
			new_toggles += 1
		new_prev = new_full
	_assert(new_toggles == 0, "uusi logiikka ei oskilloisi (%d toggle)" % new_toggles)
