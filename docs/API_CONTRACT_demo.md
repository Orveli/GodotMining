# API-kontrakti — Demo (UI ↔ pelilogiikka)

**Sitova rajapinta lane-agenttien välillä.** Lane B (UI) kutsuu VAIN näitä metodeja —
ei suoraan bottien/koneiden sisuksia. Lane A ja D toteuttavat nämä signatuurit.
Muutokset tähän tiedostoon vain orkestroijan kautta.

## BotManager (`scripts/bot_manager.gd` — lane A toteuttaa)

```gdscript
func buy_bot(role: int) -> bool
    # Tarkistaa next_bot_price() <= world.money, vähentää rahan,
    # spawnaa botin world.base.spawn_pos():iin. true jos onnistui.
func next_bot_price() -> int
    # 300 * 1.5^(ostettujen bottien määrä), pyöristetty alas 10:een.
    # Aloitusbotit (2 kpl) eivät kasvata kerrointa.
func set_role(bot_id: int, new_role: int) -> void
    # Keskeyttää työn siististi: CLAIMED/MINING-designaatio -> QUEUED,
    # cargo dumpataan baseen ennen vaihtoa (tai heti jos tyhjä).
func upgrade_bot(bot_id: int) -> bool
    # Mk1->Mk2 400, Mk2->Mk3 900. false jos ei varaa tai jo Mk3.
func upgrade_price(bot_id: int) -> int   # 0 jos Mk3
func get_fleet_stats() -> Dictionary
    # { "miners": int, "haulers": int, "miners_active": int, "haulers_active": int,
    #   "bots": [ {"id": int, "role": int, "tier": int, "state": int} ] }
func bot_count() -> int
```

## Logistics (`scripts/logistics.gd` — UUSI, lane A toteuttaa)

```gdscript
func add_pickup_point(rect: Rect2i, filter_mask: int, priority: int = 0) -> int  # id
func add_dump_point(rect: Rect2i, filter_mask: int) -> int                       # id
func remove_zone(id: int) -> void
func set_zone_filter(id: int, filter_mask: int) -> void
func set_base_filter(filter_mask: int) -> void   # 0 = kaikki kelpaa (oletus)
func get_zones() -> Array  # [ {"id", "type": "pickup"|"dump", "rect", "filter_mask", "priority"} ]
```

`filter_mask`: bittimaski, bitti = materiaali-ID (`1 << mat_id`). 0 = ei rajausta.
Hauler valitsee dumpin joka hyväksyy suurimman osan kuormasta ja on lähinnä (GDD §4.2).
Koneiden input-dumpit rekisteröidään logisticsiin `get_input_dump()`-datalla (lane G kytkee).

## Koneet (`furnace.gd`, `crusher.gd` — lane D toteuttaa)

```gdscript
func get_input_dump() -> Dictionary   # { "rect": Rect2i, "filter_mask": int }  reseptin inputit
func get_intake_center() -> Vector2i  # furnace: UUSI; crusher: on jo
func get_output_center() -> Vector2i  # furnace: UUSI; crusher: on jo
```

## PixelWorld (`pixel_world.gd` — lane G kytkee, UI kutsuu)

```gdscript
func try_buy_building(build_type: int) -> bool
    # can_afford-tarkistus + money -= BUILDING_COSTS[build_type]. UI kutsuu ENNEN sijoitustilaa;
    # peruutus (Esc/oikea hiiri) palauttaa rahan.
func set_designation_tool_mode(mode: int) -> void   # 0=pensseli, 1=laatikkoveto, 2=yksittäissolu
var money: int              # olemassa
var income_per_s: float     # UUSI: 10 s liukuva keskiarvo tuloista
signal milestone(text: String)   # tier-välitavoite-toastit (G triggaa, B näyttää)
signal demo_complete()
```

## Hinnat (yksi totuus — `money_exit.gd` PRICES + nämä vakiot)

| Tuote | Hinta |
|---|---|
| Botti | 300 × 1,5^n (n = ostetut) |
| Mk2-upgrade | 400 / botti |
| Mk3-upgrade | 900 / botti |
| Hihna | 50 |
| Furnace | 150 |
| Crusher | 120 |
| Pickup-point | 80 |
| Dump-point | 60 |
| Lamppu | 40 |

Myynti palauttaa 50 %. Materiaalihinnat: money_exit.gd PRICES (+ COPPER_ORE 4, RARE_EARTH_ORE 8 — lane C lisää).
