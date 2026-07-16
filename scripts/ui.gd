extends PanelContainer
# ═══════════════════════════════════════════════════════════════════════════
# UI 2.0 — kaivosyhtiön johtajan käyttöliittymä (DEMO_PLAN §3.1, kortti B1)
# UI-REDESIGN Vaiheet 1-4 (docs/UI_REDESIGN_PLAN.md):
#   Vaihe 1-2: yhteinen Theme + minimalisoitu HUD ("HUD = vain pisteet").
#   Vaihe 3: ikoni-actionbar + build/bot-trayt (korvaa vanhan TabContainerin).
#   Vaihe 4: diegeettiset kontekstipaneelit (klikkaa base/kone/vyöhyke maailmassa)
#            + bottien tila maailmassa (scripts/ui_bot_status_overlay.gd).
#
# Rakenne (kaikki ohjelmallinen):
#   • YLÄPALKKI (vasen-ylä): raha isolla, $/s — FPS + bottilaskuri piilossa, F3 paljastaa
#   • ACTIONBAR (alakeskellä): 4 ikoninappia — Louhi[V] / Rakenna[B] / Botit[T] / Pyyhi[E]
#   • MINE-RIVI (actionbarin yllä, näkyy vain louhinta aktiivisena): pensseli/laatikko/
#     solu + pensselikoko
#   • BUILD-TRAY (actionbarin yllä, [B] avaa/sulkee): uuni/crusher/hihna/pickup/dump
#   • BOT-TRAY (actionbarin yllä, [T]/TAB avaa/sulkee TAI klikkaa base maailmassa):
#     osta miner/hauler, roolijako, upgrade-lista, "Base hyväksyy" -materiaalitogglet
#   • KONTEKSTIPOPOVER (ilmestyy klikatun kohteen viereen maailmassa): vyöhykkeen
#     materiaalifiltteri + poisto, TAI koneen resepti (input→output + edistymä)
#   • ONBOARDING / TOASTIT / MATERIAALISKANNERI — ennallaan Vaiheesta 1-2
#
# Ulkoasu yhdestä yhteisestä teemasta (scripts/ui_theme.gd: UiTheme). Isot paneelit
# (trayt, popoverit) käyttävät UiTheme.panel_frame_style_box() -9-slice-kehystä kun
# assets/ui/panels/panel_frame.png on saatavilla, muuten StyleBoxFlat-fallback.
#
# DIEGEETTINEN MAAILMAKLIKKAUS: pixel_world.gd emittöi world_object_clicked-signaalin
# _handle_input():ssa VAIN kun mikään työkalu ei ole aktiivinen (ei designaatiota, ei
# rakennustilaa, ei vyöhykesijoitusta) ja klikkaus osuu rekisteröityyn kohteeseen.
# Tarkoituksellinen valinta: silloin klikkaus ohjautuu AINA paneeliin, ei koskaan
# hiekkamaalaukseen — ks. pixel_world.gd:n kommentti kohdassa "elif left_just and not
# bomb_mode..." Materiaali-ikonit (vyöhyke-/base-filtterit) johdetaan MAT_COLORS/
# MAT_NAMES -taulukoista, EI PNG-assetteina (assets/ui/README.md).
#
# RINNAKKAISKEHITYS: bot_manager/logistics-rajapinnat ja pixel_world-kytkennät on jo
# integroitu (lane A/G). Kaikki kutsut on silti guardattu has_method()/has_signal()/
# get():llä — napit joiden backend puuttuu näkyvät harmaina eivätkä kaadu.
# ═══════════════════════════════════════════════════════════════════════════

# Preload (ei class_name-viittaus) — vältetään class-cachen resolvointiviive
# ensimmäisellä ajolla (ks. CLAUDE.md: Godot Testing Gotchas).
const UiThemeRef := preload("res://scripts/ui_theme.gd")
const BotStatusOverlayScript := preload("res://scripts/ui_bot_status_overlay.gd")

# ── Ikonit (assets/ui/icons/, 24×24 px) — piirretään 2× (48px) nearest-filterillä ──
const ICON_TOOL_MINE := preload("res://assets/ui/icons/tool_mine.png")
const ICON_TOOL_BUILD := preload("res://assets/ui/icons/tool_build.png")
const ICON_TOOL_BOTS := preload("res://assets/ui/icons/tool_bots.png")
const ICON_TOOL_ERASE := preload("res://assets/ui/icons/tool_erase.png")
const ICON_DESIG_BRUSH := preload("res://assets/ui/icons/desig_brush.png")
const ICON_DESIG_BOX := preload("res://assets/ui/icons/desig_box.png")
const ICON_DESIG_CELL := preload("res://assets/ui/icons/desig_cell.png")
const ICON_BUILD_FURNACE := preload("res://assets/ui/icons/build_furnace.png")
const ICON_BUILD_CRUSHER := preload("res://assets/ui/icons/build_crusher.png")
const ICON_BUILD_CONVEYOR := preload("res://assets/ui/icons/build_conveyor.png")
const ICON_ZONE_PICKUP := preload("res://assets/ui/icons/zone_pickup.png")
const ICON_ZONE_DUMP := preload("res://assets/ui/icons/zone_dump.png")
const ICON_BOT_MINER := preload("res://assets/ui/icons/bot_miner.png")
const ICON_BOT_HAULER := preload("res://assets/ui/icons/bot_hauler.png")
const ICON_SPEED_PAUSE := preload("res://assets/ui/icons/speed_pause.png")
const ICON_SPEED_1X := preload("res://assets/ui/icons/speed_1x.png")
const ICON_SPEED_2X := preload("res://assets/ui/icons/speed_2x.png")
const ICON_SPEED_3X := preload("res://assets/ui/icons/speed_3x.png")
const ICON_SPEED_4X := preload("res://assets/ui/icons/speed_4x.png")

@onready var pixel_world: TextureRect = get_node("../../PixelWorld")

const MAT_EMPTY := 0
# Roolit (bot.gd Role-enum: MINER=0, HAULER=1)
const ROLE_MINER := 0
const ROLE_HAULER := 1
# Vyöhyketyypit begin_zone_placement()-kutsulle (lane G tulkitsee)
const ZONE_PICKUP := 0
const ZONE_DUMP := 1

# ── Game feel / animaatiot (Vaihe 5 kohta 2) ────────────────────────────────
# Yhteinen ankkuripaikka actionbarin yläpuolella (mine-rivi, build-tray, bot-tray,
# onboarding-vihje) — yksi vakio siroteltujen -68.0-literaalien sijaan.
const TRAY_ANCHOR_OFFSET_BOTTOM := -68.0
const TRAY_ANIM_DURATION := 0.12
const TRAY_SLIDE_OFFSET := 18.0
const POPOVER_ANIM_DURATION := 0.08
const TOAST_FADE_IN_DURATION := 0.15
const TOAST_FADE_OUT_DURATION := 0.25

# Värit — amber-paletti (UiThemeRef.COL_*), EI sinistä
const COL_MONEY := UiThemeRef.COL_MONEY
const COL_BAD := UiThemeRef.COL_BAD
const COL_DIM := UiThemeRef.COL_TEXT_DIM
const COL_ACTIVE := UiThemeRef.COL_ACTIVE
const COL_TEXT := UiThemeRef.COL_TEXT

# ── Yläpalkki (kompakti, vasen-ylä) ─────────────────────────────────────────
var money_label: Label
var income_label: Label
# Pysyvä bottilaskuri (D5): miner/hauler aktiiviset/kaikki rahamittarin alla,
# aina näkyvissä (ei enää vain F3-debugin takana).
var fleet_row: HBoxContainer
var fleet_miner_label: Label
var fleet_hauler_label: Label
var fleet_label: Label            # F3-debug-rivin bottilaskuri (säilyy ennallaan)
var fps_label: Label
var debug_row: HBoxContainer
var _debug_visible: bool = false

# ── Actionbar (alakeskellä, aina näkyvissä) ─────────────────────────────────
var actionbar_panel: PanelContainer
var tool_btn_mine: Button
var tool_btn_build: Button
var tool_btn_bots: Button
var tool_btn_erase: Button

# ── Mine-rivi (näkyy vain kun louhinta aktiivinen) ──────────────────────────
var mine_row_panel: PanelContainer
var desig_mode_buttons: Array[Button] = []
var _desig_tool_mode: int = 0

# ── Peliajan nopeus (oikea-ylä, peilikuva top_bar-sijoittelusta): Tauko/1x/2x/3x/4x ──
var speed_panel: PanelContainer
var speed_buttons: Array[Button] = []
const SPEED_VALUES: Array[float] = [0.0, 1.0, 2.0, 3.0, 4.0]   # Tauko, 1x, 2x, 3x, 4x

# ── Tray-animaatiot (Vaihe 5 kohta 2) ───────────────────────────────────────
var _tray_tweens: Dictionary = {}   # PanelContainer -> Tween (aktiivinen slide+fade)

# ── Build-tray ([B] avaa/sulkee) ────────────────────────────────────────────
var build_tray_panel: PanelContainer
var _build_tray_open: bool = false

# ── Bot-tray ([T]/TAB avaa/sulkee TAI klikkaa base) ─────────────────────────
var bot_tray_panel: PanelContainer
var _bot_tray_open: bool = false
var role_minus_btn: Button
var role_plus_btn: Button
var role_count_label: Label
var bot_list_vbox: VBoxContainer
var _last_fleet_sig: String = ""
var _bot_upgrade_items: Array = []   # [{ "btn": Button, "price": int }]

