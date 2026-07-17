extends SceneTree

# Yksikkotestit PlanetGeomille (scripts/planet_geom.gd).
# Todistaa wrap-kontraktin: wrap_x (negatiiviset + ylivuoto), wrap_dx (lyhin
# etumerkillinen suunta sauman yli), torus_dist (toroidaalinen etaisyys) ja
# grid<->polar edestakainen identiteetti (round-trip).
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_planet_geom.gd

const W := 4096  # v1 planeetta-leveys (spec S2.2)

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== PLANETGEOM-TESTIT ===\n")
	_test_wrap_x()
	_test_wrap_dx()
	_test_torus_dist()
	_test_polar_roundtrip()
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


func _approx(a: float, b: float, eps: float = 0.001) -> bool:
	return absf(a - b) <= eps


# --- Testit -----------------------------------------------------------------

func _test_wrap_x() -> void:
	print("wrap_x:")
	_check(PlanetGeom.wrap_x(0, W) == 0, "wrap_x(0) = 0")
	_check(PlanetGeom.wrap_x(5, 10) == 5, "sisapiste sailyy (5)")
	_check(PlanetGeom.wrap_x(W - 1, W) == W - 1, "wrap_x(W-1) = W-1")
	_check(PlanetGeom.wrap_x(-1, W) == W - 1, "negatiivinen wrap: -1 -> W-1")
	_check(PlanetGeom.wrap_x(W, W) == 0, "ylivuoto: W -> 0")
	_check(PlanetGeom.wrap_x(W + 1, W) == 1, "ylivuoto: W+1 -> 1")
	_check(PlanetGeom.wrap_x(-W - 1, W) == W - 1, "iso negatiivinen: -W-1 -> W-1")


func _test_wrap_dx() -> void:
	print("wrap_dx (lyhin etumerkillinen suunta):")
	_check(_approx(PlanetGeom.wrap_dx(10.0, 30.0, 100.0), 20.0), "sama puoli eteenpain: +20")
	_check(_approx(PlanetGeom.wrap_dx(30.0, 10.0, 100.0), -20.0), "sama puoli taaksepain: -20")
	# Sauman yli lyhyt reitti: x=95 -> x=5 on +10 (eteenpain sauman yli), EI -90.
	_check(_approx(PlanetGeom.wrap_dx(95.0, 5.0, 100.0), 10.0), "sauman yli eteenpain: +10 (ei -90)")
	_check(_approx(PlanetGeom.wrap_dx(5.0, 95.0, 100.0), -10.0), "sauman yli taaksepain: -10 (ei +90)")
	# Spec-esimerkki: wrap_dx(10, W-10, W) ~ -20 (lyhin reitti taaksepain sauman yli).
	_check(_approx(PlanetGeom.wrap_dx(10.0, float(W - 10), float(W)), -20.0), "spec: wrap_dx(10, W-10, W) = -20")
	# Aina rajoissa: |wrap_dx| <= w/2.
	var all_bounded := true
	for tx in [0, 1, 37, 512, 2047, 2048, 3000, 4095]:
		var d: float = PlanetGeom.wrap_dx(0.0, float(tx), float(W))
		if absf(d) > float(W) / 2.0 + 0.001:
			all_bounded = false
	_check(all_bounded, "|wrap_dx| <= w/2 kaikilla naytepisteilla")


func _test_torus_dist() -> void:
	print("torus_dist:")
	# Sauman yli: (2,0) ja (W-2,0) ovat 4 px paassa (ei W-4).
	_check(_approx(PlanetGeom.torus_dist(Vector2(2, 0), Vector2(W - 2, 0), float(W)), 4.0),
		"sauman yli: dist((2,0),(W-2,0)) = 4")
	# Ei wrappia: euklidinen 3-4-5.
	_check(_approx(PlanetGeom.torus_dist(Vector2(0, 0), Vector2(3, 4), float(W)), 5.0),
		"ilman wrappia: 3-4-5 = 5")
	# y ei wrappaa: pysty-etaisyys suora.
	_check(_approx(PlanetGeom.torus_dist(Vector2(10, 0), Vector2(10, 40), float(W)), 40.0),
		"y ei wrappaa: pystysuora 40")


func _test_polar_roundtrip() -> void:
	print("grid<->polar round-trip:")
	_check(_approx(PlanetGeom.r_surface(float(W)), float(W) / TAU), "r_surface(W) = W/TAU")
	var samples := [Vector2(0, 0), Vector2(100, 50), Vector2(2048, 200), Vector2(4095, 447)]
	var ok := true
	for s in samples:
		var polar: Vector2 = PlanetGeom.grid_to_polar(s.x, s.y, float(W))
		var back: Vector2 = PlanetGeom.polar_to_grid(polar.x, polar.y, float(W))
		if not (_approx(back.x, s.x, 0.01) and _approx(back.y, s.y, 0.01)):
			ok = false
			print("    round-trip poikkeama: %s -> %s" % [str(s), str(back)])
	_check(ok, "polar_to_grid(grid_to_polar(p)) == p kaikilla naytteilla")
