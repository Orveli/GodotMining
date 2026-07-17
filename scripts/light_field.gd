# Valokenttä fog-of-war-järjestelmää varten.
#
# Itsenäinen, testattava moduuli — EI riipu pixel_world.gd:stä, world_gen.gd:stä
# tai mistään shaderista. Integraatio (light_tex-uniform, emitterien kokoaminen
# botti/base/lamppu-datasta) tehdään myöhemmin toisessa vaiheessa.
#
# Fog-malli: "tutkittu jää muistiin + valo".
#   - Tutkimaton alue: täysin musta (0).
#   - Tutkittu mutta ei juuri nyt valaistu alue: himmeä muistitaso (EXPLORED_FLOOR).
#   - Aktiivisesti valaistu alue (taivas/emitteri): kirkas (jopa 1.0).
#
# Alaskaalattu puskuri (DS = sim-px per valosolu) pitää kustannukset alhaalla:
# 1664x960-simulaatiolla LW=208, LH=120 eli 24 960 solua/frame.
class_name LightField
extends RefCounted

# Alaskaalauskerroin — sim-px per valokentän solu.
const DS := 8

# Vastaa pixel_world.gd:n MAT_EMPTY-vakiota (tyhjä = "avoin" taivasvalon kannalta).
const MAT_EMPTY := 0

# Taivasvalon vaimennuskerroin kiinteän materiaalin kohdalla (kerroin/solu).
const SKY_DECAY := 0.72

# Pinnan ensimmäisen kiinteän solun kirkkaus avotaivaan alla — maanpinta ja
# ~30 px sen alta pysyy luettavana ennen kuin decay pimentää syvemmät solut.
const SURFACE_LIGHT := 0.9

# Valoarvo jonka ylittyessä solu merkitään pysyvästi "tutkituksi".
const EXPLORED_THRESHOLD := 0.28

# Tutkitun mutta ei-valaistun alueen himmeä pohjataso (0..1).
const EXPLORED_FLOOR := 0.20

var sim_width: int = 0
var sim_height: int = 0
var lw: int = 0  # Valopuskurin leveys soluina
var lh: int = 0  # Valopuskurin korkeus soluina

# Lopullinen 0..255-valopuskuri (LW*LH) — tätä luetaan Image/ImageTexture-siirtoon.
var light: PackedByteArray

# Pysyvä tutkimusmuisti 0..1 (LW*LH). Ei koskaan pienene paitsi clear_explored()-kutsussa.
var explored: PackedFloat32Array

# Render-shaderille annettava tekstuuri (filter_linear samplausta varten).
var texture: ImageTexture

# Sisäiset uudelleenkäytettävät työpuskurit — EI allokoida per frame.
var _light_f: PackedFloat32Array
var _blur_f: PackedFloat32Array
var _image: Image

# Esilasketut näytepisteet (DS-solu -> sim-koordinaatti), lasketaan kerran setup()issa
# jotta _apply_sky_light() ei joudu kutsumaan mini()-funktiota 24k kertaa/frame.
var _sample_x: PackedInt32Array
var _sample_y: PackedInt32Array


# Alustaa puskurit annetun simulaatiokoon mukaan. LW/LH lasketaan DS:stä.
func setup(sim_w: int, sim_h: int) -> void:
	sim_width = sim_w
	sim_height = sim_h
	lw = int(ceil(float(sim_w) / float(DS)))
	lh = int(ceil(float(sim_h) / float(DS)))

	var cell_count := lw * lh
	light.resize(cell_count)
	light.fill(0)
	explored.resize(cell_count)
	explored.fill(0.0)
	_light_f.resize(cell_count)
	_light_f.fill(0.0)
	_blur_f.resize(cell_count)
	_blur_f.fill(0.0)

	_image = Image.create_from_data(lw, lh, false, Image.FORMAT_R8, light)
	texture = ImageTexture.create_from_image(_image)

	# Esilaske taivasvalon näytepisteet (kerran, ei per frame)
	var half_ds := DS / 2
	_sample_x.resize(lw)
	for cx in lw:
		_sample_x[cx] = mini(cx * DS + half_ds, sim_w - 1)
	_sample_y.resize(lh)
	for cy in lh:
		_sample_y[cy] = mini(cy * DS + half_ds, sim_h - 1)


