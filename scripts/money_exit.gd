# MoneyExit — kaksoisroolissa.
#
# 1) Alkuperäinen rooli: itsenäinen intake-rakennus, joka kuluttaa aukosta
#    valuvat pikselit (update_exit palauttaa kulutetut mat->px; kutsuja
#    reitittää ne world.deposit_cargo():lla politiikan mukaan rahaksi tai
#    inventaarioon). Toimii liukuhihnaintegraationa — hihna tuo materiaalin
#    intake-aukolle.
# 2) Base-rooli (bottisimulaatio): sama instanssi toimii tehtaan basena.
#    - Haulerit purkavat kuormansa tänne (reititys world.deposit_cargo:ssa);
#      accept_cargo() on säilytetty arvonlaskuapurina (telemetria/testit).
#    - Bottien spawn-piste (spawn_pos) ja haulerin dump-lentokohde (intake_pos).
#    Molemmat roolit jakavat saman PRICES-hinnaston.
class_name MoneyExit
extends Node2D

const EXIT_W := 12
const EXIT_H := 10
const INTAKE_W := 6
const FLOOR_MAT := 3  # MAT_STONE
const DROP_HEIGHT := 12  # px basen intake-aukon ylapuolelle: hauler pudottaa tahan, pikselit putoavat intakeen

# Hinnat per pikseli — $/px, kontraktin mukaiset (GDD §4.1, §8 mapping).
# Kaikki tuntemattomat materiaalit → DEFAULT_PRICE. Jalostus nostaa arvoa.
# Sama taulu palvelee sekä update_exitiä (pikselinsyönti) että accept_cargoa (botit).
const PRICES := {
	0:  0,   # EMPTY    — ei mitään
	1:  1,   # SAND
	3:  1,   # STONE
	8:  1,   # ASH
	10: 3,   # GLASS
	11: 1,   # DIRT
	12: 3,   # IRON_ORE
	13: 5,   # GOLD_ORE
	14: 5,   # IRON
	15: 12,  # GOLD
	16: 2,   # COAL
	18: 1,   # GRAVEL
	20: 4,   # COPPER_ORE  (lane C lisaa worldgeniin)
	21: 8,   # RARE_EARTH  (lane C lisaa worldgeniin)
}
const DEFAULT_PRICE := 1  # Tuntematon materiaali: 1 $/px

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var intake_x: Array[int] = []
var total_earned: int = 0
# Vestigiaalinen telemetrialaskuri (M1 jalkeen $/s-mittari lukee pixel_worldin
# total_revenue-kenttaa; tama kasvaa enaa vain accept_cargo-apurikutsuista).
var earned_total: int = 0
var broken: bool = false
var _flash_timer: float = 0.0
var _label: Label

# Sprite — pixel_world antaa viitteen instansoinnin yhteydessä. null = fallback (vain flash).
var sprite_atlas: SpriteAtlas
# Tosi kun tämä instanssi on tehdasbase (world.base) — valitsee "base"-spriten "money_exit":n
# sijaan. Molemmat jakavat saman luokan (ks. tiedoston alun kaksoisrooli-kommentti).
var is_base: bool = false
var _last_anim_frame: int = -1  # viimeksi piirretty pulssi-frame; redraw vain kun tama muuttuu


func setup(center: Vector2i, base_role: bool = false) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST  # sprite teravana, ei sumea skaalaus
	is_base = base_role
	grid_pos = Vector2i(center.x - EXIT_W / 2, center.y - EXIT_H / 2)
	structure_pixels.clear()
	intake_x.clear()

	# Rakenne:
	# Rivi 0: reunat + intake-aukko (INTAKE_W px leveä, keskellä)
	# Rivit 1..H-2: täynnä
	# Rivi H-1: kiinteä alarivi (EI output-aukkoa)
	var intake_start := grid_pos.x + (EXIT_W - INTAKE_W) / 2

	for dx in EXIT_W:
		var px := grid_pos.x + dx
		var py := grid_pos.y
		if px < intake_start or px >= intake_start + INTAKE_W:
			structure_pixels.append(Vector2i(px, py))
		else:
			intake_x.append(px)

	for dy in range(1, EXIT_H - 1):
		for dx in EXIT_W:
			structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + dy))

	# Alarivi — täysin suljettu
	for dx in EXIT_W:
		structure_pixels.append(Vector2i(grid_pos.x + dx, grid_pos.y + EXIT_H - 1))

	position = Vector2.ZERO

	# Rahamäärä-label rakennuksen yläpuolelle
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 8)
	_label.add_theme_color_override("font_color", Color(0.2, 0.9, 0.3))
	_label.position = Vector2(float(grid_pos.x), float(grid_pos.y) - 10.0)
	_label.text = ""
	add_child(_label)

	queue_redraw()


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 100 + randi() % 30  # Vihertävä kivi


