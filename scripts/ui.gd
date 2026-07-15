extends PanelContainer
# ═══════════════════════════════════════════════════════════════════════════
# UI 2.0 — kaivosyhtiön johtajan käyttöliittymä (DEMO_PLAN §3.1, kortti B1)
#
# Rakenne (kaikki ohjelmallinen):
#   • YLÄPALKKI (tämä PanelContainer): raha isolla, $/s, bottilaskuri, FPS
#   • TYÖKALURIVI (alhaalla): designaatio [V] + moodit pensseli/laatikko/solu + koko
#   • ALAPANEELI (TAB togglaa): kolme välilehteä BOTIT / RAKENNUKSET / LOGISTIIKKA
#   • ONBOARDING: max 3 peräkkäistä opastetta
#   • TOASTIT: kuuntelee world.milestone-signaalia (jos on)
#   • MATERIAALISKANNERI (oikea yläkulma): ympäristön koostumus
#
# RINNAKKAISKEHITYS: bot_manager/logistics-rajapinnat (lane A) ja
# pixel_world-kytkennät (lane G) tulevat myöhemmin. Kaikki niiden kutsut on
# guardattu has_method()/has_signal()/get():llä — napit joiden backend puuttuu
# näkyvät harmaina. Integraatiossa kaikki herää eloon.
# ═══════════════════════════════════════════════════════════════════════════

@onready var pixel_world: TextureRect = get_node("../../PixelWorld")

# Roolit (bot.gd Role-enum: MINER=0, HAULER=1)
const ROLE_MINER := 0
const ROLE_HAULER := 1
# Vyöhyketyypit begin_zone_placement()-kutsulle (lane G tulkitsee)
const ZONE_PICKUP := 0
const ZONE_DUMP := 1

# Värit
const COL_MONEY := Color(0.35, 0.92, 0.48)
const COL_BAD := Color(0.95, 0.42, 0.42)
const COL_DIM := Color(0.52, 0.52, 0.58)
const COL_ACTIVE := Color(1.5, 1.5, 0.6)
const COL_TEXT := Color(0.9, 0.92, 0.95)

# ── Yläpalkki ──────────────────────────────────────────────────────────────
var money_label: Label
var income_label: Label
var fleet_label: Label
var fps_label: Label

# ── Työkalurivi ────────────────────────────────────────────────────────────
var toolbar_panel: PanelContainer
var btn_desig: Button
var desig_mode_buttons: Array[Button] = []
var _desig_tool_mode: int = 0
var brush_slider: HSlider
var brush_label: Label

# ── Alapaneeli (välilehdet) ────────────────────────────────────────────────
var bottom_panel: PanelContainer
var tab_container: TabContainer
# Botit-välilehti
var role_minus_btn: Button
var role_plus_btn: Button
var role_count_label: Label
var bot_list_vbox: VBoxContainer
var _last_fleet_sig: String = ""
var _bot_upgrade_items: Array = []   # [{ "btn": Button, "price": int }]
# Logistiikka-välilehti
var base_filter_checks: Dictionary = {}   # mat_id -> CheckBox
var zone_filter_checks: Dictionary = {}   # mat_id -> CheckBox (valittu vyöhyke)
var zone_list_vbox: VBoxContainer
var _selected_zone_id: int = -1
var _zones_cache: Array = []

# Ostettavat kortit joiden hinta/varaa-tila päivittyy: [{panel, price_label, cost_fn}]
var _afford_items: Array = []

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

# ── Materiaaliskanneri ─────────────────────────────────────────────────────
var scanner_panel: PanelContainer
var scanner_label: RichTextLabel
var _scanner_frame: int = 0
const SCANNER_INTERVAL: int = 6
const SCANNER_RADIUS: int = 50

# Päivitysakku raskaammille päivityksille (~5 Hz)
var _ui_accum: float = 0.0

# Materiaalinimet ja -värit skannerille (ID:t 0–21)
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

# Materiaalifiltterien (logistiikka) valikoima
const FILTER_MATS: Array = [
	[11, "Multa"], [1, "Hiekka"], [18, "Sora"], [16, "Hiili"],
	[12, "Rautamalmi"], [13, "Kultamalmi"], [20, "Kupari"], [21, "Harv.maa"],
	[14, "Rauta"], [15, "Kulta"], [10, "Lasi"],
]