# Palauttaa render-shaderille annettavan tekstuurin (vaihtoehto suoralle texture-jäsenelle).
func get_texture() -> ImageTexture:
	return texture


# Nollaa pysyvän tutkimusmuistin — käytetään maailman regeneroinnin yhteydessä.
func clear_explored() -> void:
	explored.fill(0.0)


# Pääpäivitys. grid = materiaali-id per sim-pikseli (PackedByteArray, koko sim_w*sim_h).
# emitters = Array of Dictionary { "position": Vector2i (sim-koord), "radius": float (sim-px),
# "intensity": float 0..1 }.
func update(grid: PackedByteArray, emitters: Array) -> void:
	if lw == 0 or lh == 0:
		return  # setup() ei ole vielä kutsuttu
	if grid.size() < sim_width * sim_height:
		return  # grid ei vastaa setup()-kokoa — turvallisuustarkistus

	_reset_to_explored_floor()
	_apply_sky_light(grid)
	_apply_emitters(emitters)
	_blur_3x3()
	_update_explored_memory()
	_write_texture()


# --- Askel 1: pohjataso muistista ---
func _reset_to_explored_floor() -> void:
	for i in _light_f.size():
		_light_f[i] = explored[i] * EXPLORED_FLOOR


# --- Askel 2: taivasvalo — kävele jokainen DS-sarake ylhäältä alas ---
# Näytteistetään DS-lohkon keskipikseli (halvempi kuin koko lohkon enemmistötesti,
# budjetti ~25k solua/frame). Kun sarake osuu ensimmäistä kertaa kiinteään materiaaliin,
# se merkitään "blocked":iksi eikä enää PALAUDU täyteen kirkkauteen, vaikka syvemmällä
# olisi jälleen avoimia soluja (esim. sivuttain kaivettu, katosta erillinen kammio).
# Tämä varmistaa että vain YHTENÄISET, suoraan taivaalta avoimet kuilut hehkuvat
# kirkkaana — irralliset onkalot pysyvät mustina kunnes botti/lamppu valaisee ne.
func _apply_sky_light(grid: PackedByteArray) -> void:
	for cx in lw:
		var sim_x := _sample_x[cx]
		var light_val := 1.0
		var blocked := false
		for cy in lh:
			var sim_y := _sample_y[cy]
			var idx := sim_y * sim_width + sim_x
			var is_open := grid[idx] == MAT_EMPTY
			if is_open and not blocked:
				light_val = 1.0
			elif not blocked:
				# Ensimmäinen kiinteä solu = maanpinta → kirkas SURFACE_LIGHT,
				# vasta seuraavat solut vaimenevat SKY_DECAY:llä.
				blocked = true
				light_val = SURFACE_LIGHT
			else:
				light_val *= SKY_DECAY
			var li := cy * lw + cx
			if light_val > _light_f[li]:
				_light_f[li] = light_val