# M1 (SPEC_seed_ship §2.1): palauttaa taman framen kuluttamat intake-pikselit
# { mat_id:int -> px:int } (tyhja {} jos ei mitaan). EI enaa palauta rahaa — kutsuja
# (_update_money_exits) reitittaa tuloksen deposit_cargolla politiikan mukaan
# (SELL -> money+total_revenue, STORE -> inventory).
func update_exit(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> Dictionary:
	var consumed: Dictionary = {}

	# Skannaa intake-alue (rivi rakennuksen ylapuolella)
	var intake_y := grid_pos.y - 1
	if intake_y >= 0:
		for ix in intake_x:
			if ix >= 0 and ix < w:
				var idx := intake_y * w + ix
				var mat_id: int = grid[idx]
				if mat_id == 0:
					continue
				consumed[mat_id] = int(consumed.get(mat_id, 0)) + 1
				grid[idx] = 0
				color_seed[idx] = randi() % 256
				_flash_timer = 0.2
				queue_redraw()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		queue_redraw()

	# Hidas pulssianimaatio: redraw VAIN kun frame vaihtuu (2 Hz), ei joka frame (60 Hz).
	# _draw() paivittaa _last_anim_framen -> pulssi animoituu mutta ei nakuta redrawia turhaan.
	if sprite_atlas != null:
		var pulse := int(Time.get_ticks_msec() / 1000.0 * 2.0) % 2
		if pulse != _last_anim_frame:
			queue_redraw()

	# Label ei enaa naytettavaa rahalukua — inventaario/talous elaa pixel_world.gd:ssa.
	_label.text = ""
	return consumed


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


# --- Base-rooli (bottisimulaatio) ---

# Summaa kuorman rahallisen arvon PRICES-taulusta. Tuntematon materiaali → 1 $/px.
# EI muuta world.moneya eikä total_earnedia (label) — kutsuja lisää palautusarvon world.moneyyn.
# Kasvattaa vain earned_total-kumulatiivilaskuria (lane G: $/s-mittari). cargo: mat_id -> px.
func accept_cargo(cargo: Dictionary) -> int:
	var total: int = 0
	for mat_id in cargo:
		var amount: int = int(cargo[mat_id])
		if amount <= 0:
			continue
		var unit_price: int = PRICES.get(int(mat_id), DEFAULT_PRICE)
		total += unit_price * amount
	earned_total += total  # kumulatiivinen tulo (lane G laskee tasta $/s)
	return total


# Bottien spawn-piste: basen yläpuolella ~20 px, rakenteen keskilinjalla.
func spawn_pos() -> Vector2:
	return Vector2(float(grid_pos.x) + float(EXIT_W) * 0.5, float(grid_pos.y) - 20.0)


# Haulerin dump-lentokohde: basen intake-aukon YLAPUOLELLA (DROP_HEIGHT px), keskilinjalla.
# Hauler lentaa tahan ja pudottaa kuorman -> pikselit putoavat ilmassa intakeen.
func intake_pos() -> Vector2:
	return Vector2(float(grid_pos.x) + float(EXIT_W) * 0.5, float(grid_pos.y) - float(DROP_HEIGHT))


# Pudotussarakkeet = intake-aukon x-koordinaatit. Hauler kirjoittaa kuorman naihin sarakkeisiin
# basen ylapuolelle -> pikselit putoavat suoraan intakeen (ei valu kiintealle olalle).
func drop_columns() -> Array[int]:
	return intake_x


# Rivi jolta hauler aloittaa pudotuksen (intake-aukon ylapuolella, DROP_HEIGHT px).
func drop_start_y() -> int:
	return grid_pos.y - DROP_HEIGHT


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Sprite ENSIN (flash-hehku piirtyy sen päälle). Kaksoisrooli: base-instanssi käyttää
	# "base"-spriteä, tavallinen myyntipiste "money_exit"-spriteä. Molemmilla hidas pulssi.
	if sprite_atlas != null:
		var sprite_name := "base" if is_base else "money_exit"
		var frame := int(Time.get_ticks_msec() / 1000.0 * 2.0) % 2
		_last_anim_frame = frame
		var tex := sprite_atlas.tex(sprite_name, frame)
		if tex:
			draw_texture(tex, Vector2(grid_pos))
	# Hehku kun raha tulee sisään
	if _flash_timer > 0.0:
		draw_rect(
			Rect2(float(grid_pos.x + 1), float(grid_pos.y + 1),
				float(EXIT_W - 2), float(EXIT_H - 2)),
			Color(0.2, 1.0, 0.3, _flash_timer * 3.0)
		)
