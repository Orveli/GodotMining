class_name DiscGeom
extends RefCounted

# Kiekkoplaneetan geometria + sektorigravitaatio (docs/SPEC_disc_planet.md).
# Grid on N×N; planeetta on kiekko gridin keskella. Solukeskipisteiden symmetria
# hoidetaan 2x-skaalatuilla deltoilla: dxc = 2x-(N-1) on aina PARITON kun N on
# parillinen -> ei koskaan nollaa, sign aina ±1, ei puolen pikselin biasia.
#
# TAMA ON JAETTU PERUSTA: simulation_disc.glsl toistaa saman matikan GLSL:na.
# ALA muuta rajapintaa tai konventioita ilman etta paivitat molemmat + spec.

const GRID_N := 1408          # gridin sivu; 16:n monikerta (88 tilea/akseli), PARILLINEN
const R_PLANET := 640         # planeetan sade (px, solukeskipiste-etaisyys)
const R_CORE := 40            # bedrock-ydin (peittaa sektorien kohtauspisteen)

# Materiaali-ID:t — TASMALLEEN samat kuin simulation.glsl / CLAUDE.md.
const MAT_EMPTY := 0
const MAT_SAND := 1
const MAT_WATER := 2
const MAT_STONE := 3
const MAT_WOOD := 4
const MAT_FIRE := 5
const MAT_OIL := 6
const MAT_STEAM := 7
const MAT_ASH := 8
const MAT_WOOD_FALLING := 9
const MAT_GLASS := 10
const MAT_DIRT := 11
const MAT_IRON_ORE := 12
const MAT_GOLD_ORE := 13
const MAT_IRON := 14
const MAT_GOLD := 15
const MAT_COAL := 16
const MAT_HELD := 17
const MAT_GRAVEL := 18
const MAT_BEDROCK := 19
const MAT_COPPER := 20
const MAT_RARE_EARTH := 21


# 2x-skaalattu x-delta keskipisteesta (aina pariton kun n parillinen).
static func dxc(x: int, n: int = GRID_N) -> int:
	return 2 * x - (n - 1)


# 2x-skaalattu y-delta keskipisteesta.
static func dyc(y: int, n: int = GRID_N) -> int:
	return 2 * y - (n - 1)


# Sektorikohtainen "alas" = painovoiman suunta kohti keskipistetta.
# |dxc| > |dyc| -> vaakasektori, muuten pystysektori (tasapeli 45°-diagonaalilla -> pysty).
# Koska dxc/dyc eivat koskaan ole 0, tulos on aina yksikkovektori.
static func down_of(x: int, y: int, n: int = GRID_N) -> Vector2i:
	var dx := dxc(x, n)
	var dy := dyc(y, n)
	if absi(dx) > absi(dy):
		return Vector2i(-1 if dx > 0 else 1, 0)
	return Vector2i(0, -1 if dy > 0 else 1)


# Kohtisuora sivusuunta (90° kaannos down-vektorista).
static func perp_of(down: Vector2i) -> Vector2i:
	return Vector2i(-down.y, down.x)


# Onko solu sateen r sisalla keskipisteesta? 2x-skaalattu kokonaislukuvertailu (ei floatteja).
static func inside_radius(x: int, y: int, r: int, n: int = GRID_N) -> bool:
	var dx := dxc(x, n)
	var dy := dyc(y, n)
	return dx * dx + dy * dy <= (2 * r) * (2 * r)


# Onko solu planeettakiekon sisalla?
static func inside_planet(x: int, y: int, n: int = GRID_N) -> bool:
	return inside_radius(x, y, R_PLANET, n)


# Onko solu bedrock-ytimessa?
static func inside_core(x: int, y: int, n: int = GRID_N) -> bool:
	return inside_radius(x, y, R_CORE, n)


# Etaisyys keskipisteesta (float, solukeskipisteet).
static func radius_of(x: int, y: int, n: int = GRID_N) -> float:
	var dx := float(dxc(x, n))
	var dy := float(dyc(y, n))
	return sqrt(dx * dx + dy * dy) * 0.5