# ── Kontekstipopover (vyöhyke- tai konepaneeli, ilmestyy maailmakohteen viereen) ──
var _context_popover: PanelContainer = null
var _context_popover_kind: String = ""
var _zone_popover_zid: int = -1
var _zone_popover_toggles: Dictionary = {}
var _zone_popover_active_btn: Button = null
var _popover_just_opened: bool = false   # estää saman klikin sulkemasta juuri avattua popoveria
var _prev_left_ui: bool = false          # oma left-just-seuranta (riippumaton pixel_worldista)

# Konepopoverin live-päivitys (Vaihe 5 kohta 4): rivikohtaiset Label-viitteet + itse
# kone, jotta collected/need-laskurit voi päivittää uudelleenrakentamatta koko paneelia.
var _machine_popover_machine: Object = null
var _machine_popover_rows: Dictionary = {}   # input_mat -> {"label": Label, "need": int}

# Ostettavat/rakennettavat kohteet joiden hinta/varaa-tila päivittyy:
# [{panel(=Button), price_label, cost_fn}]
var _afford_items: Array = []

# ── Bottien tila maailmassa (diegeettinen overlay, Vaihe 4 kohta 10) ───────
var bot_status_overlay: Control

# ── Onboarding ─────────────────────────────────────────────────────────────
var onboarding_panel: PanelContainer
var onboarding_label: Label
var _onboarding_step: int = 0
var _onboarding_done: bool = false
var _onboarding_money_base: int = 0
var _onboarding_bot_base: int = 0
const ONBOARDING_TEXTS: Array[String] = [
	"Paina V ja maalaa alue louhittavaksi",
	"Hauler tuo saaliin baseen — raha kasvaa",
	"Osta kolmas botti kun sinulla on $300",
]

# ── Toast (välitavoitteet) ─────────────────────────────────────────────────
var toast_panel: PanelContainer
var toast_label: Label
var _toast_timer: float = 0.0
var _toast_tween: Tween = null

# ── Materiaaliskanneri ─────────────────────────────────────────────────────
var scanner_panel: PanelContainer
var scanner_label: RichTextLabel
var _scanner_frame: int = 0
const SCANNER_INTERVAL: int = 6
const SCANNER_RADIUS: int = 50

# Päivitysakku raskaammille päivityksille (~5 Hz)
var _ui_accum: float = 0.0

# Materiaalinimet ja -värit skannerille + materiaali-icon-toggleille (ID:t 0–21)
const MAT_NAMES: Dictionary = {
	1: "Hiekka", 2: "Vesi", 3: "Kivi", 4: "Puu", 5: "Tuli", 6: "Öljy",
	7: "Höyry", 8: "Tuhka", 9: "Puu↓", 10: "Lasi", 11: "Multa",
	12: "Rautamalmi", 13: "Kultamalmi", 14: "Rauta", 15: "Kulta",
	16: "Hiili", 18: "Sora", 19: "Pohjakivi", 20: "Kupari", 21: "Harvinaismaa",
}
const MAT_COLORS: Dictionary = {
	1: "#dcc874", 2: "#6699dd", 3: "#8c8c85", 4: "#7a4820", 5: "#ff8020",
	6: "#3a2a1a", 7: "#ccd8e6", 8: "#5a5450", 9: "#7a4820", 10: "#a6e0d6",
	11: "#7a5230", 12: "#8c6b60", 13: "#b8a640", 14: "#adadb8", 15: "#e6c732",
	16: "#2e2b36", 18: "#6b6055", 19: "#2d2830", 20: "#b87340", 21: "#5abfa8",
}

# Materiaalifiltterien (logistiikka: base-hyväksyntä + vyöhykepopoverit) valikoima
const FILTER_MATS: Array = [
	[11, "Multa"], [1, "Hiekka"], [18, "Sora"], [16, "Hiili"],
	[12, "Rautamalmi"], [13, "Kultamalmi"], [20, "Kupari"], [21, "Harv.maa"],
	[14, "Rauta"], [15, "Kulta"], [10, "Lasi"],
]


# ═══════════════════════════════════════════════════════════════════════════
#  RAKENNUS
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	theme = UiThemeRef.build_theme()   # yksi yhteinen teema koko UI:lle (Vaihe 1)
	_register_panel(self)   # yläpalkki hiiri-inputin estoon

	_build_top_bar()
	_build_actionbar()
	_build_mine_row()
	_build_speed_panel()
	_build_build_tray()
	_build_bot_tray()
	_build_scanner_panel()
	_build_toast()
	_build_onboarding()
	_build_bot_status_overlay()
	_connect_world_signals()

	# Lisäpaneelit rekisteröidään estoon vasta kun ne on lisätty (deferred)
	_register_ui_panels.call_deferred()


func _connect_world_signals() -> void:
	# Välitavoite-toastit, demo-loppu ja diegeettinen maailmaklikkaus — vain jos
	# lane G / Vaihe 4 -kytkentä on lisännyt signaalin.
	if pixel_world.has_signal("milestone"):
		pixel_world.milestone.connect(_on_milestone)
	if pixel_world.has_signal("demo_complete"):
		pixel_world.demo_complete.connect(_on_demo_complete)
	if pixel_world.has_signal("world_object_clicked"):
		pixel_world.world_object_clicked.connect(_on_world_object_clicked)


func _register_ui_panels() -> void:
	for panel in [actionbar_panel, mine_row_panel, speed_panel, build_tray_panel, bot_tray_panel, scanner_panel]:
		_register_panel(panel)


# Rekisteröi paneeli pixel_worldin hiiri-inputin estoon.
# Tukee sekä uutta ui_panels-taulukkoa että vanhaa ui_panel-kenttää.
func _register_panel(panel: Control) -> void:
	if pixel_world == null or not is_instance_valid(panel):
		return
	var panels = pixel_world.get("ui_panels")
	if panels != null and panels is Array:
		if not panels.has(panel):
			panels.append(panel)
	else:
		pixel_world.set("ui_panel", panel)


# Poistaa paneelin input-eston listalta (kutsutaan kun dynaaminen popover tuhotaan,
# ettei ui_panels-taulukko kasva loputtomiin vanhentuneilla viitteillä).
func _unregister_panel(panel: Control) -> void:
	if pixel_world == null or not is_instance_valid(panel):
		return
	var panels = pixel_world.get("ui_panels")
	if panels != null and panels is Array:
		panels.erase(panel)


# ── Yläpalkki ──────────────────────────────────────────────────────────────

func _build_top_bar() -> void:
	# Kompakti paneeli vasempaan yläkulmaan — EI enää full-width-palkkia (Vaihe 2).
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	offset_left = 10.0
	offset_top = 10.0

	var style := UiThemeRef.panel_style_box(UiThemeRef.COL_BG_PANEL, UiThemeRef.COL_BORDER_DIM, 1, 10.0)
	add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 0)
	add_child(vbox)

	# Raha isolla, amber
	money_label = Label.new()
	money_label.text = "$0"
	money_label.add_theme_font_size_override("font_size", 26)
	money_label.add_theme_color_override("font_color", COL_MONEY)
	vbox.add_child(money_label)

	# $/s-mittari (piilotetaan jos world.income_per_s puuttuu tai on ~0)
	income_label = Label.new()
	income_label.text = ""
	income_label.visible = false
	income_label.add_theme_font_size_override("font_size", 13)
	income_label.add_theme_color_override("font_color", COL_DIM)
	vbox.add_child(income_label)

	# ── Pysyvä bottilaskuri (D5) — miner N/M + hauler N/M rahamittarin alla ────
	# Aina näkyvissä (toisin kuin alla oleva F3-debug-rivi). Lisätään saman VBoxin
	# lapseksi → container hoitaa asettelun automaattisesti, EI omia ankkureita.
	# (Paneelin lyttäys-gotcha koskee vain uusia set_anchors_preset-paneeleita, ei
	# container-lapsia — siksi tähän ei tarvita grow_horizontal/grow_vertical-säätöä.)
	fleet_row = HBoxContainer.new()
	fleet_row.add_theme_constant_override("separation", 3)
	vbox.add_child(fleet_row)

	fleet_row.add_child(_make_stat_icon(ICON_BOT_MINER, "Miner-botit: aktiiviset / kaikki"))
	fleet_miner_label = Label.new()
	fleet_miner_label.text = "0/0"
	fleet_miner_label.tooltip_text = "Miner-botit: aktiiviset / kaikki"
	fleet_miner_label.add_theme_font_size_override("font_size", 14)
	fleet_miner_label.add_theme_color_override("font_color", COL_TEXT)
	fleet_miner_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fleet_row.add_child(fleet_miner_label)

	# Väli miner- ja hauler-ryhmän väliin
	var fleet_gap := Control.new()
	fleet_gap.custom_minimum_size = Vector2(10.0, 0.0)
	fleet_row.add_child(fleet_gap)

	fleet_row.add_child(_make_stat_icon(ICON_BOT_HAULER, "Hauler-botit: aktiiviset / kaikki"))
	fleet_hauler_label = Label.new()
	fleet_hauler_label.text = "0/0"
	fleet_hauler_label.tooltip_text = "Hauler-botit: aktiiviset / kaikki"
	fleet_hauler_label.add_theme_font_size_override("font_size", 14)
	fleet_hauler_label.add_theme_color_override("font_color", COL_TEXT)
	fleet_hauler_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	fleet_row.add_child(fleet_hauler_label)

	# Debug-rivi: FPS + bottilaskuri — piilossa oletuksena, F3 paljastaa
	debug_row = HBoxContainer.new()
	debug_row.add_theme_constant_override("separation", 10)
	debug_row.visible = _debug_visible
	vbox.add_child(debug_row)

	fleet_label = Label.new()
	fleet_label.text = ""
	fleet_label.add_theme_font_size_override("font_size", 13)
	fleet_label.add_theme_color_override("font_color", COL_TEXT)
	debug_row.add_child(fleet_label)

	fps_label = Label.new()
	fps_label.text = "FPS 0"
	fps_label.add_theme_font_size_override("font_size", 12)
	fps_label.add_theme_color_override("font_color", COL_DIM)
	debug_row.add_child(fps_label)