# ═══════════════════════════════════════════════════════════════════════════
#  RAKENNUS
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_register_panel(self)   # yläpalkki hiiri-inputin estoon

	_build_top_bar()
	_build_toolbar()
	_build_bottom_panel()
	_build_scanner_panel()
	_build_toast()
	_build_onboarding()
	_connect_world_signals()

	# Lisäpaneelit rekisteröidään estoon vasta kun ne on lisätty (deferred)
	_register_ui_panels.call_deferred()


func _connect_world_signals() -> void:
	# Välitavoite-toastit ja demo-loppu — vain jos lane G on lisännyt signaalit
	if pixel_world.has_signal("milestone"):
		pixel_world.milestone.connect(_on_milestone)
	if pixel_world.has_signal("demo_complete"):
		pixel_world.demo_complete.connect(_on_demo_complete)


func _register_ui_panels() -> void:
	for panel in [bottom_panel, toolbar_panel, scanner_panel]:
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


# ── Yläpalkki ──────────────────────────────────────────────────────────────

func _build_top_bar() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, 0.96)
	style.border_width_bottom = 2
	style.border_color = Color(0.25, 0.55, 0.85, 0.7)
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 2.0
	style.content_margin_bottom = 2.0
	add_theme_stylebox_override("panel", style)

	var hbox := HBoxContainer.new()
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 10)
	add_child(hbox)

	# Raha isolla
	money_label = Label.new()
	money_label.text = "$0"
	money_label.add_theme_font_size_override("font_size", 26)
	money_label.add_theme_color_override("font_color", COL_MONEY)
	money_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(money_label)

	# $/s-mittari (piilotetaan jos world.income_per_s puuttuu)
	income_label = Label.new()
	income_label.text = ""
	income_label.add_theme_font_size_override("font_size", 15)
	income_label.add_theme_color_override("font_color", COL_MONEY)
	income_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(income_label)

	hbox.add_child(_sep())

	# Bottilaskuri rooleittain
	fleet_label = Label.new()
	fleet_label.text = ""
	fleet_label.add_theme_font_size_override("font_size", 15)
	fleet_label.add_theme_color_override("font_color", COL_TEXT)
	fleet_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(fleet_label)

	# Täyte työntää FPS:n oikealle
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	# FPS pienenä
	fps_label = Label.new()
	fps_label.text = "FPS 0"
	fps_label.add_theme_font_size_override("font_size", 12)
	fps_label.add_theme_color_override("font_color", Color(0.55, 0.58, 0.62))
	fps_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(fps_label)


# ── Työkalurivi ────────────────────────────────────────────────────────────

func _build_toolbar() -> void:
	toolbar_panel = PanelContainer.new()
	toolbar_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar_panel.offset_top = -40.0
	toolbar_panel.offset_bottom = 0.0
	toolbar_panel.add_theme_stylebox_override("panel", _dark_style(0.95))

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	toolbar_panel.add_child(hb)

	# Designaatio-toggle [V]
	btn_desig = _make_btn("Louhinta [V]", 13)
	btn_desig.pressed.connect(_toggle_designation)
	hb.add_child(btn_desig)

	hb.add_child(_sep())

	# Kolme moodinappia: pensseli / laatikko / solu
	var mode_names := ["Pensseli", "Laatikko", "Solu"]
	for i in mode_names.size():
		var b := _make_btn(mode_names[i], 12)
		b.pressed.connect(_set_desig_mode.bind(i))
		hb.add_child(b)
		desig_mode_buttons.append(b)

	hb.add_child(_sep())

	# Pensselikoko (uusiokäyttö brush_size:sta)
	brush_label = Label.new()
	brush_label.text = "Koko: %d" % int(pixel_world.brush_size)
	brush_label.add_theme_font_size_override("font_size", 12)
	brush_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(brush_label)

	brush_slider = HSlider.new()
	brush_slider.min_value = 1.0
	brush_slider.max_value = 30.0
	brush_slider.step = 1.0
	brush_slider.value = float(pixel_world.brush_size)
	brush_slider.focus_mode = Control.FOCUS_NONE
	brush_slider.custom_minimum_size = Vector2(100.0, 0.0)
	brush_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	brush_slider.value_changed.connect(_on_brush_changed)
	hb.add_child(brush_slider)

	hb.add_child(_sep())

	var hint := Label.new()
	hint.text = "Oikea hiiri = poista"
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", COL_DIM)
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(hint)

	get_parent().add_child.call_deferred(toolbar_panel)


