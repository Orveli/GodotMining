extends Control
# ═══════════════════════════════════════════════════════════════════════════
# UI_BOT_STATUS_OVERLAY — botin tila diegeettisesti maailmassa
# (UI_REDESIGN_PLAN.md Vaihe 4, kohta 10: "botti-status maailmaan")
#
# Piirtää jokaisen botin yläpuolelle pienen kuormapalkin (täyttöaste) ja himmentää
# IDLE-botit. Roolierottelu (miner=amber/hauler=sininen) on jo botin runkovärissä
# (bot_manager.gd draw_bots()) — tämä overlay VAIN täydentää sitä, EI koske
# bottien tilakoneeseen tai piirtologiikkaan millään tavalla (erillinen Control,
# lukee vain get_fleet_stats()-datan).
#
# Koordinaatit: get_fleet_stats()["bots"][i]["pos"] on sim-pikselikoordinaatti.
# pixel_world.grid_to_screen() muuntaa sen ruutukoordinaatiksi (huomioi zoom/pan).
# Tämä Control lisätään "UI"-CanvasLayeriin (sama taso kuin muu HUD) — ei
# building_layerin lapseksi, koska sen skaalaus vastaisi vain zoomia eikä
# CanvasLayerin omaa (aina 1:1) koordinaatistoa.
# ═══════════════════════════════════════════════════════════════════════════

var pixel_world: TextureRect = null

# Bot.Role / Bot.BotState -kopiot (vältetään riippuvuus class_name-cacheen, ks.
# CLAUDE.md: Godot Testing Gotchas — preload-viittaus olisi turha tässä koska
# tarvitaan vain kaksi kokonaislukuvakiota).
const ROLE_MINER := 0
const BOT_STATE_IDLE := 0
const BOT_STATE_SEEK_CHARGE := 5   # M3
const BOT_STATE_CHARGING := 6      # M3
# Idle-syy (bot_manager.gd IDLE_REASON_*): vain ALL_BLOCKED nostetaan diegeettisesti esiin (P0-1b).
const IDLE_REASON_ALL_BLOCKED := 3
const IDLE_REASON_WAITING_CHARGER := 6  # M3

const BAR_W := 14.0
const BAR_H := 3.0
const BAR_OFFSET_Y := -11.0
const COL_BAR_BG := Color(0.05, 0.05, 0.08, 0.85)
const COL_BAR_MINER := Color(0.88, 0.66, 0.25, 0.95)
const COL_BAR_HAULER := Color(0.35, 0.62, 0.95, 0.95)
const IDLE_ALPHA := 0.35   # himmennys kun botti on IDLE (ei töissä)

# M3: akkupalkki kuormapalkin alapuolella + lataustilan ikoni.
const BATT_BAR_H := 2.0
const BATT_BAR_OFFSET_Y := -7.0
const COL_BATT_OK := Color(0.45, 0.85, 0.4, 0.95)     # vihreä = riittää
const COL_BATT_LOW := Color(0.95, 0.35, 0.2, 0.95)    # punainen = vähissä (hakeutuu lataukseen)
const BATT_LOW_FRAC := 0.2                             # BATTERY_SEEK / BATTERY_MAX = 18/90
const COL_CHARGE := Color(1.0, 0.85, 0.25, 1.0)       # keltainen lataussalama
const COL_WAIT := Color(1.0, 0.55, 0.15, 1.0)         # amber = odottaa vuoroa

# P0-1b: "ei reittiä" -varoitus tavoittamattoman designaation ylle jaaneelle idle-minerille.
const COL_WARN := Color(1.0, 0.55, 0.15, 1.0)      # amber-oranssi huutomerkki (erottuu himmennyksesta)
const COL_WARN_BG := Color(0.05, 0.05, 0.08, 0.9)  # tumma tausta luettavuudelle
const WARN_TEXT := "! ei reittiä"
const WARN_FONT_SIZE := 9
const WARN_OFFSET_Y := -6.0   # varoituksen alareuna kuormapalkin ylapuolella


func setup(world: TextureRect) -> void:
	pixel_world = world
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # ei koskaan estä klikkauksia maailmaan
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _process(_delta: float) -> void:
	# Botit liikkuvat joka frame -> piirretään uudelleen joka frame. Botteja on
	# vähän (kymmeniä), draw_rect-kutsut ovat halpoja.
	queue_redraw()


