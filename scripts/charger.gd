# Latauspaikan datamalli (M3 - SPEC_seed_ship). RefCounted-data jonka BotManager omistaa
# (bot_manager.chargers). Yksi Charger tarjoaa yhden tai useamman slotin (dokkauspisteen).
# coal_buffer antaa hiilibuustin (6x nopeampi lataus); tyhjana slotti lataa ilmaisella
# trickle-tahdilla. M4:n latausrivisto-moduuli kasvattaa slot_countia (CHARGER_BUILT_SLOTS).
# ASCII-only-kommentit (bottisim-tiedosto).
class_name Charger
extends RefCounted

var id: int = -1
var slot_count: int = 1
var slot_positions: Array[Vector2] = []   # sim-px per slotti (dokkauspiste)
var is_base: bool = false                  # basen sisaanrakennettu (ei purettavissa)
var coal_buffer: float = 0.0               # jaljella oleva buustattu latausyksikkomaara


# Latausnopeus slottia kohden: coal_buffer > 0 -> CHARGE_COAL, muuten CHARGE_TRICKLE.
func charge_rate() -> float:
	return BotManager.CHARGE_COAL if coal_buffer > 0.0 else BotManager.CHARGE_TRICKLE


# Syota hiilta puskuriin: 1 COAL px = COAL_UNITS_PER_PX buustattua latausyksikkoa.
func feed_coal(px: int) -> void:
	if px <= 0:
		return
	coal_buffer += float(px) * BotManager.COAL_UNITS_PER_PX


# Dokkauspiste slotille si. Palauttaa ensimmaisen positiot jos si on rajojen ulkopuolella;
# tyhja slot_positions -> ZERO (degeneroitunut testitapaus).
func slot_pos(si: int) -> Vector2:
	if si >= 0 and si < slot_positions.size():
		return slot_positions[si]
	if not slot_positions.is_empty():
		return slot_positions[0]
	return Vector2.ZERO