func _toggle_designation() -> void:
	var on := not _get_designation_mode()
	_set_designation_mode(on)
	if on:
		pixel_world.build_mode = 0  # BUILD_NONE


func _set_desig_mode(mode: int) -> void:
	_desig_tool_mode = mode
	# Kytke pixel_worldin työkalumoodi jos backend on (lane G); muuten vain UI-korostus
	if pixel_world.has_method("set_designation_tool_mode"):
		pixel_world.set_designation_tool_mode(mode)
	# Työkalun valinta aktivoi louhintatilan
	_set_designation_mode(true)
	pixel_world.build_mode = 0  # BUILD_NONE


func _on_brush_changed(value: float) -> void:
	pixel_world.brush_size = int(value)
	brush_label.text = "Koko: %d" % int(value)


# ── Alapaneeli (välilehdet) ────────────────────────────────────────────────

func _build_bottom_panel() -> void:
	bottom_panel = PanelContainer.new()
	bottom_panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom_panel.offset_top = -270.0
	bottom_panel.offset_bottom = -40.0   # työkalurivin yläpuolelle
	bottom_panel.add_theme_stylebox_override("panel", _dark_style(0.97))

	tab_container = TabContainer.new()
	tab_container.add_theme_font_size_override("font_size", 13)
	bottom_panel.add_child(tab_container)

	_build_bots_tab()
	_build_buildings_tab()
	_build_logistics_tab()

	get_parent().add_child.call_deferred(bottom_panel)


func _tab_root(title: String) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.name = title
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	margin.add_child(vb)
	tab_container.add_child(margin)
	return vb