# ═══════════════════════════════════════════════════════════════════════════
#  ACTIONBAR (Vaihe 3, kohta 1) — 4 ikoninappia alakeskellä
# ═══════════════════════════════════════════════════════════════════════════

func _build_actionbar() -> void:
	actionbar_panel = PanelContainer.new()
	actionbar_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	actionbar_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	actionbar_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	actionbar_panel.offset_bottom = -12.0
	actionbar_panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	actionbar_panel.add_child(hb)

	tool_btn_mine = _make_tool_button(ICON_TOOL_MINE, "Louhi [V]\nMerkkaa alue louhittavaksi", 48.0)
	tool_btn_mine.pressed.connect(_on_tool_mine_pressed)
	hb.add_child(tool_btn_mine)

	tool_btn_build = _make_tool_button(ICON_TOOL_BUILD, "Rakenna [B]\nAvaa rakennus- ja vyöhykevalikon", 48.0)
	tool_btn_build.pressed.connect(_on_tool_build_pressed)
	hb.add_child(tool_btn_build)

	# HUOM: tooltip sanoo [TAB] eikä [T] — kirjain T on jo pixel_world.gd:n legacy-
	# kaivaustyökalun sädekierrolla (KEY_T, ks. _input()), eikä sitä voi vapauttaa
	# rikkomatta toimivaa mekaniikkaa. TAB on ainoa toimiva pikanäppäin botti-traylle.
	tool_btn_bots = _make_tool_button(ICON_TOOL_BOTS, "Botit [TAB]\nOsta ja hallitse botteja", 48.0)
	tool_btn_bots.pressed.connect(_on_tool_bots_pressed)
	hb.add_child(tool_btn_bots)

	tool_btn_erase = _make_tool_button(ICON_TOOL_ERASE, "Pyyhi [E]\nPoista maalattua materiaalia", 48.0)
	tool_btn_erase.pressed.connect(_on_tool_erase_pressed)
	hb.add_child(tool_btn_erase)

	get_parent().add_child.call_deferred(actionbar_panel)


func _on_tool_mine_pressed() -> void:
	_close_build_tray()
	_close_bot_tray()
	_close_context_popover()
	_toggle_designation()


func _on_tool_build_pressed() -> void:
	_toggle_build_tray()


func _on_tool_bots_pressed() -> void:
	_toggle_bot_tray()


func _on_tool_erase_pressed() -> void:
	_close_build_tray()
	_close_bot_tray()
	_close_context_popover()
	_set_designation_mode(false)
	pixel_world.build_mode = pixel_world.BUILD_NONE
	pixel_world.current_material = MAT_EMPTY   # sama efekti kuin E-näppäin


func _toggle_designation() -> void:
	var on := not _get_designation_mode()
	_set_designation_mode(on)
	if on:
		pixel_world.build_mode = 0  # BUILD_NONE


# ═══════════════════════════════════════════════════════════════════════════
#  MINE-RIVI (Vaihe 3, kohta 2) — näkyy vain kun louhinta aktiivinen
# ═══════════════════════════════════════════════════════════════════════════

func _build_mine_row() -> void:
	mine_row_panel = PanelContainer.new()
	mine_row_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	mine_row_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	mine_row_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	mine_row_panel.offset_bottom = TRAY_ANCHOR_OFFSET_BOTTOM   # actionbarin yläpuolelle
	mine_row_panel.visible = false
	mine_row_panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	mine_row_panel.add_child(hb)

	var mode_icons: Array[Texture2D] = [ICON_DESIG_BRUSH, ICON_DESIG_BOX, ICON_DESIG_CELL]
	var mode_tips: Array[String] = [
		"Pensseli\nPidä pohjassa ja maalaa säteellä",
		"Laatikko\nVedä suorakulmio",
		"Solu\nKlikkaa yksi solu kerrallaan",
	]
	desig_mode_buttons.clear()
	for i in mode_icons.size():
		var b := _make_tool_button(mode_icons[i], mode_tips[i], 36.0)
		b.pressed.connect(_set_desig_mode.bind(i))
		hb.add_child(b)
		desig_mode_buttons.append(b)

	get_parent().add_child.call_deferred(mine_row_panel)


func _set_desig_mode(mode: int) -> void:
	_desig_tool_mode = mode
	# Kytke pixel_worldin työkalumoodi jos backend on (lane G); muuten vain UI-korostus
	if pixel_world.has_method("set_designation_tool_mode"):
		pixel_world.set_designation_tool_mode(mode)
	# Työkalun valinta aktivoi louhintatilan
	_set_designation_mode(true)
	pixel_world.build_mode = 0  # BUILD_NONE


# ═══════════════════════════════════════════════════════════════════════════
#  PELIAJAN NOPEUS (oikea-ylä) — Tauko/1x/2x/3x/4x, peilikuva top_bar-sijoittelusta
# ═══════════════════════════════════════════════════════════════════════════

func _build_speed_panel() -> void:
	speed_panel = PanelContainer.new()
	speed_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	speed_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	speed_panel.offset_right = -10.0
	speed_panel.offset_top = 10.0
	speed_panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	speed_panel.add_child(hb)

	var icons: Array[Texture2D] = [ICON_SPEED_PAUSE, ICON_SPEED_1X, ICON_SPEED_2X, ICON_SPEED_3X, ICON_SPEED_4X]
	var tips: Array[String] = ["Tauko", "1x", "2x", "3x", "4x"]
	speed_buttons.clear()
	for i in icons.size():
		var b := _make_tool_button(icons[i], tips[i], 36.0)
		b.pressed.connect(_on_speed_pressed.bind(SPEED_VALUES[i]))
		hb.add_child(b)
		speed_buttons.append(b)

	get_parent().add_child.call_deferred(speed_panel)


func _on_speed_pressed(value: float) -> void:
	pixel_world.sim_speed = value


# ═══════════════════════════════════════════════════════════════════════════
#  BUILD-TRAY (Vaihe 3, kohta 3) — [B] avaa/sulkee
# ═══════════════════════════════════════════════════════════════════════════

func _build_build_tray() -> void:
	build_tray_panel = PanelContainer.new()
	build_tray_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	build_tray_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	build_tray_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	build_tray_panel.offset_bottom = TRAY_ANCHOR_OFFSET_BOTTOM
	build_tray_panel.visible = false
	build_tray_panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	build_tray_panel.add_child(hb)

	_add_tray_item(hb, ICON_BUILD_FURNACE, "Sulatusuuni\nHiekka→lasi, malmi→harkko",
		func() -> int: return _building_cost("furnace"),
		func() -> void: _buy_building(pixel_world.BUILD_FURNACE, _building_cost("furnace")))
	_add_tray_item(hb, ICON_BUILD_CRUSHER, "Murskain\nKivi/sora→hiekka",
		func() -> int: return _building_cost("crusher"),
		func() -> void: _buy_building(pixel_world.BUILD_CRUSHER, _building_cost("crusher")))
	_add_tray_item(hb, ICON_BUILD_CONVEYOR, "Kuljetushihna\nSiirtää materiaalia ilman bottia",
		func() -> int: return _building_cost("conveyor"),
		func() -> void: _buy_building(pixel_world.BUILD_CONVEYOR_START, _building_cost("conveyor")))
	_add_tray_item(hb, ICON_ZONE_PICKUP, "Nouto-vyöhyke\nHaulerit hakevat täältä",
		func() -> int: return _zone_cost(80),
		func() -> void: _place_zone(ZONE_PICKUP, 80))
	_add_tray_item(hb, ICON_ZONE_DUMP, "Pudotus-vyöhyke\nHaulerit purkavat tänne",
		func() -> int: return _zone_cost(60),
		func() -> void: _place_zone(ZONE_DUMP, 60))

	get_parent().add_child.call_deferred(build_tray_panel)


func _toggle_build_tray() -> void:
	if _build_tray_open:
		_close_build_tray()
	else:
		_close_bot_tray()
		_close_context_popover()
		_set_designation_mode(false)
		_animate_tray_open(build_tray_panel)
		_build_tray_open = true


func _close_build_tray() -> void:
	_animate_tray_close(build_tray_panel)
	_build_tray_open = false


# Sulkee trayn automaattisesti heti kun sijoitustila alkaa (rakennus TAI vyöhyke) —
# UI_REDESIGN_PLAN.md Vaihe 3 kohta 3: "Tray sulkeutuu kun sijoitustila alkaa tai [B]/Esc."
func _update_build_tray_visibility() -> void:
	if not _build_tray_open:
		return
	if pixel_world.build_mode != pixel_world.BUILD_NONE or pixel_world.zone_placement_type >= 0:
		_close_build_tray()


