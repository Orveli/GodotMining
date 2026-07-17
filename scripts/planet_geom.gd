class_name PlanetGeom
extends RefCounted

# Wrappaa x-koordinaatin valille [0, w). Toimii myos negatiivisille.
static func wrap_x(x: int, w: int) -> int:
	return ((x % w) + w) % w

# Lyhin etumerkillinen x-erotus toruksessa: tulos valilla (-w/2, w/2].
# Kayta AINA kun lasketaan "suuntaa" tai "etaisyytta" x:ssa (heuristiikka, liike, separaatio).
static func wrap_dx(from_x: float, to_x: float, w: float) -> float:
	var d := to_x - from_x
	d = fposmod(d + w * 0.5, w) - w * 0.5
	return d

# Lyhin toroidaalinen euklidinen etaisyys (x wrap, y suora).
static func torus_dist(a: Vector2, b: Vector2, w: float) -> float:
	var dx := wrap_dx(a.x, b.x, w)
	var dy := b.y - a.y
	return sqrt(dx * dx + dy * dy)

# Polaarigeometria (P5/P6 kayttaa). r_surface = w / (2*PI).
static func r_surface(w: float) -> float:
	return w / TAU

# grid (x,y) -> napa (kulma rad, sade px). Kulmaan EI lisata kameraoffsettia (se on P5:ssa).
static func grid_to_polar(gx: float, gy: float, w: float) -> Vector2:
	return Vector2((gx / w) * TAU, r_surface(w) - gy)

# napa (kulma, sade) -> grid (x wräpätty [0,w), y clampaamaton — kutsuja clamppaa).
static func polar_to_grid(theta: float, radius: float, w: float) -> Vector2:
	var gx := fposmod(theta / TAU * w, w)
	var gy := r_surface(w) - radius
	return Vector2(gx, gy)