func _build_bots_tab() -> void:
	var root := _tab_root("BOTIT")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hb)

	# ── Vasen: osto + roolijako ──
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)

	var buy_row := HBoxContainer.new()
	buy_row.add_theme_constant_override("separation", 8)
	left.add_child(buy_row)
	_add_afford_card(buy_row, "Osta Miner", "Louhii merkatut alueet", _bot_price,
		_buy_bot.bind(ROLE_MINER))
	_add_afford_card(buy_row, "Osta Hauler", "Kuljettaa saaliin baseen", _bot_price,
		_buy_bot.bind(ROLE_HAULER))

	var role_row := HBoxContainer.new()
	role_row.add_theme_constant_override("separation", 6)
	left.add_child(role_row)
	role_row.add_child(_label("Minereitä:", 13))
	role_minus_btn = _make_btn("−", 16)
	role_minus_btn.custom_minimum_size = Vector2(30.0, 0.0)
	role_minus_btn.pressed.connect(_on_role_change.bind(-1))
	role_row.add_child(role_minus_btn)
	role_count_label = _label("—", 16)
	role_count_label.custom_minimum_size = Vector2(28.0, 0.0)
	role_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_row.add_child(role_count_label)
	role_plus_btn = _make_btn("+", 16)
	role_plus_btn.custom_minimum_size = Vector2(30.0, 0.0)
	role_plus_btn.pressed.connect(_on_role_change.bind(1))
	role_row.add_child(role_plus_btn)

	# ── Oikea: bottilista + Mk-upgradet ──
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	right.add_child(_label("Botit & upgradet", 12, COL_DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(340.0, 170.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bot_list_vbox = VBoxContainer.new()
	bot_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bot_list_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(bot_list_vbox)
	right.add_child(scroll)


func _build_buildings_tab() -> void:
	var root := _tab_root("RAKENNUKSET")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	root.add_child(row)
	# VAIN Furnace / Crusher / Hihna — sand_mine/spawner/linko/kaivos poistuvat (lane E)
	_add_afford_card(row, "Furnace", "Sulattaa malmit harkoiksi",
		func() -> int: return _building_cost("furnace"),
		func() -> void: _buy_building(pixel_world.BUILD_FURNACE, _building_cost("furnace")))
	_add_afford_card(row, "Crusher", "Murskaa kiven soraksi",
		func() -> int: return _building_cost("crusher"),
		func() -> void: _buy_building(pixel_world.BUILD_CRUSHER, _building_cost("crusher")))
	_add_afford_card(row, "Hihna", "Kuljettaa ilman bottia",
		func() -> int: return _building_cost("conveyor"),
		func() -> void: _buy_building(pixel_world.BUILD_CONVEYOR_START, _building_cost("conveyor")))

	root.add_child(_label("Klikkaa kortti → sijoita hiirellä. Esc / oikea hiiri peruu.", 11, COL_DIM))


func _build_logistics_tab() -> void:
	var root := _tab_root("LOGISTIIKKA")
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(hb)

	# ── Vasen: sijoituskortit + suodattimet ──
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)

	var card_row := HBoxContainer.new()
	card_row.add_theme_constant_override("separation", 8)
	left.add_child(card_row)
	_add_afford_card(card_row, "Pickup-piste", "Haulerit hakevat täältä",
		func() -> int: return _zone_cost(80),
		func() -> void: _place_zone(ZONE_PICKUP, 80))
	_add_afford_card(card_row, "Dump-piste", "Haulerit purkavat tänne",
		func() -> int: return _zone_cost(60),
		func() -> void: _place_zone(ZONE_DUMP, 60))

	left.add_child(_label("Base hyväksyy:", 12, COL_DIM))
	base_filter_checks = _build_filter_grid(left, func() -> void: _on_base_filter_changed())

	left.add_child(_label("Valittu vyöhyke:", 12, COL_DIM))
	zone_filter_checks = _build_filter_grid(left, func() -> void: _on_zone_filter_changed())

	# ── Oikea: vyöhykelista ──
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(right)
	right.add_child(_label("Vyöhykkeet", 12, COL_DIM))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300.0, 170.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	zone_list_vbox = VBoxContainer.new()
	zone_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zone_list_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(zone_list_vbox)
	right.add_child(scroll)


# Rakentaa materiaalifiltteri-checkbox-ruudukon; palauttaa mat_id -> CheckBox
func _build_filter_grid(parent: VBoxContainer, on_toggle: Callable) -> Dictionary:
	var grid := GridContainer.new()
	grid.columns = 4
	parent.add_child(grid)
	var checks: Dictionary = {}
	for m in FILTER_MATS:
		var cb := CheckBox.new()
		cb.text = m[1]
		cb.button_pressed = true
		cb.focus_mode = Control.FOCUS_NONE
		cb.disabled = true  # logistiikka-backend puuttuu -> herää integraatiossa
		cb.add_theme_font_size_override("font_size", 11)
		cb.toggled.connect(func(_v: bool) -> void: on_toggle.call())
		checks[int(m[0])] = cb
		grid.add_child(cb)
	return checks


# ═══════════════════════════════════════════════════════════════════════════
#  OSTOKORTIT (hinta + varaa-tila)
# ═══════════════════════════════════════════════════════════════════════════

# Rakentaa kortin (nimi + hinta + kuvaus) joka reagoi vasempaan klikkaukseen.
func _add_afford_card(parent: Control, title: String, desc: String,
		cost_fn: Callable, on_click: Callable) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	panel.custom_minimum_size = Vector2(150.0, 0.0)

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.13, 0.18, 0.98)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.35, 0.45, 0.8)
	panel.add_theme_stylebox_override("panel", style)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 1)
	panel.add_child(vb)

	var name_lbl := Label.new()
	name_lbl.text = title
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", COL_TEXT)
	vb.add_child(name_lbl)

	var price_lbl := Label.new()
	price_lbl.text = ""
	price_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	price_lbl.add_theme_font_size_override("font_size", 15)
	price_lbl.add_theme_color_override("font_color", COL_MONEY)
	vb.add_child(price_lbl)

	if desc != "":
		var desc_lbl := Label.new()
		desc_lbl.text = desc
		desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		desc_lbl.add_theme_font_size_override("font_size", 10)
		desc_lbl.add_theme_color_override("font_color", Color(0.6, 0.62, 0.68))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.custom_minimum_size = Vector2(136.0, 0.0)
		vb.add_child(desc_lbl)

	panel.gui_input.connect(func(e: InputEvent) -> void:
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			on_click.call())

	parent.add_child(panel)
	_afford_items.append({ "panel": panel, "price_label": price_lbl, "cost_fn": cost_fn })


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


# Botin hinta next_bot_price():stä; -1 jos backend puuttuu (kortti harmaana)
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


func _on_base_filter_changed() -> void:
	var lg := _logistics()
	if lg == null or not lg.has_method("set_base_filter"):
		return
	lg.set_base_filter(_filter_mask_from(base_filter_checks))