# ═══════════════════════════════════════════════════════════════════════════
#  BOT-TRAY (Vaihe 3 kohta 4 + Vaihe 4 kohta 8) — [T]/TAB TAI klikkaa base
# ═══════════════════════════════════════════════════════════════════════════

func _build_bot_tray() -> void:
	bot_tray_panel = PanelContainer.new()
	bot_tray_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bot_tray_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bot_tray_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bot_tray_panel.offset_bottom = TRAY_ANCHOR_OFFSET_BOTTOM
	bot_tray_panel.visible = false
	bot_tray_panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	bot_tray_panel.add_child(vb)

	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	vb.add_child(buy_row)
	_add_tray_item(buy_row, ICON_BOT_MINER, "Osta Miner\nLouhii merkatut alueet",
		_bot_price, _buy_bot.bind(ROLE_MINER))
	_add_tray_item(buy_row, ICON_BOT_HAULER, "Osta Hauler\nKuljettaa saaliin baseen",
		_bot_price, _buy_bot.bind(ROLE_HAULER))

	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 6)
	vb.add_child(role_row)
	role_row.add_child(_label("Minereitä:", 12))
	role_minus_btn = _make_btn("−", 16)
	role_minus_btn.custom_minimum_size = Vector2(26.0, 0.0)
	role_minus_btn.pressed.connect(_on_role_change.bind(-1))
	role_row.add_child(role_minus_btn)
	role_count_label = _label("—", 14)
	role_count_label.custom_minimum_size = Vector2(24.0, 0.0)
	role_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_row.add_child(role_count_label)
	role_plus_btn = _make_btn("+", 16)
	role_plus_btn.custom_minimum_size = Vector2(26.0, 0.0)
	role_plus_btn.pressed.connect(_on_role_change.bind(1))
	role_row.add_child(role_plus_btn)

	vb.add_child(_label("Botit & upgradet", 11, COL_DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(280.0, 100.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	bot_list_vbox = VBoxContainer.new()
	bot_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_list_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(bot_list_vbox)
	vb.add_child(scroll)

	get_parent().add_child.call_deferred(bot_tray_panel)


func _toggle_bot_tray() -> void:
	if _bot_tray_open:
		_close_bot_tray()
	else:
		_open_bot_tray()


# Avaa bot-trayn. Käytetään sekä [T]-napista/-näppäimestä että basen maailmaklikkauksesta
# (Vaihe 4 kohta 8: "sama paneeli kuin [T]"). YKSINKERTAISTUS: paneeli pysyy aina
# ankkuroituna actionbarin yläpuolelle riippumatta avaustavasta — ei sijoiteta dynaamisesti
# basen viereen, koska Control-ankkurit ja vapaa position-asetus olisivat ristiriidassa
# (ks. raportti). Looginen ja johdonmukainen: sama nappi tekee saman asian kummastakin
# lähteestä.
func _open_bot_tray() -> void:
	_close_build_tray()
	_close_context_popover()
	_set_designation_mode(false)   # sulkee mine-rivin (sama ankkuripaikka, ei saa jäädä päällekkäin)
	_animate_tray_open(bot_tray_panel)
	_bot_tray_open = true
	_last_fleet_sig = ""   # pakota bottilistan uudelleenrakennus heti avattaessa
	_maybe_rebuild_bot_list()


func _close_bot_tray() -> void:
	_animate_tray_close(bot_tray_panel)
	_bot_tray_open = false


# ═══════════════════════════════════════════════════════════════════════════
#  TRAY-ANIMAATIOT (Vaihe 5 kohta 2) — lyhyt slide-ylös + fade auki, käänteinen kiinni
# ═══════════════════════════════════════════════════════════════════════════

# Avaa paneelin heti (visible=true HETI, ei animaation lopussa) jotta
# _register_panel-pohjainen input-esto (pixel_world.gd: ui_panels-rektitarkistus)
# pysyy voimassa koko animaation ajan — ainoastaan modulate-alpha ja offset_bottom
# animoituvat, paneelin lopullinen koko/sijainti on jo asetettu.
func _animate_tray_open(panel: PanelContainer) -> void:
	if panel == null:
		return
	_kill_tray_tween(panel)
	panel.visible = true
	panel.modulate.a = 0.0
	panel.offset_bottom = TRAY_ANCHOR_OFFSET_BOTTOM + TRAY_SLIDE_OFFSET
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 1.0, TRAY_ANIM_DURATION)
	tw.tween_property(panel, "offset_bottom", TRAY_ANCHOR_OFFSET_BOTTOM, TRAY_ANIM_DURATION)
	_tray_tweens[panel] = tw


# Häivyttää + liu'uttaa paneelin pois ja piilottaa (visible=false) vasta kun animaatio
# on valmis. Ei-op jos paneeli on jo piilossa (esim. _close_build_tray() kutsuttuna
# monesta paikasta varmuuden vuoksi).
func _animate_tray_close(panel: PanelContainer) -> void:
	if panel == null or not panel.visible:
		return
	_kill_tray_tween(panel)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_IN)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 0.0, TRAY_ANIM_DURATION)
	tw.tween_property(panel, "offset_bottom", TRAY_ANCHOR_OFFSET_BOTTOM + TRAY_SLIDE_OFFSET, TRAY_ANIM_DURATION)
	tw.chain().tween_callback(func() -> void:
		panel.visible = false
		panel.offset_bottom = TRAY_ANCHOR_OFFSET_BOTTOM
		panel.modulate.a = 1.0)
	_tray_tweens[panel] = tw


func _kill_tray_tween(panel: PanelContainer) -> void:
	if _tray_tweens.has(panel):
		var tw: Tween = _tray_tweens[panel]
		if tw != null and tw.is_valid():
			tw.kill()
		_tray_tweens.erase(panel)


# ═══════════════════════════════════════════════════════════════════════════
#  MATERIAALI-ICON-TOGGLET (Vaihe 4 kohta 7) — korvaa checkbox-ruudukon.
#  Väri MAT_COLORS-taulukosta, EI PNG-assetteja (assets/ui/README.md).
#  Uudelleenkäytetään sekä "Base hyväksyy" -rivillä (bot-tray) että
#  vyöhykepopoverin filtteririvillä.
# ═══════════════════════════════════════════════════════════════════════════

# Rakentaa rivin materiaali-toggle-nappeja. initial_mask: 0 = kaikki päällä (ei rajausta,
# sama semantiikka kuin Logistics.mask_accepts). Palauttaa mat_id -> Button; kutsuja
# kytkee toggled-signaalin itse _wire_mat_toggle_row():lla (kun tietää mihin kohteeseen
# muutos kohdistuu).
func _build_mat_toggle_row(parent: Control, initial_mask: int) -> Dictionary:
	var toggles: Dictionary = {}
	for m in FILTER_MATS:
		var mat_id := int(m[0])
		var accepted: bool = initial_mask == 0 or (initial_mask & (1 << mat_id)) != 0
		var btn := _make_mat_toggle(mat_id, accepted)
		parent.add_child(btn)
		toggles[mat_id] = btn
	return toggles


func _wire_mat_toggle_row(toggles: Dictionary, on_change: Callable) -> void:
	for mat_id in toggles:
		var btn: Button = toggles[mat_id]
		btn.toggled.connect(func(_v: bool) -> void: on_change.call())


func _make_mat_toggle(mat_id: int, initial: bool) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.button_pressed = initial
	b.custom_minimum_size = Vector2(18.0, 18.0)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = String(MAT_NAMES.get(mat_id, "?"))
	var col := Color(String(MAT_COLORS.get(mat_id, "#888888")))
	var on_sb := UiThemeRef.panel_style_box(col, UiThemeRef.COL_BORDER, 1, 1.0)
	var off_sb := UiThemeRef.panel_style_box(col.darkened(0.6), UiThemeRef.COL_BORDER_DIM, 1, 1.0)
	b.add_theme_stylebox_override("normal", off_sb)
	b.add_theme_stylebox_override("hover", off_sb)
	b.add_theme_stylebox_override("pressed", on_sb)
	b.add_theme_stylebox_override("hover_pressed", on_sb)
	b.add_theme_stylebox_override("focus", off_sb)
	return b


# Ei-interaktiivinen materiaalivärineliö (koneen resepti-ikonina, ks. _open_machine_popover).
func _mat_swatch(mat_id: int) -> Control:
	var r := ColorRect.new()
	r.custom_minimum_size = Vector2(16.0, 16.0)
	r.color = Color(String(MAT_COLORS.get(mat_id, "#888888")))
	r.tooltip_text = String(MAT_NAMES.get(mat_id, "?"))
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


# ═══════════════════════════════════════════════════════════════════════════
#  DIEGEETTINEN MAAILMAKLIKKAUS + KONTEKSTIPOPOVERIT (Vaihe 4, kohdat 7-9)
# ═══════════════════════════════════════════════════════════════════════════

func _on_world_object_clicked(kind: String, data: Dictionary) -> void:
	match kind:
		"base":
			_open_bot_tray()
		"furnace", "crusher":
			_open_machine_popover(kind, data.get("obj"))
		"zone":
			_open_zone_popover(data.get("zone", {}))


