extends SceneTree

# Yksikkotestit PlanetCameralle (scripts/planet_camera.gd, SPEC_planet P5).
# Todistaa polaarikameran matematiikan:
#   - screen_to_grid / grid_to_screen ovat toistensa kaanteisoperaatioita
#     (round-trip) eri angle/zoom/radius_center-arvoilla, nakyvalla sadealueella.
#   - taivas (r > R_surface) ja ydin (r < R_inner) palautuvat (-1,-1).
#   - apply_to_shader tayttaa oikeat uniformit.
#   - whole_planet_zoom on positiivinen.
#
# Renderointia EI testata (integraattorin ikkunallinen verifiointi). Tama testaa
# vain matematiikan grid-avaruudessa.
#
# Aja headless:
#   godot --headless --path . --script res://tests/unit/test_planet_camera.gd

const W := 4096   # v1 planeetta-leveys (spec S2.2)
const H := 448    # v1 planeetta-syvyys

var _pass := 0
var _fail := 0


func _init() -> void:
	print("=== PLANETCAMERA-TESTIT ===\n")
	_test_roundtrip()
	_test_sky_and_core()
	_test_apply_to_shader()
	_test_whole_planet_zoom()
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


func _make_cam() -> PlanetCamera:
	var cam := PlanetCamera.new()
	cam.world_w = float(W)
	cam.world_h = float(H)
	cam.screen_size = Vector2(1664.0, 960.0)
	return cam


# --- Testit -----------------------------------------------------------------

# Round-trip: kaytetaan grid-pisteita LAHTONA (grid_to_screen tuottaa taatusti
# planeetalle osuvan ruutupisteen). Sitten screen_to_grid palauttaa solun, ja
# grid_to_screen siita takaisin ~ alkuperainen ruutupiste. Epsilon huomioi solun
# katkaisun (int-trunkkaus): yksi grid-yksikko = zoom ruutupikselia.
func _test_roundtrip() -> void:
	print("round-trip grid<->screen (eri angle/zoom/radius_center):")
	var cam := _make_cam()
	# (angle, radius_center, zoom). Kattaa koko pallon, kierron ja lahikuvat.
	var configs := [
		[0.0, 0.0, cam.whole_planet_zoom()],
		[1.2, 0.0, cam.whole_planet_zoom()],
		[-2.0, 200.0, 1.5],
		[TAU * 0.75, 400.0, 3.0],
		[3.14159, 500.0, 0.9],
	]
	# Sisapiste-naytteet: gy valilla [3, H-4] jotta r pysyy tiukasti (R_inner, R_surface].
	var gxs := [0, 100, 1000, 2048, 3000, 4095]
	var gys := [3, 50, 200, 400, 444]
	var worst := 0.0
	var ok := true
	for cfg in configs:
		cam.angle = cfg[0]
		cam.radius_center = cfg[1]
		cam.zoom = cfg[2]
		var eps: float = 2.0 * cam.zoom + 1.0
		for gx in gxs:
			for gy in gys:
				var g := Vector2(float(gx), float(gy))
				var p: Vector2 = cam.grid_to_screen(g)
				var g2: Vector2i = cam.screen_to_grid(p)
				if g2.x < 0:
					ok = false
					print("    in-band epaonnistui: g=%s cfg=%s -> (-1,-1)" % [str(g), str(cfg)])
					continue
				var p2: Vector2 = cam.grid_to_screen(Vector2(g2))
				var err: float = (p2 - p).length()
				if err > worst:
					worst = err
				if err > eps:
					ok = false
					print("    round-trip poikkeama %.3f > %.3f: g=%s cfg=%s" % [err, eps, str(g), str(cfg)])
	_check(ok, "grid_to_screen(screen_to_grid(p)) ~ p kaikilla naytteilla (worst=%.3f)" % worst)

	# Lisatarkistus: nolla-kierto ja nolla-offset -> tunnettu geometria. Pinnan piste
	# gy=0 (r=R_surface) osuu etaisyydelle R_surface*zoom planeetan keskipisteesta.
	cam.angle = 0.0
	cam.radius_center = 0.0
	cam.zoom = cam.whole_planet_zoom()
	var center := cam.screen_size * 0.5
	# gx=0 -> theta=0 -> +x-suunta pinnalla.
	var surf := cam.grid_to_screen(Vector2(0.0, 0.0))
	var expect_r := PlanetGeom.r_surface(float(W)) * cam.zoom
	_check(absf((surf - center).length() - expect_r) < 0.01, "pinnan piste etaisyydella R_surface*zoom keskipisteesta")


func _test_sky_and_core() -> void:
	print("taivas + ydin -> (-1,-1):")
	var cam := _make_cam()
	cam.angle = 0.0
	cam.radius_center = 0.0
	cam.zoom = cam.whole_planet_zoom()
	var center := cam.screen_size * 0.5
	# Kaukana keskipisteesta -> r > R_surface -> taivas.
	var sky := cam.screen_to_grid(center + Vector2(2000.0, 0.0))
	_check(sky == Vector2i(-1, -1), "kaukainen piste -> taivas (-1,-1)")
	# Tasmalleen keskipiste -> r=0 < R_inner -> ydin.
	var core := cam.screen_to_grid(center)
	_check(core == Vector2i(-1, -1), "keskipiste -> ydin (-1,-1)")
	# Pinnan lahelta osuu grid-soluun (ei taivas/ydin).
	var r_surf := PlanetGeom.r_surface(float(W))
	var on := cam.screen_to_grid(center + Vector2((r_surf - 5.0) * cam.zoom, 0.0))
	_check(on.x >= 0 and on.y >= 0, "pinnan lahella -> validi grid-solu")


func _test_apply_to_shader() -> void:
	print("apply_to_shader tayttaa uniformit:")
	var cam := _make_cam()
	cam.angle = 1.5
	cam.radius_center = 321.0
	cam.zoom = 2.25
	var mat := ShaderMaterial.new()
	cam.apply_to_shader(mat)
	var r_surf := PlanetGeom.r_surface(float(W))
	_check(absf(float(mat.get_shader_parameter("view_angle")) - 1.5) < 1e-4, "view_angle")
	_check(absf(float(mat.get_shader_parameter("view_radius_center")) - 321.0) < 1e-4, "view_radius_center")
	_check(absf(float(mat.get_shader_parameter("view_zoom")) - 2.25) < 1e-4, "view_zoom")
	_check(absf(float(mat.get_shader_parameter("r_surface")) - r_surf) < 1e-2, "r_surface = W/TAU")
	_check(absf(float(mat.get_shader_parameter("r_inner")) - (r_surf - float(H))) < 1e-2, "r_inner = R_surface - H")
	var ss: Vector2 = mat.get_shader_parameter("screen_size")
	_check(ss == Vector2(1664.0, 960.0), "screen_size")


func _test_whole_planet_zoom() -> void:
	print("whole_planet_zoom:")
	var cam := _make_cam()
	var z := cam.whole_planet_zoom()
	# Koko pallo mahtuu pystyyn: R_surface * z ~ ruudun puolikorkeus.
	var expect := (cam.screen_size.y * 0.5) / PlanetGeom.r_surface(float(W))
	_check(z > 0.0, "positiivinen")
	_check(absf(z - expect) < 1e-4, "R_surface*z = ruudun puolikorkeus")