func _on_zone_filter_changed() -> void:
	var lg := _logistics()
	if lg == null or _selected_zone_id < 0 or not lg.has_method("set_zone_filter"):
		return
	lg.set_zone_filter(_selected_zone_id, _filter_mask_from(zone_filter_checks))


func _update_logistics() -> void:
	var lg := _logistics()
	var base_enabled: bool = lg != null and lg.has_method("set_base_filter")
	for mat_id in base_filter_checks:
		base_filter_checks[mat_id].disabled = not base_enabled

	_refresh_zone_list(lg)

	var zone_enabled: bool = lg != null and _selected_zone_id >= 0 and lg.has_method("set_zone_filter")
	for mat_id in zone_filter_checks:
		zone_filter_checks[mat_id].disabled = not zone_enabled


func _refresh_zone_list(lg: Object) -> void:
	if zone_list_vbox == null:
		return
	if lg == null or not lg.has_method("get_zones"):
		if zone_list_vbox.get_child_count() != 1:
			_clear_children(zone_list_vbox)
			zone_list_vbox.add_child(_label("Logistiikka ei saatavilla (odottaa lane A)", 11, COL_DIM))
		return

	var zones: Array = lg.get_zones()
	# Rakenna lista uudelleen vain jos vyöhykkeet muuttuivat
	if _zones_signature(zones) == _zones_signature(_zones_cache):
		return
	_zones_cache = zones
	_clear_children(zone_list_vbox)
	if zones.is_empty():
		zone_list_vbox.add_child(_label("Ei vyöhykkeitä", 11, COL_DIM))
		return
	for z in zones:
		var zid := int(z.get("id", -1))
		var ztype := String(z.get("type", "?"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		var sel := _make_btn("%s #%d" % [ztype.capitalize(), zid], 11)
		sel.pressed.connect(_on_select_zone.bind(zid))
		row.add_child(sel)
		var rem := _make_btn("Poista", 11)
		rem.pressed.connect(_on_remove_zone.bind(zid))
		row.add_child(rem)
		zone_list_vbox.add_child(row)


func _on_select_zone(zid: int) -> void:
	_selected_zone_id = zid
	# Lataa vyöhykkeen nykyinen filtteri checkboxeihin
	for z in _zones_cache:
		if int(z.get("id", -1)) == zid:
			var mask := int(z.get("filter_mask", 0))
			for mat_id in zone_filter_checks:
				# mask 0 = ei rajausta -> kaikki päällä
				zone_filter_checks[mat_id].set_pressed_no_signal(
					mask == 0 or (mask & (1 << int(mat_id))) != 0)
			break


func _on_remove_zone(zid: int) -> void:
	var lg := _logistics()
	if lg == null or not lg.has_method("remove_zone"):
		return
	lg.remove_zone(zid)
	if _selected_zone_id == zid:
		_selected_zone_id = -1


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


func _zones_signature(zones: Array) -> String:
	var parts := PackedStringArray()
	for z in zones:
		parts.append("%d:%s:%d" % [int(z.get("id", -1)), String(z.get("type", "?")), int(z.get("filter_mask", 0))])
	return "|".join(parts)


# ═══════════════════════════════════════════════════════════════════════════
#  ONBOARDING
# ═══════════════════════════════════════════════════════════════════════════

func _build_onboarding() -> void:
	onboarding_panel = PanelContainer.new()
	onboarding_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	onboarding_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	onboarding_panel.grow_vertical = Control.GROW_DIRECTION_END
	onboarding_panel.offset_top = 96.0
	onboarding_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.82)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(14.0)
	style.set_border_width_all(1)
	style.border_color = Color(0.3, 0.6, 0.9, 0.5)
	onboarding_panel.add_theme_stylebox_override("panel", style)

	onboarding_label = Label.new()
	onboarding_label.text = ONBOARDING_TEXTS[0]
	onboarding_label.add_theme_font_size_override("font_size", 22)
	onboarding_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.85))
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
	if not _onboarding_done:
		onboarding_label.text = ONBOARDING_TEXTS[_onboarding_step]
		onboarding_panel.visible = true


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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.14, 0.09, 0.92)
	style.set_corner_radius_all(5)
	style.set_content_margin_all(8.0)
	style.set_border_width_all(1)
	style.border_color = COL_MONEY
	toast_panel.add_theme_stylebox_override("panel", style)

	toast_label = Label.new()
	toast_label.add_theme_font_size_override("font_size", 18)
	toast_label.add_theme_color_override("font_color", Color(0.85, 1.0, 0.85))
	toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast_panel.add_child(toast_label)

	get_parent().add_child.call_deferred(toast_panel)