# Vyöhykkeen (pickup/dump) materiaalifiltteri + poisto. Korvaa vanhan checkbox-
# ruudukon ja vyöhykelistan kokonaan — vyöhykettä muokataan klikkaamalla sitä maailmassa.
func _open_zone_popover(zone: Dictionary) -> void:
	if zone.is_empty():
		return
	_close_context_popover()
	_close_build_tray()
	_close_bot_tray()

	var zid := int(zone.get("id", -1))
	var ztype := String(zone.get("type", "?"))
	var mask := int(zone.get("filter_mask", 0))
	var rect: Rect2i = zone.get("rect", Rect2i())
	var is_base_dropoff := bool(zone.get("is_base_dropoff", false))

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)

	if is_base_dropoff:
		vb.add_child(_label("Base-pudotus", 12, COL_TEXT))
		vb.add_child(_label("Pudottaa baseen -> rahaksi", 10, COL_DIM))
	else:
		vb.add_child(_label("%s #%d" % [ztype.capitalize(), zid], 12, COL_TEXT))

	# Aktiivinen/Pois päältä -kytkin (materiaalifiltterin YLÄPUOLELLE). Pois päältä ollessa
	# vyöhyke ei kelpaa choose_dumpin/pickup_zonesin kandidaatiksi riippumatta filtteristä.
	var active := bool(zone.get("active", true))
	var active_btn := _make_btn(_zone_active_label(active), 11)
	active_btn.toggle_mode = true
	active_btn.button_pressed = active
	active_btn.pressed.connect(_on_zone_popover_active_toggled)
	vb.add_child(active_btn)
	_zone_popover_active_btn = active_btn

	vb.add_child(_label("Hyväksytyt materiaalit:", 10, COL_DIM))

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 3)
	vb.add_child(row)
	var toggles := _build_mat_toggle_row(row, mask)
	_zone_popover_toggles = toggles
	_zone_popover_zid = zid
	_wire_mat_toggle_row(toggles, _on_zone_popover_filter_changed)

	var remove_btn := _make_btn("Poista vyöhyke", 11)
	remove_btn.pressed.connect(_on_zone_popover_remove)
	vb.add_child(remove_btn)

	get_parent().add_child(panel)
	_context_popover = panel
	_context_popover_kind = "zone"
	_register_panel(panel)
	var anchor: Vector2 = pixel_world.grid_to_screen(
		Vector2(float(rect.position.x) + float(rect.size.x) * 0.5, float(rect.position.y)))
	_position_popover(panel, anchor)
	_animate_popover_in(panel)
	_popover_just_opened = true


func _on_zone_popover_filter_changed() -> void:
	var lg := _logistics()
	if lg == null or _zone_popover_zid < 0 or not lg.has_method("set_zone_filter"):
		return
	lg.set_zone_filter(_zone_popover_zid, _filter_mask_from(_zone_popover_toggles))


# Aktiivinen/Pois päältä -kytkin: filter_mask säilyy koskemattomana, vain active-lippu vaihtuu.
func _on_zone_popover_active_toggled() -> void:
	var lg := _logistics()
	var btn := _zone_popover_active_btn
	if lg == null or _zone_popover_zid < 0 or btn == null or not is_instance_valid(btn):
		return
	if not lg.has_method("set_zone_active"):
		return
	var new_active := btn.button_pressed
	lg.set_zone_active(_zone_popover_zid, new_active)
	btn.text = _zone_active_label(new_active)


func _zone_active_label(active: bool) -> String:
	return "Aktiivinen: KYLLÄ" if active else "Aktiivinen: EI"


func _on_zone_popover_remove() -> void:
	var lg := _logistics()
	if lg != null and lg.has_method("remove_zone") and _zone_popover_zid >= 0:
		lg.remove_zone(_zone_popover_zid)
	_close_context_popover()


# Koneen (furnace/crusher) resepti-popover: input→output-materiaalit väripaletista +
# kerätty/tarvittu-edistymä. Koneilla ON queryttävä rekisteri (pixel_world.furnaces/
# crushers, grid_pos + RECIPES-const) — ei tarvitse pikseliskannausta.
func _open_machine_popover(kind: String, machine: Variant) -> void:
	if machine == null or not is_instance_valid(machine):
		return
	_close_context_popover()
	_close_build_tray()
	_close_bot_tray()

	var w: int
	var h: int
	if kind == "furnace":
		w = machine.FURNACE_W
		h = machine.FURNACE_H
	else:
		w = machine.CRUSHER_W
		h = machine.CRUSHER_H

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	panel.add_child(vb)
	vb.add_child(_label(kind.capitalize(), 13, COL_TEXT))

	var recipes: Dictionary = machine.RECIPES
	var collected: Dictionary = machine.collected
	_machine_popover_rows = {}
	for input_mat: int in recipes.keys():
		var recipe: Dictionary = recipes[input_mat]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		vb.add_child(row)
		row.add_child(_mat_swatch(input_mat))
		row.add_child(_label("→", 12, COL_DIM))
		row.add_child(_mat_swatch(int(recipe["output"])))
		var have: int = int(collected.get(input_mat, 0))
		var need: int = int(recipe["count"])
		var progress_lbl := _label("%d/%d" % [have, need], 11, COL_DIM)
		row.add_child(progress_lbl)
		_machine_popover_rows[input_mat] = {"label": progress_lbl, "need": need}

	get_parent().add_child(panel)
	_context_popover = panel
	_context_popover_kind = kind
	_machine_popover_machine = machine   # Vaihe 5 kohta 4: live-päivitystä varten (ks. _update_machine_popover)
	_register_panel(panel)
	var anchor: Vector2 = pixel_world.grid_to_screen(
		Vector2(machine.grid_pos.x + float(w) * 0.5, float(machine.grid_pos.y)))
	_position_popover(panel, anchor)
	_animate_popover_in(panel)
	_popover_just_opened = true


# Vaihe 5 kohta 4: päivittää auki olevan konepopoverin kerätty/tarvittu-laskurit
# (~2 Hz, kutsutaan _process():n olemassa olevasta ~5 Hz-akusta — riittää ja ylittää
# pyydetyn taajuuden). Ei rakenna paneelia uudelleen, vain Label.text per rivi.
# Read-only: lukee vain machine.collected, ei koske pelilogiikkaan.
func _update_machine_popover() -> void:
	if _machine_popover_machine == null or not is_instance_valid(_machine_popover_machine):
		return
	if _context_popover == null or not is_instance_valid(_context_popover):
		return
	var collected: Dictionary = _machine_popover_machine.collected
	for input_mat in _machine_popover_rows:
		var entry: Dictionary = _machine_popover_rows[input_mat]
		var lbl: Label = entry["label"]
		if not is_instance_valid(lbl):
			continue
		var have: int = int(collected.get(input_mat, 0))
		lbl.text = "%d/%d" % [have, int(entry["need"])]


# Sijoittaa popoverin ankkurin yläpuolelle (keskitettynä x-akselilla). Tarkka koko ei
# ole vielä tiedossa ensimmäisellä framella (layout deferred) — _clamp_context_popover()
# korjaa asemaa joka frame kunnes koko on asettunut.
func _position_popover(panel: Control, anchor_screen: Vector2) -> void:
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	var est := panel.get_combined_minimum_size()
	panel.position = anchor_screen - Vector2(est.x * 0.5, est.y + 14.0)


# Nopea fade+scale-in (Vaihe 5 kohta 2, ~0.08 s). Skaalataan vain visuaalisesti
# (Control.scale/pivot_offset) — panel.position/size (siis _register_panel-eston
# käyttämä get_global_rect()) ei muutu, joten input-esto kattaa koko lopullisen
# alueen jo ensimmäisestä framesta lähtien vaikka paneeli näyttää vielä pieneltä.
func _animate_popover_in(panel: Control) -> void:
	var est := panel.get_combined_minimum_size()
	panel.pivot_offset = est * 0.5
	panel.modulate.a = 0.0
	panel.scale = Vector2(0.9, 0.9)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.set_ease(Tween.EASE_OUT)
	tw.set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(panel, "modulate:a", 1.0, POPOVER_ANIM_DURATION)
	tw.tween_property(panel, "scale", Vector2.ONE, POPOVER_ANIM_DURATION)


func _close_context_popover() -> void:
	if _context_popover != null and is_instance_valid(_context_popover):
		_unregister_panel(_context_popover)
		_context_popover.queue_free()
	_context_popover = null
	_context_popover_kind = ""
	_zone_popover_zid = -1
	_zone_popover_toggles = {}
	_zone_popover_active_btn = null
	_machine_popover_machine = null
	_machine_popover_rows = {}


# Pitää popoverin ruudun sisällä (1664×960-ikkuna, mutta lasketaan aina oikeasta
# viewport-koosta). Ajetaan joka frame kun popover on auki — halpa (yksi rect-vertailu).
func _clamp_context_popover() -> void:
	if _context_popover == null or not is_instance_valid(_context_popover):
		return
	var sz := _context_popover.size
	var vp := get_viewport_rect().size
	var pos := _context_popover.position
	pos.x = clampf(pos.x, 4.0, maxf(4.0, vp.x - sz.x - 4.0))
	pos.y = clampf(pos.y, 4.0, maxf(4.0, vp.y - sz.y - 4.0))
	_context_popover.position = pos