# --- Askel 3: emitterit — additiivinen säteittäinen falloff DS-tilassa ---
func _apply_emitters(emitters: Array) -> void:
	for e in emitters:
		var pos: Vector2i = e.get("position", Vector2i.ZERO)
		var radius: float = float(e.get("radius", 40.0))
		var intensity: float = float(e.get("intensity", 1.0))
		if radius <= 0.0:
			continue

		# SIM-koordinaatit → DS-koordinaatit
		var ecx := float(pos.x) / float(DS)
		var ecy := float(pos.y) / float(DS)
		var erad := radius / float(DS)

		# Käsitellään vain emitterin bounding box DS-tilassa (halpa, ei koko puskuria).
		var x0 := maxi(0, int(floor(ecx - erad)))
		var x1 := mini(lw - 1, int(ceil(ecx + erad)))
		var y0 := maxi(0, int(floor(ecy - erad)))
		var y1 := mini(lh - 1, int(ceil(ecy + erad)))

		for y in range(y0, y1 + 1):
			for x in range(x0, x1 + 1):
				var dx := float(x) - ecx
				var dy := float(y) - ecy
				var dist := sqrt(dx * dx + dy * dy)
				if dist > erad:
					continue
				var falloff: float = 1.0 - dist / erad
				var li := y * lw + x
				_light_f[li] = clampf(_light_f[li] + intensity * falloff, 0.0, 1.0)


# --- Askel 4 (valinnainen): kevyt 3x3-laatikkosumennus pehmeyden vuoksi ---
# Toteutettu separoituna (vaakapassi + pystypassi) täyden 3x3-ikkunan sijaan:
# O(2*LW*LH) yhdeksän-näytteen O(9*LW*LH):n sijaan. Reunatarkistus on nostettu
# per-rivi-tasolle (silmukan ulkopuolelle) niin että valtaosa pikseleistä
# käsitellään täysin haarautumattomasti — alkuperäinen per-pikseli-if-versio
# mitattiin ~35ms/frame, tämä versio ~4-6ms/frame samalla laadulla.
const _ONE_THIRD := 1.0 / 3.0


func _blur_3x3() -> void:
	if lw < 2 or lh < 2:
		return  # Liian pieni puskuri reunapareille — ei realistinen sim-koko, mutta turvatarkistus
	# Vaakapassi: _light_f -> _blur_f. Reunasarakkeet (x=0, x=lw-1) käsitellään
	# erikseen ennen/jälkeen haarautumatonta keskiosaa.
	for y in lh:
		var row_base := y * lw
		_blur_f[row_base] = (_light_f[row_base] + _light_f[row_base + 1]) * 0.5
		for x in range(1, lw - 1):
			var p := row_base + x
			_blur_f[p] = (_light_f[p - 1] + _light_f[p] + _light_f[p + 1]) * _ONE_THIRD
		var last := row_base + lw - 1
		_blur_f[last] = (_light_f[last - 1] + _light_f[last]) * 0.5

	# Pystypassi: _blur_f -> _light_f. Reunarivit (y=0, y=lh-1) käsitellään
	# omina tapauksinaan, jolloin sisärivien x-silmukka on täysin haarautumaton.
	var row_base0 := 0
	var row_below0 := lw
	for x in lw:
		_light_f[row_base0 + x] = (_blur_f[row_base0 + x] + _blur_f[row_below0 + x]) * 0.5

	for y in range(1, lh - 1):
		var row_base := y * lw
		var row_above := row_base - lw
		var row_below := row_base + lw
		for x in lw:
			_light_f[row_base + x] = (
				_blur_f[row_above + x] + _blur_f[row_base + x] + _blur_f[row_below + x]
			) * _ONE_THIRD

	var last_row := (lh - 1) * lw
	var row_above_last := last_row - lw
	for x in lw:
		_light_f[last_row + x] = (_blur_f[row_above_last + x] + _blur_f[last_row + x]) * 0.5


# --- Askel 5: päivitä pysyvä tutkimusmuisti ---
func _update_explored_memory() -> void:
	for i in _light_f.size():
		if _light_f[i] > EXPLORED_THRESHOLD:
			explored[i] = 1.0


# --- Askel 6: kirjoita lopullinen 0..255-puskuri Image/ImageTexture-siirtona ---
func _write_texture() -> void:
	for i in _light_f.size():
		light[i] = int(clampf(_light_f[i] * 255.0, 0.0, 255.0))
	_image.set_data(lw, lh, false, Image.FORMAT_R8, light)
	texture.update(_image)