func _on_milestone(text: String) -> void:
	_show_toast(text, 3.5)


func _on_demo_complete() -> void:
	_show_toast("Demo valmis! Jatka vapaasti.", 8.0)


func _show_toast(text: String, duration: float) -> void:
	if toast_label == null:
		return
	toast_label.text = text
	toast_panel.visible = true
	_toast_timer = duration


func _update_toast(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			toast_panel.visible = false


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

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.08, 0.72)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(6.0)
	scanner_panel.add_theme_stylebox_override("panel", style)

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
#  PÄÄSILMUKKA
# ═══════════════════════════════════════════════════════════════════════════

func _input(event: InputEvent) -> void:
	# TAB togglaa alapaneelin näkyvyyden
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_TAB:
		if bottom_panel != null:
			bottom_panel.visible = not bottom_panel.visible
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not is_instance_valid(pixel_world):
		return

	# Kevyet päivitykset joka frame
	money_label.text = "$%d" % int(pixel_world.money)
	fps_label.text = "FPS %d" % Engine.get_frames_per_second()
	_update_toast(delta)
	_update_onboarding()
	_update_toolbar_highlight()

	# Raskaammat päivitykset ~5 Hz
	_ui_accum += delta
	if _ui_accum >= 0.2:
		_ui_accum = 0.0
		_update_income()
		_update_fleet()
		_update_afford()
		_maybe_rebuild_bot_list()
		_update_logistics()

	# Materiaaliskanneri harvakseltaan
	_scanner_frame += 1
	if _scanner_frame >= SCANNER_INTERVAL:
		_scanner_frame = 0
		update_material_scanner()


func _update_income() -> void:
	# $/s-mittari — vain jos lane G on lisännyt income_per_s-kentän
	var inc = pixel_world.get("income_per_s")
	if inc == null:
		income_label.visible = false
		return
	income_label.visible = true
	var f := float(inc)
	income_label.text = "+$%d/s" % int(round(f))
	income_label.add_theme_color_override("font_color", COL_MONEY if f > 0.0 else COL_DIM)


func _update_fleet() -> void:
	var bm := _bm()
	if bm != null and bm.has_method("get_fleet_stats"):
		var s: Dictionary = bm.get_fleet_stats()
		fleet_label.text = "Miner %d/%d    Hauler %d/%d" % [
			int(s.get("miners_active", 0)), int(s.get("miners", 0)),
			int(s.get("haulers_active", 0)), int(s.get("haulers", 0))]
		role_count_label.text = "%d" % int(s.get("miners", 0))
		var has_setrole: bool = bm.has_method("set_role")
		role_minus_btn.disabled = not has_setrole
		role_plus_btn.disabled = not has_setrole
	elif bm != null:
		var arr = bm.get("bots")
		fleet_label.text = "Botteja: %d" % (arr.size() if arr != null else 0)
		role_count_label.text = "—"
		role_minus_btn.disabled = true
		role_plus_btn.disabled = true
	else:
		fleet_label.text = ""
		role_count_label.text = "—"
		role_minus_btn.disabled = true
		role_plus_btn.disabled = true


func _update_toolbar_highlight() -> void:
	if btn_desig == null:
		return
	var dm: bool = _get_designation_mode()
	btn_desig.modulate = COL_ACTIVE if dm else Color.WHITE
	for i in desig_mode_buttons.size():
		desig_mode_buttons[i].modulate = COL_ACTIVE if (dm and i == _desig_tool_mode) else Color.WHITE


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


func _make_btn(text: String, font_size: int = 12) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", font_size)
	return btn


func _label(text: String, font_size: int = 12, color: Color = COL_TEXT) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return lbl


func _dark_style(alpha: float) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.08, 0.11, alpha)
	style.border_width_top = 2
	style.border_color = Color(0.25, 0.4, 0.6, 0.7)
	style.content_margin_left = 8.0
	style.content_margin_right = 8.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _clear_children(node: Node) -> void:
	for c in node.get_children():
		c.queue_free()
