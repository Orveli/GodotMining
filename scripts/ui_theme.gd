class_name UiTheme
extends RefCounted
# ═══════════════════════════════════════════════════════════════════════════
# UI_THEME — yksi yhteinen Theme-resurssi koko käyttöliittymälle
# (UI_REDESIGN_PLAN.md, Vaihe 1)
#
# Paletti: "Industrial Gothic Underground" — lähes musta kivi + lämmin amber-
# aksentti. EI SINISTÄ missään (vanha 0.25,0.55,0.85-border on poistunut).
# Pikselifontti (Silkscreen) antialiasointi/hinting pois → terävät pikselit.
# ═══════════════════════════════════════════════════════════════════════════

# ── Paletti ──────────────────────────────────────────────────────────────
const COL_BG_PANEL := Color("1a1712e6")        # paneelien tausta, lähes musta kivi
const COL_BG_PANEL_LIGHT := Color("241f18e6")  # vaaleampi sävy (napit, hover-alusta)
const COL_BORDER := Color("d98a3a")            # lämmin amber — ainoa kirkas reunusväri
const COL_BORDER_DIM := Color("6b4a26")        # himmeä amber, ei-aktiivinen reunus
const COL_TEXT := Color("e8e0d0")              # lämmin vaalea teksti
const COL_TEXT_DIM := Color("7a7060")          # himmeä toissijainen teksti
const COL_MONEY := Color("e6c732")             # kulta — raha
const COL_BAD := Color("a8483a")               # punaruskea — virhe / ei varaa
const COL_ACTIVE := Color(1.6, 1.15, 0.55)     # ylikirkas amber-modulaatio (aktiivinen työkalu)

const FONT_PATH_REGULAR := "res://assets/ui/fonts/Silkscreen-Regular.ttf"
const FONT_PATH_BOLD := "res://assets/ui/fonts/Silkscreen-Bold.ttf"

const DEFAULT_FONT_SIZE := 14

# ── 9-slice-paneelikehykset (UI-REDESIGN Vaihe 3, assets/ui/panels/) ────────
const PANEL_FRAME_PATH := "res://assets/ui/panels/panel_frame.png"   # 48×48, marginaalit 12px
const BUTTON_FRAME_PATH := "res://assets/ui/panels/button_frame.png"  # 24×24, marginaalit 8px


# Rakentaa ja palauttaa yhden yhteisen Theme-resurssin. Kutsutaan kerran
# UI-juuren _ready():ssa (ui.gd: `theme = UiTheme.build_theme()`).
static func build_theme() -> Theme:
	var theme := Theme.new()

	var font := _load_pixel_font(FONT_PATH_REGULAR)
	if font != null:
		theme.default_font = font
	theme.default_font_size = DEFAULT_FONT_SIZE

	_style_panel(theme)
	_style_button(theme)
	_style_checkbox(theme)
	_style_slider(theme)
	_style_tab_container(theme)
	_style_tooltip(theme)
	_style_label(theme)

	return theme


# Lataa pikselifontin ja sammuttaa antialiasoinnin/hintingin jotta reunat
# pysyvät terävinä nearest-filter-renderöinnin rinnalla. Palauttaa null jos
# fonttiassettia ei löydy (esim. lataus epäonnistui) — kutsuja käyttää silloin
# Godotin oletusfonttia.
static func _load_pixel_font(path: String) -> FontFile:
	if not ResourceLoader.exists(path):
		return null
	var font := load(path) as FontFile
	if font == null:
		return null
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.hinting = TextServer.HINTING_NONE
	font.oversampling = 1.0
	return font


# Yleinen paneelityylin rakentaja — teräväkulmainen (ei pyöristystä, pikselityyli),
# uudelleenkäytettävissä myös ui.gd:n yksittäisille popup-paneeleille.
static func panel_style_box(bg: Color, border: Color, border_w: int = 1, margin: float = 8.0) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_border_width_all(border_w)
	sb.border_color = border
	sb.set_corner_radius_all(0)
	sb.set_content_margin_all(margin)
	return sb


# 9-slice-paneelikehys isoille kontekstuaalisille paneeleille (trayt, popoverit):
# panel_frame.png, 48×48, kulmat pysyvät terävinä 12px-marginaaleilla. Palauttaa null jos
# assettia ei löydy (kutsuja käyttää silloin UiTheme.panel_style_box()-fallbackia).
static func panel_frame_style_box(margin: float = 12.0) -> StyleBoxTexture:
	if not ResourceLoader.exists(PANEL_FRAME_PATH):
		return null
	var tex := load(PANEL_FRAME_PATH) as Texture2D
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.set_content_margin_all(margin)
	return sb


