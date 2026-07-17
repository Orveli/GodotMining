class_name PlanetCamera
extends RefCounted

# Planeetan katselukamera (SPEC_planet P5). Muuntaa ruutupikselit <-> grid-koordinaatit
# kaanteispolaarilla ja tuottaa planet_warp.gdshader:n uniformit. Grid-avaruus pysyy
# suorakulmaisena; tama luokka hoitaa VAIN nakymamuunnoksen (polaari) kameran tilalla.
#
# Malli: planeetan geometrinen keskipiste sijoitetaan ruudulle pisteeseen
#   planet_center = screen_center + (0, radius_center * zoom)
# jolloin sade radius_center osuu ruudun pystykeskelle. radius_center=0 -> koko pallo
# keskitettyna (ydin ruudun keskella); radius_center=R_surface + iso zoom -> pinnan lahikuva.
#
# Kentat joita P6 ohjaa:
#   angle          - kameran kulmaoffset (rad); A/D pyorittaa planeettaa
#   radius_center  - sateittainen keskitys (px); W/S liikuttaa syvyydessa
#   zoom           - ruutupx per world-px; ZOOM_MIN=koko pallo .. ZOOM_MAX=lahi

var angle: float = 0.0             # kameran kulmaoffset (rad, wrap TAU)
var radius_center: float = 0.0     # sateittainen keskitys (px)
var zoom: float = 1.0              # ruutupx per world-px

var world_w: float = 4096.0        # SIM_WIDTH
var world_h: float = 448.0         # SIM_HEIGHT
var screen_size: Vector2 = Vector2(1664.0, 960.0)

# Screen -> world-vektori planeetan keskipisteesta. Sisainen apuri; palauttaa
# (world_vec, r, theta) jossa theta sisaltaa kameran kulman.
func _screen_to_world(screen_px: Vector2) -> Dictionary:
	var planet_center := screen_size * 0.5 + Vector2(0.0, radius_center * zoom)
	var d := screen_px - planet_center
	var safe_zoom := maxf(zoom, 0.0001)
	var world_vec := d / safe_zoom
	var r := world_vec.length()
	var theta := atan2(world_vec.y, world_vec.x) + angle
	return {"world_vec": world_vec, "r": r, "theta": theta}

# Ruutupikseli -> grid (kaanteispolaari). Palauttaa Vector2i(-1,-1) jos taivas (r>R_surface)
# tai ydin (r<R_inner). gx wrapataan [0,W), gy clampataan [0,H).
func screen_to_grid(screen_px: Vector2) -> Vector2i:
	var r_surf := PlanetGeom.r_surface(world_w)
	var r_inner := r_surf - world_h
	var s := _screen_to_world(screen_px)
	var r: float = s["r"]
	if r > r_surf:
		return Vector2i(-1, -1)   # taivas / avaruus
	if r < r_inner:
		return Vector2i(-1, -1)   # ydinmohkale
	var g := PlanetGeom.polar_to_grid(s["theta"], r, world_w)
	var gx := int(g.x)
	var gy := int(g.y)
	if gx < 0:
		gx = 0
	elif gx >= int(world_w):
		gx = int(world_w) - 1
	if gy < 0:
		gy = 0
	elif gy >= int(world_h):
		gy = int(world_h) - 1
	return Vector2i(gx, gy)

# grid -> ruutupikseli (eteenpain). Kaytetaan popover-sijoitteluun (ui.gd grid_to_screen).
# Palauttaa ruutupikselin myos naennaisen nakyvan alueen ulkopuolelta (kutsuja clamppaa).
func grid_to_screen(grid_pos: Vector2) -> Vector2:
	var r_surf := PlanetGeom.r_surface(world_w)
	var polar := PlanetGeom.grid_to_polar(grid_pos.x, grid_pos.y, world_w)
	var theta_grid: float = polar.x
	var r: float = polar.y
	# Kaanna: shaderissa theta = atan2(world_vec) + angle -> atan2 = theta_grid - angle
	var eff := theta_grid - angle
	var world_vec := Vector2(cos(eff), sin(eff)) * r
	var planet_center := screen_size * 0.5 + Vector2(0.0, radius_center * zoom)
	return planet_center + world_vec * zoom

# Paivita planet_warp.gdshader:n uniformit tasta kameran tilasta.
func apply_to_shader(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	var r_surf := PlanetGeom.r_surface(world_w)
	mat.set_shader_parameter("view_angle", angle)
	mat.set_shader_parameter("view_radius_center", radius_center)
	mat.set_shader_parameter("view_zoom", zoom)
	mat.set_shader_parameter("r_surface", r_surf)
	mat.set_shader_parameter("r_inner", r_surf - world_h)
	mat.set_shader_parameter("screen_size", screen_size)

# Zoom jolla koko pallo mahtuu ruudun pystysuuntaan (ZOOM_MIN). radius_center=0 + tama
# zoom -> koko planeetta keskitettyna. P6 kayttaa alarajana.
func whole_planet_zoom() -> float:
	var r_surf := PlanetGeom.r_surface(world_w)
	if r_surf <= 0.0:
		return 1.0
	return (screen_size.y * 0.5) / r_surf