# Sulkee popoverin kun klikataan sen ulkopuolelle (Vaihe 4 kohta 7: "sulkeutuu
# klikkauksesta muualle / Esc"). Oma left-just-seuranta koska pixel_world.gd:n oma
# klikkauskäsittely ei tiedä UI:n popover-tilasta. _popover_just_opened-lippu estää
# saman klikin (joka avasi popoverin) sulkemasta sitä heti samalla framella.
func _handle_popover_outside_click() -> void:
	var left := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var left_just := left and not _prev_left_ui
	_prev_left_ui = left
	if _popover_just_opened:
		_popover_just_opened = false
		return
	if not left_just:
		return
	if _context_popover == null or not is_instance_valid(_context_popover):
		return
	var mp := get_viewport().get_mouse_position()
	if not _context_popover.get_global_rect().has_point(mp):
		_close_context_popover()


# ═══════════════════════════════════════════════════════════════════════════
#  TRAY-KOHTEET (ikoni + hinta allekkain, himmenee ilman varaa)
# ═══════════════════════════════════════════════════════════════════════════

func _add_tray_item(parent: Control, icon: Texture2D, tooltip: String,
		cost_fn: Callable, on_click: Callable) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	parent.add_child(vb)

	var btn := _make_tool_button(icon, tooltip, 48.0)
	btn.pressed.connect(on_click)
	vb.add_child(btn)

	var price_lbl := Label.new()
	price_lbl.text = ""
	price_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", COL_MONEY)
	vb.add_child(price_lbl)

	_afford_items.append({ "panel": btn, "price_label": price_lbl, "cost_fn": cost_fn })


func _update_afford() -> void:
	for it in _afford_items:
		var c: int = int(it["cost_fn"].call())
		var pl: Label = it["price_label"]
		var panel: Control = it["panel"]
		if c < 0:
			# Backend puuttuu -> harmaa, ei hintaa
			pl.text = "—"
			pl.add_theme_color_override("font_color", COL_DIM)
			panel.modulate = Color(0.55, 0.55, 0.6)
		else:
			pl.text = "$%d" % c
			if _can_afford(c):
				pl.add_theme_color_override("font_color", COL_MONEY)
				panel.modulate = Color.WHITE
			else:
				pl.add_theme_color_override("font_color", COL_BAD)
				panel.modulate = Color(0.7, 0.7, 0.72)


# ═══════════════════════════════════════════════════════════════════════════
#  OSTOLOGIIKKA (kaikki guardattu — toimii myös baseline-koodia vasten)
# ═══════════════════════════════════════════════════════════════════════════

func _bm() -> Object:
	if pixel_world == null:
		return null
	return pixel_world.get("bot_manager")


func _logistics() -> Object:
	if pixel_world == null:
		return null
	return pixel_world.get("logistics")


func _can_afford(cost: int) -> bool:
	if pixel_world == null:
		return false
	if bool(pixel_world.infinite_money):
		return true
	return int(pixel_world.money) >= cost


# Botin hinta next_bot_price():stä; -1 jos backend puuttuu (nappi harmaana)
func _bot_price() -> int:
	var bm := _bm()
	if bm != null and bm.has_method("next_bot_price"):
		return int(bm.next_bot_price())
	return -1


func _buy_bot(role: int) -> void:
	var bm := _bm()
	if bm == null or not bm.has_method("buy_bot"):
		return
	var price := _bot_price()
	if price < 0 or not _can_afford(price):
		return
	bm.buy_bot(role)


func _building_cost(key: String) -> int:
	match key:
		"furnace": return 150
		"crusher": return 120
		"conveyor": return 50
	return 0


func _buy_building(build_const: int, cost: int) -> void:
	if not _can_afford(cost):
		return
	# Lane G: try_buy_building tekee can_afford + money -=; peruutus palauttaa rahan.
	if pixel_world.has_method("try_buy_building"):
		if not pixel_world.try_buy_building(build_const):
			return
	_set_designation_mode(false)
	pixel_world.build_mode = build_const
	pixel_world.block_paint = true


func _on_role_change(delta_miners: int) -> void:
	var bm := _bm()
	if bm == null or not (bm.has_method("get_fleet_stats") and bm.has_method("set_role")):
		return
	var stats: Dictionary = bm.get_fleet_stats()
	var bots: Array = stats.get("bots", [])
	# +1: muunna hauler mineriksi; -1: muunna miner haulerkiksi
	var from_role := ROLE_HAULER if delta_miners > 0 else ROLE_MINER
	var to_role := ROLE_MINER if delta_miners > 0 else ROLE_HAULER
	for b in bots:
		if int(b.get("role", 0)) == from_role:
			bm.set_role(int(b.get("id", 0)), to_role)
			return


# ── Logistiikka ────────────────────────────────────────────────────────────

# Pickup/dump-vyöhykkeen hinta; -1 jos logistiikka tai sijoitushook puuttuu
func _zone_cost(base_cost: int) -> int:
	if _logistics() == null:
		return -1
	if not pixel_world.has_method("begin_zone_placement"):
		return -1
	return base_cost


func _place_zone(zone_type: int, cost: int) -> void:
	if _zone_cost(cost) < 0 or not _can_afford(cost):
		return
	_set_designation_mode(false)
	pixel_world.begin_zone_placement(zone_type)


func _filter_mask_from(checks: Dictionary) -> int:
	var mask := 0
	for mat_id in checks:
		if checks[mat_id].button_pressed:
			mask |= (1 << int(mat_id))
	return mask


# ═══════════════════════════════════════════════════════════════════════════
#  BOTTILISTA (Mk-upgradet)
# ═══════════════════════════════════════════════════════════════════════════

func _maybe_rebuild_bot_list() -> void:
	if bot_list_vbox == null:
		return
	var bm := _bm()
	var sig := _fleet_signature(bm)
	if sig != _last_fleet_sig:
		_last_fleet_sig = sig
		_rebuild_bot_list(bm)
	# Päivitä upgrade-nappien varaa-tila (raha muuttuu jatkuvasti)
	for it in _bot_upgrade_items:
		it["btn"].disabled = not _can_afford(int(it["price"]))


func _rebuild_bot_list(bm: Object) -> void:
	_clear_children(bot_list_vbox)
	_bot_upgrade_items.clear()

	if bm == null or not bm.has_method("get_fleet_stats"):
		bot_list_vbox.add_child(_label("Bottihallinta ei saatavilla (odottaa lane A)", 11, COL_DIM))
		return

	var stats: Dictionary = bm.get_fleet_stats()
	var bots: Array = stats.get("bots", [])
	if bots.is_empty():
		bot_list_vbox.add_child(_label("Ei botteja", 11, COL_DIM))
		return

	for b in bots:
		var id := int(b.get("id", 0))
		var role := int(b.get("role", 0))
		var tier := int(b.get("tier", 0))
		var role_str := "Miner" if role == ROLE_MINER else "Hauler"

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var info := _label("#%d  %s  Mk%d" % [id, role_str, tier + 1], 12)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)

		var price := 0
		if bm.has_method("upgrade_price"):
			price = int(bm.upgrade_price(id))
		if price > 0 and bm.has_method("upgrade_bot"):
			var ub := _make_btn("Mk%d  $%d" % [tier + 2, price], 11)
			ub.pressed.connect(func() -> void:
				if _can_afford(price):
					bm.upgrade_bot(id))
			row.add_child(ub)
			_bot_upgrade_items.append({ "btn": ub, "price": price })
		else:
			row.add_child(_label("Max", 11, COL_DIM))

		bot_list_vbox.add_child(row)


func _fleet_signature(bm: Object) -> String:
	if bm == null:
		return "none"
	if bm.has_method("get_fleet_stats"):
		var stats: Dictionary = bm.get_fleet_stats()
		var parts := PackedStringArray()
		for b in stats.get("bots", []):
			parts.append("%d:%d:%d" % [int(b.get("id", 0)), int(b.get("role", 0)), int(b.get("tier", 0))])
		return "|".join(parts)
	var arr = bm.get("bots")
	return "n%d" % (arr.size() if arr != null else 0)


# ═══════════════════════════════════════════════════════════════════════════
#  ONBOARDING
# ═══════════════════════════════════════════════════════════════════════════

func _build_onboarding() -> void:
	# Vaihe 5 kohta 3: pieni diegeettinen vihjerivi actionbarin YLÄPUOLELLE — ei enää
	# iso keskuslaatikko. Sama ankkuripaikka kuin mine-rivi/trayt (TRAY_ANCHOR_
	# OFFSET_BOTTOM); _update_onboarding() piilottaa vihjeen automaattisesti kun
	# joku niistä on jo auki samalla paikalla (ks. row_busy).
	onboarding_panel = PanelContainer.new()
	onboarding_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	onboarding_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	onboarding_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	onboarding_panel.offset_bottom = TRAY_ANCHOR_OFFSET_BOTTOM
	onboarding_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	onboarding_panel.add_theme_stylebox_override("panel", _frame_or_flat_panel())

	onboarding_label = Label.new()
	onboarding_label.text = "> " + ONBOARDING_TEXTS[0]
	onboarding_label.add_theme_font_size_override("font_size", 12)
	onboarding_label.add_theme_color_override("font_color", UiThemeRef.COL_BORDER_DIM)
	onboarding_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	onboarding_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	onboarding_panel.add_child(onboarding_label)

	get_parent().add_child.call_deferred(onboarding_panel)


