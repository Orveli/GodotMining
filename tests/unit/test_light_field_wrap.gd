extends SceneTree

# Yksikkotestit LightFieldin toroidaaliselle (planeetta) x-wrapille.
#  1) _blur_3x3 vaakapassi wrappaa: kirkas sarake saumassa (x=lw-1) vuotaa sarakkeeseen x=0.
#  2) _apply_emitters wrappaa: reunaemitteri (x lahella 0) valaisee sauman yli (x lahella lw-1).
# Kutsuu privaatteja metodeja suoraan y-uniformille / nollatulle _light_f:lle -> ei tarvitse
# renderointia (headless-turvallinen). Ei kutsu update():a (texture-siirto ei ole testin kohde).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_light_field_wrap.gd

# Planeetan v1-koko: sim 4096x448 -> lw=512, lh=56 (DS=8, 4096 on 8-jaollinen -> symmetrinen).
const SIM_W := 4096
const SIM_H := 448

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== LIGHT_FIELD-WRAP-TESTIT ===\n")
	_test_blur_seam_bleed()
	_test_emitter_seam_wrap()
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


func _make_field() -> LightField:
	var lf := LightField.new()
	lf.setup(SIM_W, SIM_H)
	return lf


# Vaakapassin toroidaalisuus: kirkas sarake x=lw-1 (arvo 1.0) kaikilla riveilla. Wrapin ansiosta
# sen valo vuotaa sarakkeeseen x=0 (~1/3). Ilman wrappia (clamp) x=0 jaisi nollaan.
func _test_blur_seam_bleed() -> void:
	print("--- Testi 1: blur vuotaa sauman yli ---")
	var lf := _make_field()
	var lw: int = lf.lw
	var lh: int = lf.lh

	# y-uniform kentta: pystypassi sailyttaa arvot -> lopputulos = vaakablur.
	lf._light_f.fill(0.0)
	for y in lh:
		lf._light_f[y * lw + (lw - 1)] = 1.0

	lf._blur_3x3()

	var col0: float = lf._light_f[0 * lw + 0]
	var col_seam: float = lf._light_f[0 * lw + (lw - 1)]
	print("  x=0 blur=%.4f  x=lw-1 blur=%.4f (odotus ~0.333 kummallekin)" % [col0, col_seam])
	_check(col0 > 0.1, "x=0 sai valoa saumasta (ei clamp-katkoa)")
	_check(absf(col0 - 1.0 / 3.0) < 0.02, "x=0 blur ~ 1/3 (kirkas naapuri sauman yli)")
	_check(absf(col0 - col_seam) < 0.02, "x=0 ja x=lw-1 jatkuvat (sauma huomaamaton)")


# Emitterin toroidaalisuus: emitteri x=2 (lahella saumaa) valaisee cellit myos x=lw-1:n puolella.
# Kaukainen sarake (x=lw/2) jaa pimeaksi -> emitteri on paikallinen, ei globaali.
func _test_emitter_seam_wrap() -> void:
	print("--- Testi 2: emitteri valaisee sauman yli ---")
	var lf := _make_field()
	var lw: int = lf.lw

	lf._light_f.fill(0.0)
	var ey := 224  # ecy = 224/8 = 28 (kokonainen valosolurivi)
	var row := (ey / LightField.DS)
	var emitters: Array = [{"position": Vector2i(2, ey), "radius": 40.0, "intensity": 1.0}]
	lf._apply_emitters(emitters)

	var seam_cell: float = lf._light_f[row * lw + (lw - 1)]
	var far_cell: float = lf._light_f[row * lw + (lw / 2)]
	print("  x=lw-1 valo=%.4f  x=lw/2 valo=%.4f" % [seam_cell, far_cell])
	_check(seam_cell > 0.0, "reunaemitteri valaisee sauman toisella puolella (x=lw-1)")
	_check(far_cell == 0.0, "kaukainen sarake (x=lw/2) jaa pimeaksi (emitteri paikallinen)")
