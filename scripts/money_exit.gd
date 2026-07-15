# MoneyExit — kaksoisroolissa.
#
# 1) Alkuperäinen rooli (säilyy): itsenäinen "kassa"-rakennus, joka syö
#    intake-aukosta valuvat pikselit rahaksi (update_exit). Toimii jatkossa
#    liukuhihnaintegraationa — hihna tuo materiaalin intake-aukolle.
# 2) Base-rooli (bottisimulaatio): sama instanssi toimii tehtaan basena.
#    - Haulerit purkavat kuormansa tänne → accept_cargo() summaa arvon
#      PRICES-taulusta (kutsuja lisää tuloksen world.moneyyn).
#    - Bottien spawn-piste (spawn_pos) ja haulerin dump-lentokohde (intake_pos).
#    Molemmat roolit jakavat saman PRICES-hinnaston.
class_name MoneyExit
extends Node2D

const EXIT_W := 12
const EXIT_H := 10
const INTAKE_W := 6
const FLOOR_MAT := 3  # MAT_STONE

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
}
const DEFAULT_PRICE := 1  # Tuntematon materiaali: 1 $/px

var grid_pos: Vector2i = Vector2i.ZERO
var structure_pixels: Array[Vector2i] = []
var intake_x: Array[int] = []
var total_earned: int = 0
var broken: bool = false
var _flash_timer: float = 0.0
var _label: Label


func setup(center: Vector2i) -> void:
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
	_label.text = "$0"
	add_child(_label)

	queue_redraw()


func build_structure(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int) -> void:
	for sp in structure_pixels:
		if sp.x >= 0 and sp.x < w and sp.y >= 0 and sp.y < h:
			var idx := sp.y * w + sp.x
			grid[idx] = FLOOR_MAT
			color_seed[idx] = 100 + randi() % 30  # Vihertävä kivi


func update_exit(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> int:
	var frame_earnings: int = 0

	# Skannaa intake-alue (rivi rakennuksen yläpuolella)
	var intake_y := grid_pos.y - 1
	if intake_y >= 0:
		for ix in intake_x:
			if ix >= 0 and ix < w:
				var idx := intake_y * w + ix
				var mat_id: int = grid[idx]
				if mat_id == 0:
					continue
				var earned: int = PRICES.get(mat_id, DEFAULT_PRICE)
				frame_earnings += earned
				total_earned += earned
				grid[idx] = 0
				color_seed[idx] = randi() % 256
				_flash_timer = 0.2
				queue_redraw()

	if _flash_timer > 0.0:
		_flash_timer -= delta
		queue_redraw()

	_label.text = "$%d" % total_earned
	return frame_earnings


func get_structure_pixels() -> Array[Vector2i]:
	return structure_pixels


# --- Base-rooli (bottisimulaatio) ---

# Summaa kuorman rahallisen arvon PRICES-taulusta. Tuntematon materiaali → 1 $/px.
# EI muuta world-tilaa eikä total_earnedia — kutsuja lisää palautusarvon world.moneyyn.
# cargo: mat_id (int) -> pikselimäärä (int).
func accept_cargo(cargo: Dictionary) -> int:
	var total: int = 0
	for mat_id in cargo:
		var amount: int = int(cargo[mat_id])
		if amount <= 0:
			continue
		var unit_price: int = PRICES.get(int(mat_id), DEFAULT_PRICE)
		total += unit_price * amount
	return total


# Bottien spawn-piste: basen yläpuolella ~20 px, rakenteen keskilinjalla.
func spawn_pos() -> Vector2:
	return Vector2(float(grid_pos.x) + float(EXIT_W) * 0.5, float(grid_pos.y) - 20.0)


# Haulerin dump-lentokohde: basen yläreunan keskikohta (intake-aukon kohdalla).
func intake_pos() -> Vector2:
	return Vector2(float(grid_pos.x) + float(EXIT_W) * 0.5, float(grid_pos.y))


func _draw() -> void:
	if structure_pixels.is_empty():
		return
	# Hehku kun raha tulee sisään
	if _flash_timer > 0.0:
		draw_rect(
			Rect2(float(grid_pos.x + 1), float(grid_pos.y + 1),
				float(EXIT_W - 2), float(EXIT_H - 2)),
			Color(0.2, 1.0, 0.3, _flash_timer * 3.0)
		)