func _update_onboarding() -> void:
	if _onboarding_done or onboarding_panel == null:
		return
	match _onboarding_step:
		0:
			# Ekaan louhinta-alueeseen asti
			if _desig_any_active():
				_advance_onboarding()
		1:
			# Kunnes raha alkaa kasvaa (hauler toi saalista)
			if int(pixel_world.money) > _onboarding_money_base:
				_advance_onboarding()
		2:
			# Kunnes kolmas botti ostettu
			if _current_bot_count() > _onboarding_bot_base:
				_advance_onboarding()
	if _onboarding_done:
		return
	onboarding_label.text = "> " + ONBOARDING_TEXTS[_onboarding_step]
	# Piilota vihje kun mine-rivi/build-tray/bot-tray jo käyttää samaa ankkuripaikkaa
	# actionbarin yläpuolella — ettei kaksi paneelia näy päällekkäin. Sivuvaikutus on
	# looginenkin: esim. askel 0:n "paina V" -vihje ei ole enää tarpeen kun mine-rivi
	# (V:n painamisen seuraus) on jo auki.
	var row_busy: bool = _get_designation_mode() or _build_tray_open or _bot_tray_open
	onboarding_panel.visible = not row_busy


func _advance_onboarding() -> void:
	_onboarding_step += 1
	if _onboarding_step >= ONBOARDING_TEXTS.size():
		_onboarding_done = true
		onboarding_panel.visible = false
		return
	if _onboarding_step == 1:
		_onboarding_money_base = int(pixel_world.money)
	elif _onboarding_step == 2:
		_onboarding_bot_base = _current_bot_count()


func _current_bot_count() -> int:
	var bm := _bm()
	if bm == null:
		return 0
	if bm.has_method("bot_count"):
		return int(bm.bot_count())
	var arr = bm.get("bots")
	return arr.size() if arr != null else 0


# ═══════════════════════════════════════════════════════════════════════════
#  TOASTIT (välitavoitteet)
# ═══════════════════════════════════════════════════════════════════════════

func _build_toast() -> void:
	toast_panel = PanelContainer.new()
	toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	toast_panel.grow_vertical = Control.GROW_DIRECTION_END
	toast_panel.offset_top = 54.0
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.visible = false

	toast_panel.add_theme_stylebox_override("panel",
		UiThemeRef.panel_style_box(UiThemeRef.COL_BG_PANEL, UiThemeRef.COL_BORDER, 1, 8.0))

	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", COL_TEXT)
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(toast_label)

	get_parent().add_child.call_deferred(toast_panel)


func _on_milestone(text: String) -> void:
	_show_toast(text, 3.5)


func _on_demo_complete() -> void:
	_show_toast("Demo valmis! Jatka vapaasti.", 8.0)


# Vaihe 5 kohta 2: fade-in heti näkyviin tullessa. Aiempi toast (jos vielä
# häivytysvaiheessa) katkaistaan ja korvataan uudella — ei jää kesken roikkumaan.
func _show_toast(text: String, duration: float) -> void:
	if toast_label == null:
		return
	_kill_toast_tween()
	toast_label.text = text
	toast_panel.visible = true
	toast_panel.modulate.a = 0.0
	_toast_timer = duration
	_toast_tween = create_tween()
	_toast_tween.tween_property(toast_panel, "modulate:a", 1.0, TOAST_FADE_IN_DURATION)


# Häivyttää toastin ennen piiloutumista (Vaihe 5 kohta 2) — visible=false vasta
# fade-outin lopussa, ei enää suoraan aika loppuessa.
func _update_toast(delta: float) -> void:
	if _toast_timer <= 0.0:
		return
	_toast_timer -= delta
	if _toast_timer <= 0.0:
		_toast_timer = 0.0
		_kill_toast_tween()
		_toast_tween = create_tween()
		_toast_tween.tween_property(toast_panel, "modulate:a", 0.0, TOAST_FADE_OUT_DURATION)
		_toast_tween.tween_callback(func() -> void: toast_panel.visible = false)


func _kill_toast_tween() -> void:
	if _toast_tween != null and _toast_tween.is_valid():
		_toast_tween.kill()
	_toast_tween = null


# ═══════════════════════════════════════════════════════════════════════════
#  MATERIAALISKANNERI (säilyy — GDD §7.3)
# ═══════════════════════════════════════════════════════════════════════════

func _build_scanner_panel() -> void:
	scanner_panel = PanelContainer.new()
	scanner_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	scanner_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	scanner_panel.grow_vertical = Control.GROW_DIRECTION_END
	scanner_panel.offset_right = -8.0
	scanner_panel.offset_top = 56.0
	scanner_panel.offset_left = -188.0
	scanner_panel.offset_bottom = 256.0
	scanner_panel.visible = _debug_visible   # debug-tila (F3) — piilossa oletuksena

	scanner_panel.add_theme_stylebox_override("panel",
		UiThemeRef.panel_style_box(UiThemeRef.COL_BG_PANEL, UiThemeRef.COL_BORDER_DIM, 1, 6.0))

	scanner_label = RichTextLabel.new()
	scanner_label.bbcode_enabled = true
	scanner_label.fit_content = true
	scanner_label.scroll_active = false
	scanner_label.custom_minimum_size = Vector2(168.0, 0.0)
	scanner_label.add_theme_font_size_override("normal_font_size", 11)
	scanner_panel.add_child(scanner_label)

	get_parent().add_child.call_deferred(scanner_panel)


func update_material_scanner() -> void:
	if not is_instance_valid(pixel_world) or scanner_label == null:
		return
	if pixel_world.grid.is_empty():
		return

	var px: int = int(pixel_world.cam_grid_pos.x)
	var py: int = int(pixel_world.cam_grid_pos.y)
	var w: int = pixel_world.SIM_WIDTH
	var h: int = pixel_world.SIM_HEIGHT
	var r: int = SCANNER_RADIUS
	var r2: int = r * r

	var counts: Dictionary = {}
	var total: int = 0
	var y_min: int = maxi(py - r, 0)
	var y_max: int = mini(py + r, h - 1)
	var x_min: int = maxi(px - r, 0)
	var x_max: int = mini(px + r, w - 1)

	for cy in range(y_min, y_max + 1):
		var dy: int = cy - py
		var dy2: int = dy * dy
		if dy2 > r2:
			continue
		var dx_max: int = int(sqrt(float(r2 - dy2)))
		var cx_min: int = maxi(px - dx_max, x_min)
		var cx_max: int = mini(px + dx_max, x_max)
		for cx in range(cx_min, cx_max + 1):
			var mat: int = pixel_world.grid[cy * w + cx]
			if mat != 0:
				counts[mat] = counts.get(mat, 0) + 1
				total += 1

	if total == 0:
		scanner_label.text = "[color=#666666]Skanneri: tyhjää[/color]"
		return

	var entries: Array = []
	for mat_id: int in counts:
		entries.append([mat_id, counts[mat_id]])
	entries.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])

	var lines: PackedStringArray = PackedStringArray()
	lines.append("[color=#aaaaaa]Ympäristö (r=%d)[/color]" % r)
	for entry: Array in entries:
		var mat_id: int = entry[0]
		var count: int = entry[1]
		if not MAT_NAMES.has(mat_id):
			continue
		var pct: float = 100.0 * float(count) / float(total)
		var name_str: String = MAT_NAMES[mat_id]
		if MAT_COLORS.has(mat_id):
			lines.append("[color=%s]%s[/color]  [color=#cccccc]%.1f%%[/color]" % [MAT_COLORS[mat_id], name_str, pct])
		else:
			lines.append("%s  %.1f%%" % [name_str, pct])
	scanner_label.text = "\n".join(lines)


# ═══════════════════════════════════════════════════════════════════════════
#  BOTTIEN TILA MAAILMASSA (Vaihe 4, kohta 10 — erillinen overlay-piirto)
# ═══════════════════════════════════════════════════════════════════════════

func _build_bot_status_overlay() -> void:
	bot_status_overlay = BotStatusOverlayScript.new()
	bot_status_overlay.setup(pixel_world)
	get_parent().add_child.call_deferred(bot_status_overlay)


# ═══════════════════════════════════════════════════════════════════════════
#  PÄÄSILMUKKA
# ═══════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	# TAB togglaa bot-trayn (korvaa vanhan bottom_panelin, Vaihe 3 kohta 5).
	if event.keycode == KEY_TAB:
		_toggle_bot_tray()
		get_viewport().set_input_as_handled()
	# B togglaa build-trayn (UI_REDESIGN_PLAN.md: "Rakenna [B]"). Vapaa näppäin —
	# pixel_world.gd:n KEY_B-tapaus on vain kuolleessa build_menu_visible-haarassa
	# (ei koskaan true), joten ei konfliktia legacy-inputin kanssa.
	elif event.keycode == KEY_B:
		_toggle_build_tray()
		get_viewport().set_input_as_handled()
	# F3 togglaa debug-tilan (FPS, bottilaskuri, materiaaliskanneri).
	# Ei kutsuta set_input_as_handled():a — debug_overlay.gd kuuntelee samaa
	# näppäintä omaan overlayynsa, eikä sitä saa syödä täällä.
	elif event.keycode == KEY_F3:
		_debug_visible = not _debug_visible
		_apply_debug_visibility()
	# Esc sulkee ylimmän auki olevan UI-elementin (popover -> build-tray -> bot-tray).
	# Ei syödä eventtiä — pixel_world.gd:llä on oma, riippumaton Esc-käsittelynsä
	# (rakennus-/vyöhykesijoituksen peruutus), joka ei liity tähän UI-tilaan.
	elif event.keycode == KEY_ESCAPE:
		if _context_popover != null:
			_close_context_popover()
		elif _build_tray_open:
			_close_build_tray()
		elif _bot_tray_open:
			_close_bot_tray()