# 9-slice-kehys yksittäisille napeille (actionbar-työkalunapit): button_frame.png, 24×24,
# marginaalit 8px. Pienissä (<40px) napeissa StyleBoxFlat voi näyttää siistimmältä —
# kutsuja päättää kummalla käyttötapaus toimii paremmin (ks. ui.gd toolbar-kommentit).
static func button_frame_style_box(margin: float = 8.0) -> StyleBoxTexture:
	if not ResourceLoader.exists(BUTTON_FRAME_PATH):
		return null
	var tex := load(BUTTON_FRAME_PATH) as Texture2D
	if tex == null:
		return null
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.texture_margin_left = margin
	sb.texture_margin_right = margin
	sb.texture_margin_top = margin
	sb.texture_margin_bottom = margin
	sb.set_content_margin_all(margin)
	return sb


static func _style_panel(theme: Theme) -> void:
	var panel := panel_style_box(COL_BG_PANEL, COL_BORDER_DIM, 1, 8.0)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)


static func _style_button(theme: Theme) -> void:
	var normal := panel_style_box(COL_BG_PANEL_LIGHT, COL_BORDER_DIM, 1, 6.0)
	var hover := panel_style_box(COL_BG_PANEL_LIGHT.lightened(0.1), COL_BORDER, 1, 6.0)
	var pressed := panel_style_box(COL_BORDER.darkened(0.35), COL_BORDER, 2, 6.0)
	var disabled := panel_style_box(COL_BG_PANEL, COL_BORDER_DIM.darkened(0.3), 1, 6.0)
	var focus := panel_style_box(Color(0.0, 0.0, 0.0, 0.0), COL_BORDER, 1, 6.0)

	theme.set_stylebox("normal", "Button", normal)
	theme.set_stylebox("hover", "Button", hover)
	theme.set_stylebox("pressed", "Button", pressed)
	theme.set_stylebox("disabled", "Button", disabled)
	theme.set_stylebox("focus", "Button", focus)

	theme.set_color("font_color", "Button", COL_TEXT)
	theme.set_color("font_hover_color", "Button", COL_ACTIVE)
	theme.set_color("font_pressed_color", "Button", COL_ACTIVE)
	theme.set_color("font_disabled_color", "Button", COL_TEXT_DIM)
	theme.set_font_size("font_size", "Button", 13)


static func _style_checkbox(theme: Theme) -> void:
	theme.set_color("font_color", "CheckBox", COL_TEXT)
	theme.set_color("font_hover_color", "CheckBox", COL_ACTIVE)
	theme.set_color("font_pressed_color", "CheckBox", COL_ACTIVE)
	theme.set_color("font_disabled_color", "CheckBox", COL_TEXT_DIM)
	theme.set_font_size("font_size", "CheckBox", 12)


static func _style_slider(theme: Theme) -> void:
	var groove := StyleBoxFlat.new()
	groove.bg_color = COL_BG_PANEL_LIGHT
	groove.set_corner_radius_all(0)
	groove.content_margin_top = 6.0
	groove.content_margin_bottom = 6.0
	theme.set_stylebox("slider", "HSlider", groove)

	var fill := StyleBoxFlat.new()
	fill.bg_color = COL_BORDER
	fill.set_corner_radius_all(0)
	fill.content_margin_top = 6.0
	fill.content_margin_bottom = 6.0
	theme.set_stylebox("grabber_area", "HSlider", fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", fill)


static func _style_tab_container(theme: Theme) -> void:
	var panel := panel_style_box(COL_BG_PANEL, COL_BORDER_DIM, 1, 8.0)
	theme.set_stylebox("panel", "TabContainer", panel)
	var tab_selected := panel_style_box(COL_BG_PANEL_LIGHT, COL_BORDER, 1, 6.0)
	var tab_unselected := panel_style_box(COL_BG_PANEL, COL_BORDER_DIM, 1, 6.0)
	theme.set_stylebox("tab_selected", "TabContainer", tab_selected)
	theme.set_stylebox("tab_unselected", "TabContainer", tab_unselected)
	theme.set_color("font_selected_color", "TabContainer", COL_ACTIVE)
	theme.set_color("font_unselected_color", "TabContainer", COL_TEXT_DIM)
	theme.set_font_size("font_size", "TabContainer", 13)


static func _style_tooltip(theme: Theme) -> void:
	var tip := panel_style_box(COL_BG_PANEL, COL_BORDER, 1, 6.0)
	theme.set_stylebox("panel", "TooltipPanel", tip)
	theme.set_color("font_color", "TooltipLabel", COL_TEXT)
	theme.set_font_size("font_size", "TooltipLabel", 12)


static func _style_label(theme: Theme) -> void:
	theme.set_color("font_color", "Label", COL_TEXT)
	theme.set_font_size("font_size", "Label", 13)
