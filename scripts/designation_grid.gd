# scripts/designation_grid.gd
# Karkea designaatiogridi: pelaaja maalaa louhittavia alueita, botit varaavat ja louhivat.
# Yksi solu = 16x16 px (vastaa navigaatiogridin solua 1:1 -> saavutettavuus yksinkertaistuu:
# designaatiosolu = navsolu, joten "onko OPEN-naapuri" on suora navvertailu). Grid 256x28 = 7168 solua.
# Yksi tavu per solu -> ~7 KB, ladattavissa kokonaan overlay-piirtoon.
# Planeetta: x-akseli jaksollinen (sauma x=0 <-> x=GW-1); get/set/paint wrapaavat x:ssa, y ei.
class_name DesignationGrid
extends RefCounted

const CELL := 16           # solun sivu pikseleina
const GW := 256            # soluja leveyssuunnassa (256*16 = 4096 px); x wrappaa sauman yli
const GH := 28             # soluja korkeussuunnassa (28*16 = 448 px); y ei wrappaa

const PX_W := GW * CELL    # 4096 — designoitavan alueen leveys pikseleina
const PX_H := GH * CELL    # 448  — designoitavan alueen korkeus pikseleina

# Solun tilat. Numerointi lukittu rajapintakontraktiin.
enum { D_NONE = 0, D_QUEUED = 1, D_BLOCKED = 2, D_CLAIMED = 3, D_MINING = 4 }

# Solujen tila, indeksi dy*GW+dx. Julkinen luku-/kirjoituskaytto sallittu, mutta
# muutokset kannattaa tehda set_cell()/paint_px_rect()-kutsuilla jotta `version` pysyy oikeana.
var cells: PackedByteArray

# Kasvaa aina kun jokin solu oikeasti muuttuu. Overlay vertaa tallennettuun arvoon
# ja piirtaa uudelleen vain kun versio on kasvanut.
var version: int = 0


func _init() -> void:
	cells = PackedByteArray()
	cells.resize(GW * GH)
	cells.fill(D_NONE)


func get_cell(dx: int, dy: int) -> int:
	# x wrappaa (jaksollinen); y-rajojen ulkopuoli tulkitaan tyhjaksi (D_NONE), ei kaadu.
	if dy < 0 or dy >= GH:
		return D_NONE
	dx = PlanetGeom.wrap_x(dx, GW)
	return cells[dy * GW + dx]


func set_cell(dx: int, dy: int, v: int) -> void:
	# Aseta yksittaisen solun tila. Ei tee mitaan jos y on rajojen ulkopuolella
	# tai arvo ei muutu (talloin `version` ei myoskaan kasva -> ei turhia overlay-redrawta).
	# x wrappaa (jaksollinen).
	if dy < 0 or dy >= GH:
		return
	dx = PlanetGeom.wrap_x(dx, GW)
	var idx := dy * GW + dx
	if cells[idx] == v:
		return
	cells[idx] = v
	version += 1


func paint_px_rect(r: Rect2i, add: bool, mineable_check: Callable = Callable()) -> void:
	# Muuntaa pikselisuorakulmion soluvyohykkeeksi ja clampaa gridin reunoihin.
	#   add = true  -> asettaa VAIN D_NONE-solut D_QUEUEDiksi (ei ylikirjoita
	#                  BLOCKED/CLAIMED/MINING/QUEUED-tiloja). Jos mineable_check on
	#                  annettu (is_valid()), solu jaa D_NONEksi ellei mineable_check(cx, cy)
	#                  palauta true — nain tyhjan ilman paalle ei voi jonottaa louhintaa.
	#   add = false -> nollaa minka tahansa tilan D_NONEksi.
	if r.size.x <= 0 or r.size.y <= 0:
		return

	# Inklusiivinen viimeinen pikseli.
	var px0 := r.position.x
	var py0 := r.position.y
	var px1 := r.position.x + r.size.x - 1
	var py1 := r.position.y + r.size.y - 1

	# Vain y rajaa; x wrappaa (sauman yli vedetyt kaivuulaatikot sallitaan).
	if py1 < 0 or py0 >= PX_H:
		return

	var cy0 := clampi(py0 / CELL, 0, GH - 1)
	var cy1 := clampi(py1 / CELL, 0, GH - 1)

	# x-solujen span voi olla negatiivinen tai >= GW ennen wrappia; floori sietaa negatiivit.
	# Sauman yli vedettaessa iteroidaan wrapaten (cx = wrap_x(ccx, GW)).
	var ccx0 := floori(float(px0) / float(CELL))
	var ccx1 := floori(float(px1) / float(CELL))
	# Jos veto peittaa koko renkaan, rajaa yhteen kierrokseen (ei paallekkaista maalausta).
	if ccx1 - ccx0 >= GW - 1:
		ccx0 = 0
		ccx1 = GW - 1

	var changed := false
	for cy in range(cy0, cy1 + 1):
		var row := cy * GW
		for ccx in range(ccx0, ccx1 + 1):
			var cx := PlanetGeom.wrap_x(ccx, GW)
			var idx := row + cx
			if add:
				if cells[idx] == D_NONE and (not mineable_check.is_valid() or mineable_check.call(cx, cy)):
					cells[idx] = D_QUEUED
					changed = true
			else:
				if cells[idx] != D_NONE:
					cells[idx] = D_NONE
					changed = true

	if changed:
		version += 1


func cell_px_rect(dx: int, dy: int) -> Rect2i:
	# Solun kattama pikselialue simulaatiokoordinaateissa.
	return Rect2i(dx * CELL, dy * CELL, CELL, CELL)


func any_active() -> bool:
	# True jos yksikin solu on muussa kuin D_NONE-tilassa. Skannaus katkeaa
	# ensimmaiseen aktiiviseen soluun (nopea yleistapaus) — worst case ~7168 tavua.
	for i in cells.size():
		if cells[i] != D_NONE:
			return true
	return false