func _process(delta: float) -> void:
	if not is_instance_valid(pixel_world):
		return

	# Kevyet päivitykset joka frame
	money_label.text = "$%d" % int(pixel_world.money)
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	_update_toast(delta)
	_update_onboarding()
	_update_actionbar_highlight()
	_update_build_tray_visibility()
	_handle_popover_outside_click()
	_clamp_context_popover()

	# Raskaammat päivitykset ~5 Hz
	_ui_accum += delta
	if _ui_accum >= 0.2:
		_ui_accum = 0.0
		_update_income()
		_update_fleet()
		_update_afford()
		_maybe_rebuild_bot_list()
		_update_machine_popover()   # Vaihe 5 kohta 4: ~5 Hz > pyydetty ~2 Hz, riittää

	# Materiaaliskanneri harvakseltaan — vain debug-tilassa (F3)
	if _debug_visible:
		_scanner_frame += 1
		if _scanner_frame >= SCANNER_INTERVAL:
			_scanner_frame = 0
			update_material_scanner()


# Näyttää/piilottaa debug-tilan elementit (FPS, bottilaskuri, skanneri) F3:lla.
func _apply_debug_visibility() -> void:
	if debug_row != null:
		debug_row.visible = _debug_visible
	if scanner_panel != null:
		scanner_panel.visible = _debug_visible


func _update_income() -> void:
	# $/s-mittari — vain jos lane G on lisännyt income_per_s-kentän, piilotetaan
	# myös jos arvo on ~0 (ei mitään näytettävää)
	var inc = pixel_world.get("income_per_s")
	if inc == null:
		income_label.visible = false
		return
	var f := float(inc)
	if absf(f) < 0.05:
		income_label.visible = false
		return
	income_label.visible = true
	income_label.text = "+$%d/s" % int(round(f))
	income_label.add_theme_color_override("font_color", COL_MONEY if f > 0.0 else COL_DIM)


func _update_fleet() -> void:
	# Päivitetään ~5 Hz (samassa tahdissa $/s-mittarin kanssa, ks. _process). Yksi
	# get_fleet_stats()-kutsu ruokkii sekä pysyvän yläpalkkilaskurin (D5) että
	# F3-debug-rivin — ei duplikaattikutsua.
	var bm := _bm()
	if bm != null and bm.has_method("get_fleet_stats"):
		var s: Dictionary = bm.get_fleet_stats()
		var mi_a := int(s.get("miners_active", 0))
		var mi := int(s.get("miners", 0))
		var ha_a := int(s.get("haulers_active", 0))
		var ha := int(s.get("haulers", 0))
		# Pysyvä yläpalkin bottilaskuri (aktiiviset/kaikki)
		fleet_miner_label.text = "%d/%d" % [mi_a, mi]
		fleet_hauler_label.text = "%d/%d" % [ha_a, ha]
		# F3-debug-rivi ennallaan
		fleet_label.text = "Miner %d/%d    Hauler %d/%d" % [mi_a, mi, ha_a, ha]
		role_count_label.text = "%d" % mi
		var has_setrole: bool = bm.has_method("set_role")
		role_minus_btn.disabled = not has_setrole
		role_plus_btn.disabled = not has_setrole
	elif bm != null:
		var arr = bm.get("bots")
		fleet_miner_label.text = "—"
		fleet_hauler_label.text = "—"
		fleet_label.text = "Botteja: %d" % (arr.size() if arr != null else 0)
		role_count_label.text = "—"
		role_minus_btn.disabled = true
		role_plus_btn.disabled = true
	else:
		fleet_miner_label.text = "0/0"
		fleet_hauler_label.text = "0/0"
		fleet_label.text = ""
		role_count_label.text = "—"
		role_minus_btn.disabled = true
		role_plus_btn.disabled = true


func _update_actionbar_highlight() -> void:
	if tool_btn_mine == null:
		return
	var dm: bool = _get_designation_mode()
	tool_btn_mine.modulate = COL_ACTIVE if dm else Color.WHITE
	mine_row_panel.visible = dm
	for i in desig_mode_buttons.size():
		desig_mode_buttons[i].modulate = COL_ACTIVE if (dm and i == _desig_tool_mode) else Color.WHITE

	var building: bool = pixel_world.build_mode != pixel_world.BUILD_NONE
	tool_btn_build.modulate = COL_ACTIVE if (building or _build_tray_open) else Color.WHITE

	tool_btn_bots.modulate = COL_ACTIVE if _bot_tray_open else Color.WHITE

	var erasing: bool = (not dm) and (not building) and int(pixel_world.current_material) == MAT_EMPTY
	tool_btn_erase.modulate = COL_ACTIVE if erasing else Color.WHITE

	_update_speed_highlight()


# Korostaa aktiivisen peliajan nopeuden (Tauko/1x/2x/3x/4x) samalla COL_ACTIVE-
# modulaatiotekniikalla kuin desig_mode_buttons yllä.
func _update_speed_highlight() -> void:
	if speed_buttons.is_empty():
		return
	var speed: float = pixel_world.sim_speed
	for i in speed_buttons.size():
		speed_buttons[i].modulate = COL_ACTIVE if is_equal_approx(speed, SPEED_VALUES[i]) else Color.WHITE


# ═══════════════════════════════════════════════════════════════════════════
#  GUARDATUT PIXEL_WORLD-ACCESSORIT (designaatio voi puuttua vanhalta baselinelta)
# ═══════════════════════════════════════════════════════════════════════════

func _get_designation_mode() -> bool:
	var v = pixel_world.get("designation_mode")
	return bool(v) if v != null else false


func _set_designation_mode(on: bool) -> void:
	pixel_world.set("designation_mode", on)


func _desig_any_active() -> bool:
	var d = pixel_world.get("desig")
	return d != null and d.has_method("any_active") and d.any_active()


# ═══════════════════════════════════════════════════════════════════════════
#  APURIT
# ═══════════════════════════════════════════════════════════════════════════

func _sep() -> VSeparator:
	return VSeparator.new()


# Isot paneelit (trayt, popoverit): 9-slice panel_frame.png kun saatavilla, muuten
# StyleBoxFlat-fallback samalla amber-paletilla (UiTheme.panel_style_box()).
func _frame_or_flat_panel() -> StyleBox:
	var frame := UiThemeRef.panel_frame_style_box()
	if frame != null:
		return frame
	return UiThemeRef.panel_style_box(UiThemeRef.COL_BG_PANEL, UiThemeRef.COL_BORDER_DIM, 1, 10.0)


# Ikoninappi (actionbar/trayt): 9-slice button_frame.png kun saatavilla, nearest-filter
# terävälle pikselilookille. Vaihe 5: normal/hover/pressed ovat erilliset tekstuuri-
# tintit (UiTheme.icon_button_state_styleboxes) — aktiivinen työkalu erottuu tästä
# silti omalla COL_ACTIVE-modulaatiollaan (ks. _update_actionbar_highlight), joka
# kertautuu hover/press-tintin päälle eikä korvaa sitä. button_frame.png:n 8px-
# marginaali on tarkoitettu tälle 48px-kokoluokalle; pienempiin (<32px) napteihin
# sitä ei käytetä (ks. UI_REDESIGN_PLAN.md Vaihe 3 kohta 6 — team-leadin sallima
# StyleBoxFlat-fallback pienille napeille, joka jo erottelee hover/pressed teeman
# kautta).
func _make_tool_button(icon: Texture2D, tooltip: String, size: float) -> Button:
	var b := Button.new()
	b.icon = icon
	b.expand_icon = true
	b.text = ""
	b.custom_minimum_size = Vector2(size, size)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tooltip
	b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	if size >= 40.0:
		# Vaihe 5 kohta 1: erilliset normal/hover/pressed-tekstuurit (ei enää sama
		# kehys kaikissa tiloissa) — COL_ACTIVE-modulaatio (_update_actionbar_highlight)
		# pysyy erillisenä kerroksena tämän päällä, joten aktiivinen työkalu erottuu
		# silti hoverista.
		var states := UiThemeRef.icon_button_state_styleboxes()
		if not states.is_empty():
			b.add_theme_stylebox_override("normal", states["normal"])
			b.add_theme_stylebox_override("hover", states["hover"])
			b.add_theme_stylebox_override("pressed", states["pressed"])
			b.add_theme_stylebox_override("focus", states["focus"])
	return b


func _make_btn(text: String, font_size: int = 12) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", font_size)
	return btn


# Pieni tilastoikoni (yläpalkin bottilaskuri): TextureRect nearest-filterillä terävää
# pikselilookia varten. Skaalataan annettuun kokoon kuvasuhde säilyttäen.
func _make_stat_icon(icon: Texture2D, tooltip: String = "", size: float = 20.0) -> TextureRect:
	var tr := TextureRect.new()
	tr.texture = icon
	tr.custom_minimum_size = Vector2(size, size)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tr.tooltip_text = tooltip
	return tr


func _label(text: String, font_size: int = 12, color: Color = COL_TEXT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