func _draw() -> void:
	if pixel_world == null or not is_instance_valid(pixel_world):
		return
	# M5: laskeutumisintron aikana botit ovat piilossa kapselissa -> ei tila-palkkeja.
	if bool(pixel_world.get("_bots_hidden")):
		return
	var bm = pixel_world.get("bot_manager")
	if bm == null or not bm.has_method("get_fleet_stats"):
		return
	var stats: Dictionary = bm.get_fleet_stats()
	for b in stats.get("bots", []):
		if not (b.has("pos") and b.has("cargo_total") and b.has("carry_cap")):
			continue   # vanhempi backend ilman additiivisia kenttiä -> ohita hiljaa
		var pos: Vector2 = b["pos"]
		var screen: Vector2 = pixel_world.grid_to_screen(pos)
		var idle: bool = int(b.get("state", 0)) == BOT_STATE_IDLE
		var alpha: float = IDLE_ALPHA if idle else 1.0
		var cap: int = maxi(int(b["carry_cap"]), 1)
		var frac: float = clampf(float(b["cargo_total"]) / float(cap), 0.0, 1.0)
		var role_col: Color = COL_BAR_MINER if int(b.get("role", 0)) == ROLE_MINER else COL_BAR_HAULER

		var bar_pos := screen + Vector2(-BAR_W * 0.5, BAR_OFFSET_Y)
		draw_rect(Rect2(bar_pos, Vector2(BAR_W, BAR_H)),
			Color(COL_BAR_BG.r, COL_BAR_BG.g, COL_BAR_BG.b, COL_BAR_BG.a * alpha))
		if frac > 0.0:
			draw_rect(Rect2(bar_pos, Vector2(BAR_W * frac, BAR_H)),
				Color(role_col.r, role_col.g, role_col.b, role_col.a * alpha))

		# M3: akkupalkki kuormapalkin alapuolella. Vihreä kun riittää, punainen kun vähissä.
		# Lataus-/odotustilassa alphaa ei himmennetä (tila on merkityksellinen, ei "toimeton").
		if b.has("battery") and b.has("battery_max"):
			var state: int = int(b.get("state", 0))
			var charging: bool = state == BOT_STATE_CHARGING or state == BOT_STATE_SEEK_CHARGE
			var batt_alpha: float = 1.0 if charging else alpha
			var bmax: float = maxf(float(b["battery_max"]), 0.001)
			var bfrac: float = clampf(float(b["battery"]) / bmax, 0.0, 1.0)
			var batt_pos := screen + Vector2(-BAR_W * 0.5, BATT_BAR_OFFSET_Y)
			draw_rect(Rect2(batt_pos, Vector2(BAR_W, BATT_BAR_H)),
				Color(COL_BAR_BG.r, COL_BAR_BG.g, COL_BAR_BG.b, COL_BAR_BG.a * batt_alpha))
			if bfrac > 0.0:
				var bcol: Color = COL_BATT_LOW if bfrac <= BATT_LOW_FRAC else COL_BATT_OK
				draw_rect(Rect2(batt_pos, Vector2(BAR_W * bfrac, BATT_BAR_H)),
					Color(bcol.r, bcol.g, bcol.b, bcol.a * batt_alpha))
			# Lataus-/odotusikoni botin oikealla puolella.
			if charging:
				_draw_charge_icon(screen, COL_CHARGE)
			elif int(b.get("idle_reason", 0)) == IDLE_REASON_WAITING_CHARGER:
				_draw_charge_icon(screen, COL_WAIT)

		# P0-1b: idle-miner jolla ei ole reittia (kaikki designaatiot BLOCKED) -> diegeettinen
		# varoitus TAYDELLA alphalla (himmennys ei kertonut mitaan). Piirretaan vain talle syylle.
		if idle and int(b.get("idle_reason", 0)) == IDLE_REASON_ALL_BLOCKED:
			_draw_blocked_warning(screen)


# M3: pieni lataussalama-ikoni (kolmio) botin oikealla puolella. Väri kertoo tilan
# (keltainen = lataa, amber = odottaa vuoroa).
func _draw_charge_icon(screen: Vector2, col: Color) -> void:
	var o := screen + Vector2(BAR_W * 0.5 + 3.0, -2.0)
	var pts := PackedVector2Array([
		o + Vector2(1.0, -4.0), o + Vector2(-2.0, 1.0), o + Vector2(0.0, 1.0),
		o + Vector2(-1.0, 4.0), o + Vector2(2.0, -1.0), o + Vector2(0.0, -1.0),
	])
	draw_colored_polygon(pts, col)


# Piirtaa pienen "! ei reittiä" -varoituksen botin ylle (P0-1b). Tausta takaa luettavuuden
# tummaakin/kirkasta maastoa vasten; teksti keskitetaan botin ylle.
func _draw_blocked_warning(screen: Vector2) -> void:
	var font := get_theme_default_font()
	if font == null:
		font = ThemeDB.fallback_font
	var tw: float = font.get_string_size(WARN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, WARN_FONT_SIZE).x
	var baseline := screen + Vector2(-tw * 0.5, BAR_OFFSET_Y + WARN_OFFSET_Y)
	# Tausta: teksti istuu baseline-koordinaatilla, joten rect ulottuu baselinen ylapuolelle.
	draw_rect(Rect2(baseline + Vector2(-2.0, -float(WARN_FONT_SIZE)),
		Vector2(tw + 4.0, float(WARN_FONT_SIZE) + 3.0)), COL_WARN_BG)
	draw_string(font, baseline, WARN_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, WARN_FONT_SIZE, COL_WARN)
