# SPEC: Seed Ship — itsereplikoituva von Neumann -parvi

**Versio:** 1.0 · **Laatija:** game-architect · **Tila:** toteutettavaksi (M1–M5)
**Kohde:** 5 peräkkäistä Opus-ohjelmoija-agenttia. Jokainen moduuli (M1–M5) on itsenäisesti
toteutettava ja testattava. Lue tämä koko dokumentti ennen oman moduulisi aloittamista, mutta
toteuta VAIN oman moduulisi osuus. Moduulien väliset sopimukset ovat luvussa 5 — älä riko niitä.

> **Tyyliohje kaikille moduuleille:** noudata KUNKIN tiedoston olemassa olevaa kommenttityyliä.
> Bottisim-tiedostot (`bot.gd`, `bot_manager.gd`, `logistics.gd`, `money_exit.gd`,
> `designation_grid.gd`, uudet `charger.gd`/`base_modules.gd`) ovat **ASCII-only** (ei ääkkösiä
> kommenteissa). `pixel_world.gd`, `ui.gd`, `world_gen.gd` käyttävät ä/ö:tä — jatka samalla tyylillä
> niissä. Tyyppivihjeet aina, snake_case, `UPPER_CASE` vakiot, signaalit `.connect()`:lla.

---

## 1. Visio ja pelaajakokemus

Pelaaja EI ole hahmo vaan **von Neumann -luotainparvi**, joka laskeutuu planeetalle, louhii
raaka-ainetta, **replikoi itseään** raaka-aineesta ja **kasvattaa emoalusta** (base) moduuli
kerrallaan. Dyson-lore on kevyt kehys — EI vihollisia, EI taistelua tässä vaiheessa. Ydintunne:
"pieni siemen kasvaa itseään ruokkivaksi koneistoksi".

Talouden ydinmuutos: **materiaali on ensisijainen resurssi, raha toissijainen.** Boteilta baseen
tuotu materiaali menee **inventaarioon** (mat_id → px). Inventaariosta rakennetaan (botit,
latauspaikat, moduulit) tai myydään (→ raha → unlockit/upgradet säilyvät rahapohjaisina).

### Ensimmäiset ~10 minuuttia (kokenut pelaaja, nopea startti)

| Aika | Tapahtuma |
|---|---|
| 0:00 | Title-ruutu. Klik → kapseli putoaa taivaalta (falling sand: pöly + sora), laskeutuu alustalle, aukeaa, 2 bottia ulos. Klik skippaa intron heti. |
| 0:05 | Designaatiotila on jo PÄÄLLÄ. Pelaaja vetää kaivuualueen alustan viereen näkyvälle rautasuonelle (M5 takaa suonen pintaan). |
| 0:20 | Miner louhii rautaa, hauler tuo baseen → **inventaarioon** kertyy IRON_ORE. Roska (gravel/multa) myydään automaattisesti → raha alkaa nousta. |
| 0:45 | Inventaariossa ~10 IRON_ORE → base-napin "Rakenna botti" hehkuu → **eka replikaatio** (< 1 min). |
| 1:30 | 4. botti → yksi latauspaikka ei riitä → **latausjono** syntyy (botit odottavat vuoroa, työ hidastuu). Base-kylkeen ilmestyy haamu: **latausrivistö** (täyttötarve 30 IRON_ORE). |
| 2:30 | Latausrivistö rakentuu (botit/pelaaja täyttävät haamun) → jono purkautuu. |
| 3:30 | Täysi looppi rullaa: louhi → replikoi → lataa → laajenna. Seuraava haamu (jalostamo-liitäntä) näkyvissä. |
| 5:00–10:00 | Jalostamo-unlock (furnace/crusher näkyviin), syvemmät suonet (COPPER/RARE_EARTH), moduuliketju etenee. |

**Kaikki onboarding-triggerit ovat toiminta-/resurssipohjaisia, EIVÄT aikapohjaisia.** Kokenut
pelaaja saa täyden loopin käyntiin ~3–4 minuutissa; hidas pelaaja etenee samat virstat omaan tahtiin.

---

## 2. Talousmalli

### 2.1 Inventaario-datamalli

Inventaario elää **`pixel_world.gd`:ssä** (talouden keskussolmu: `money`, ScenarioRunner ja
build/sell-polut ovat jo siellä). MoneyExit (base) pysyy "rakenne + intake-mekanismi" -roolissa.

```gdscript
# pixel_world.gd (uudet kentat, money:n (rivi 254) viereen)
var inventory: Dictionary = {}          # mat_id (int) -> px-maara (int). Vain STORE-materiaalit kertyvat.
var material_policy: Dictionary = {}    # mat_id (int) -> POLICY_SELL | POLICY_STORE
var total_revenue: int = 0              # kumulatiivinen myyntitulo (income-mittari lukee tata)
const POLICY_SELL := 0                  # materiaali myydaan heti saapuessa (-> money)
const POLICY_STORE := 1                 # materiaali varastoidaan inventaarioon (-> rakentaminen)
```

**Politiikka jakaa intake-virran saapumishetkellä** (ei erillistä periodista skannausta):
- **STORE**-materiaali → `inventory[mat] += px`.
- **SELL**-materiaali → `money += PRICES[mat] * px`, `total_revenue += arvo` (täsmälleen nykyinen
  "raha nousee kun saalis tulee" -käytös).

**Oletuspolitiikat** (asetetaan `_init_bot_sim()`:ssä):

| Materiaali | Oletus | Perustelu |
|---|---|---|
| IRON_ORE (12) | STORE | Ensisijainen rakennusaine (botit, moduulit) |
| COPPER (20) | STORE | Syvempi rakennus-/moduuliaine |
| RARE_EARTH (21) | STORE | Harvinaisin rakennusaine (myydään premium-hintaan tai varastoon) |
| COAL (16) | STORE | Latauspaikkojen polttoaine (M3) |
| Kaikki muu (GRAVEL, DIRT, SAND, STONE, GOLD_ORE, GOLD, ASH, GLASS…) | SELL | Roska/rahavirta — pitaa demo-kaaren rahamittarit elossa |

Pelaaja kääntää politiikan base-popoverissa (2.2). Näin "inventaariolla on kaksi ulostuloa"
toteutuu konkreettisena pelaajan hallitsemana valintana, ilman klikkispämmiä ja demo-kaarta rikkomatta.

### 2.2 Myyntiflow

**Ratkaisu: hybridi — automaattinen politiikka (2.1) + manuaalinen myynti base-popoverissa.**
(Vaihtoehdot olivat: pelkkä auto-myynti filtterillä, tai pelkkä manuaalinen nappi. Hybridi valittu,
koska se säilyttää selkeän "rakenna vs. myy" -jännitteen: rakennusaineet **varastoituvat**
oletuksena, roska **myydään** oletuksena, ja pelaaja voi kääntää kummankin.)

Base-popover (`world_object_clicked` "base" → `ui.gd`) näyttää:
- **Inventaariolista:** per varastoitu materiaali: ikoni + px-määrä + $-arvo (`PRICES`).
- Per rivi: **[Myy]** (kertaluontoinen likvidointi: `sell_from_inventory(mat)`), ja
  **[Varastoi]/[Myy autom.]** -kytkin (asettaa `material_policy`).
- **[Myy kaikki ylijäämä]** -nappi (`sell_all_surplus()`).

**API (M1 toteuttaa, pixel_world.gd):**

```gdscript
func deposit_material(mat_id: int, px: int) -> void        # reitittaa policyn mukaan (SELL->money, STORE->inventory)
func deposit_cargo(cargo: Dictionary) -> void              # loop deposit_material; bot_managerin fallback-purku kayttaa
func sell_from_inventory(mat_id: int, px: int = -1) -> int # px<0 = kaikki; poistaa inventoryst, money+=arvo, total_revenue+=arvo, palauttaa arvon
func sell_all_surplus() -> int                             # myy koko inventoryn (kaikki materiaalit), palauttaa kokonaisarvon
func inventory_amount(mat_id: int) -> int                  # inventory.get(mat_id, 0)
func inventory_total_value() -> int                        # summa PRICES*px yli inventoryn
func set_material_policy(mat_id: int, policy: int) -> void
func can_afford_materials(recipe: Dictionary) -> bool      # recipe: mat_id -> px; true jos inventory kattaa
func spend_materials(recipe: Dictionary) -> bool           # tarkistaa + vahentaa inventoryst atomisesti; false jos ei kata
```

### 2.3 Resurssigraafi

```
                              +--> [SELL policy]  --> money --> unlockit / tier-upgradet (rahapohjaiset, SAILYY)
                              |                                --> furnace/crusher-rakennus (rahapohjainen, SAILYY)
  louhinta -> hauler -> base -+
   (miner)   (dump)   intake  |
                              +--> [STORE policy] --> inventory --> build_bot (M2, IRON_ORE)
                                                                --> build_charger (M3, IRON_ORE + COAL-polttoaine)
                                                                --> haamumoduulit (M4, IRON_ORE/COPPER/STONE)
                                                                --> (manuaalinen sell_from_inventory -> money)
```

- **Rakennusvaluutta (STORE):** IRON_ORE ensisijainen; COPPER/RARE_EARTH syvemmät moduulit; COAL
  polttoaine latauspaikoille.
- **Rahavaluutta (SELL):** kaikki roska auto-myynnillä + varastoidun ylijäämän manuaalimyynti.
  Raha säilyy unlockeja, tier-upgradeja (`upgrade_bot`) ja jalostuskoneiden (furnace/crusher/conveyor)
  ostoa varten — **rahatalous SÄILYY, inventaario tulee sen ETEEN.**

### 2.4 Tuning-vakiot (lähtöarvot — mitoitettu mine_rate=80 px/s, carry_cap=40 px vasten)

**Bottihinta-progressio (M2):** `next_bot_cost(n)` missä n = jo rakennettujen bottien määrä
(aloitus-2 EI laske). Resepti on pelkkää IRON_ORE:a.

| n (rakennettu) | IRON_ORE px | Huom |
|---|---|---|
| 0 (3. botti) | 10 | < 1 hauler-lasti (40 px) → eka replikaatio < 1 min |
| 1 | 14 | |
| 2 | 19 | jono-ongelma syntyy ~tässä (4. botti kentällä) |
| 3 | 26 | |
| 4 | 35 | |
| 5 | 47 | |

Kaava: `cost_px = int(ceil(10.0 * pow(1.35, n)))`. Kasvu loiva jotta lauma skaalautuu, mutta
kalliimpi kuin rahamalli — pitää replikaation resurssisidonnaisena.

**Akku + lataus (M3):** akkuyksikkö = "työsekunti".

| Vakio | Arvo | Merkitys |
|---|---|---|
| `BATTERY_MAX` | 90.0 | täysi akku = 90 s työtä |
| `BATTERY_DRAIN` | 1.0 /s | hupenee VAIN WORK- ja DUMP-tilassa (ei liikkeesta/idlestä) |
| `BATTERY_SEEK` | 18.0 | (20 %) → botti hakeutuu lataukseen kun akku alle tämän |
| `BATTERY_FULL_ENOUGH` | 85.0 | lataus loppuu kun akku >= tämä (estää thrashing) |
| `CHARGE_TRICKLE` | 1.5 /s | ilmainen trickle → täysi lataus ~60 s |
| `CHARGE_COAL` | 9.0 /s | hiilibuusti (6×) → täysi lataus ~10 s |
| `COAL_UNITS_PER_PX` | 30.0 | 1 COAL px = 30 latausyksikköä buustattua latausta |
| `CHARGER_BASE_SLOTS` | 1 | basen sisäänrakennettu latauspaikka |
| `CHARGER_BUILT_SLOTS` | 2 | rakennettava latausrivistö-moduuli (M4) lisää slotit |

Mitoituksen todiste: työ 90 s + trickle-lataus 60 s = 150 s sykli → 1 paikka palvelee 150/60 ≈
**2,5 bottia ilmaiseksi**. Hiilellä 90 s + 10 s = 100 s sykli → 100/10 = **10 bottia**. ✓

**Moduulihinnat (M4):** täyttötarve (inventaariosta / haulerien tuomana).

| Moduuli | Täyttö | Trigger (progressive disclosure) | Unlock |
|---|---|---|---|
| Latausrivistö | 30 IRON_ORE | botti käynyt WAITING_CHARGER-tilassa TAI fleet ≥ 4 | +2 latausslottia |
| Jalostamo-liitäntä | 40 IRON_ORE + 20 COAL | latausrivistö valmis JA inventory piti joskus ≥ 40 IRON_ORE | furnace + crusher build-trayhin |
| Varastosiilo (valinn.) | 60 STONE tai GRAVEL | jalostamo valmis | +10 % myyntiarvo TAI inventory-selkeys |

### 2.5 Tunnettu epäjohdonmukaisuus (korjaa migraatiossa)

`bot_manager.next_bot_price()` (rivi 219–220) on **oikeasti** `25 * 1.25^n`, mutta usea kommentti
ja skenaario (`bot.gd` rivi ~30, `pixel_world.gd` START_MONEY-kommentti rivi 276, `deep_ore_sale.json`
"300+450+675", `bot_buy.json` "300 * 1.5^n") viittaa vanhentuneeseen `300 * 1.5^n` -hintaan. M2 poistaa
rahapohjaisen `buy_bot`in kokonaan → korjaa/poista nämä stale-kommentit samalla.

---

## 3. Moduulispeksit M1–M5

### M1 — Base-inventaario + talousremontti

**Tavoite:** intake-materiaali → inventaario (mat_id → px) rahan sijaan; politiikkapohjainen
auto-myynti + manuaalimyynti; koko myöhempien moduulien resurssi-API.

**Muutettavat tiedostot:**
- `scripts/pixel_world.gd` — inventaario-kentät ja API (2.1–2.2), `_update_money_exits` (rivi 3350),
  `_update_income` (rivi 1748), `_init_bot_sim` (rivi 1545, oletuspolitiikat + nollaus), ScenarioRunner
  (uudet komennot, luku 4), `_get_debug_state`/`game_state`-dumppi jos inventory halutaan näkyviin.
- `scripts/money_exit.gd` — `update_exit()` (rivi 101) EI enää palauta rahaa vaan kuluttamansa
  pikselit; `accept_cargo()` (rivi 139) jää arvonlaskuapuriksi (ei enää kytketty rahaan).
- `scripts/bot_manager.gd` — fallback-purkupolut: `set_role` (rivi 248–249) ja
  `_sell_remaining_cargo` (rivi 908–913): korvaa `world.money += world.base.accept_cargo(...)` →
  `world.deposit_cargo(b.cargo)`.
- `scripts/ui.gd` — base-popover: inventaariolista + myyntinapit + politiikkakytkin.

**API-muutokset (tarkat signatuurit):**

```gdscript
# money_exit.gd — muutettu paluutyyppi (int -> Dictionary)
# Palauttaa taman framen kuluttamat intake-pikselit { mat_id:int -> px:int } (tyhja {} jos ei mitaan).
# EI enaa palauta rahaa. total_earned/earned_total-laskurit voi poistaa tai jattaa telemetriaksi;
# _label naytto vaihtuu (ks. alla).
func update_exit(grid: PackedByteArray, color_seed: PackedByteArray, w: int, h: int, delta: float) -> Dictionary
```

```gdscript
# pixel_world.gd — _update_money_exits (rivi 3350) uusi runko
func _update_money_exits(delta: float) -> bool:
    var modified := false
    var alive: Array = []
    for me in money_exits:
        var consumed: Dictionary = me.update_exit(grid, color_seed, W, SIM_HEIGHT, delta)
        if not consumed.is_empty():
            deposit_cargo(consumed)   # reitittaa policyn mukaan (SELL->money+total_revenue, STORE->inventory)
            modified = true
        if me.broken:
            _unregister_building_pixels(me.structure_pixels)
            me.queue_free()
        else:
            alive.append(me)
    money_exits = alive
    return modified
```

**Income-mittari:** `_update_income` (rivi 1748) laskee nyt `money_exit.earned_total`-summan deltaa.
Vaihda lähde: käytä `total_revenue`-kenttää (kasvaa vain myynneistä, ei koskaan pienene → sama
negatiivi-clamp-logiikka toimii). Näin `$/s` mittaa oikeaa myyntituloa, ei intake-volyymiä.

**MoneyExit-label:** `_label` näytti `"$%d"` (total_earned). Vaihda näyttämään joko tyhjää/piilotettu
tai "kertyy"-indikaattori. Älä poista `_label`-solmua kaatamatta `setup()`:ia — riittää `_label.text = ""`.

**UI-muutokset:** base-popover (`ui.gd`, `world_object_clicked` "base" -haara). Jos base-popoveria ei
vielä ole erikseen, lisää se: näyttää inventaariorivit (`pixel_world.inventory`), myyntinapit ja
politiikkakytkimet. Käytä olemassa olevaa amber-teemaa ja popover-rakennetta.

**MIKÄ SÄILYY ENNALLAAN:** GPU-sim, CA, fysiikka, hihnat, furnace/crusher/conveyor, `mvp_write_pixel`,
`building_pixels`, `_drop_cargo_above_base`/`_deposit_cargo_to_zone` (nämä kirjoittavat pikseleitä —
base-dropoffin fyysinen pudotus intakeen on edelleen pääpolku, update_exit vain reitittää tuloksen
inventaarioon), Logistics-vyöhykkeet, base-dropoff-filtteri (`is_base_dropoff`), designaatio, nav.

**Testisuunnitelma:**
- **Päivitä** `tests/unit/test_money_exit.gd`: `update_exit` palauttaa nyt Dictionaryn (ei intiä).
  `accept_cargo` säilyy arvonlaskurina (assertit voivat jäädä).
- **Uusi** `tests/unit/test_inventory.gd` (extends SceneTree): testaa `deposit_material` (SELL vs
  STORE), `spend_materials` (riittävä/riittämätön), `sell_from_inventory`, `can_afford_materials`.
- **Uudet skenaariokomennot** (luku 4) testattavissa `tests/scenarios/inventory_flow.json`:lla.

**Riskit:** (1) `update_exit`-paluutyypin muutos rikkoo kaikki kutsujat — grep `update_exit` (vain
`_update_money_exits`). (2) `accept_cargo`-irrotus rahasta: varmista että set_role/watchdog-purku ei
enää tuplaa rahaa. (3) income-mittarin lähteen vaihto: älä jätä `earned_total`-summaa roikkumaan.

---

### M2 — Bottireplikaatio materiaaleista

**Tavoite:** botit rakennetaan inventaarion IRON_ORE:sta rahan sijaan; kasvava resepti; base-napin
hehku kun varaa on.

**Muutettavat tiedostot:**
- `scripts/bot_manager.gd` — `next_bot_price` (rivi 219) → `next_bot_cost`; `buy_bot` (rivi 225) →
  `build_bot`; `_bought_count` (rivi 134) säilyy laskurina.
- `scripts/ui.gd` — `_bot_price` (rivi 1108) / `_buy_bot` (rivi 1115) → materiaalipohjaiset;
  bot-tray/base-nappi hehkuu kun `can_build_bot()`.
- `scripts/pixel_world.gd` — ScenarioRunner `buy_bot`-komento (rivi 4726) → `build_bot` +
  inventaarion siemenkomento (luku 4).

**API-muutokset:**

```gdscript
# bot_manager.gd
# Seuraavan botin resepti: { MAT_IRON_ORE: int }. _bought_count kasvattaa hintaa.
func next_bot_cost() -> Dictionary:
    var px := int(ceil(10.0 * pow(1.35, float(_bought_count))))
    return { MAT_IRON_ORE: px }

# Onko varaa rakentaa (world.inventory kattaa reseptin)?
func can_build_bot() -> bool:
    if world == null:
        return false
    return world.can_afford_materials(next_bot_cost())

# Rakenna botti: kuluta materiaalit inventaariosta, spawnaa basesta. Korvaa buy_bot(raha).
func build_bot(role: int) -> bool:
    if world == null or world.base == null or not is_instance_valid(world.base):
        return false
    if not world.spend_materials(next_bot_cost()):
        return false
    _bought_count += 1
    add_bot(role, world.base.spawn_pos())
    return true
```

**Poista** `next_bot_price()` ja `buy_bot()` (money). Päivitä kaikki kutsujat: `ui.gd` (`_bot_price`
→ näyttää reseptin px-määrän; `_buy_bot` → `build_bot`), ScenarioRunner.

**UI-muutokset:** bot-trayn osto-item ja/tai base-popover näyttää reseptin ("10 rautaa") ja **hehkuu
(amber-glow) kun `can_build_bot()` on tosi.** `_can_afford`-rahalogiikka vaihtuu `can_build_bot()`:iin.
Jos ei varaa → toast "Ei tarpeeksi rautaa (tarvitaan N)".

**MIKÄ SÄILYY ENNALLAAN:** `add_bot`, `set_role`, `upgrade_bot`/`upgrade_price` (tier-upgradet
pysyvät RAHAPOHJAISINA), aloituslauma (`_init_bot_sim` spawnaa yhä 1 miner + 1 hauler), fleet-stats,
ruuhkanhallinta.

**Testisuunnitelma:**
- **Päivitä** `tests/scenarios/bot_buy.json`: `set_money` → `set_inventory {mat:12, px:...}`;
  `buy_bot` → `build_bot`; assertit `assert_money_*` → `assert_inventory`/`assert_fleet`.
- **Päivitä** `tests/unit/test_bot_manager.gd`: jos se testaa `buy_bot`/`next_bot_price`, vaihda
  `build_bot`/`next_bot_cost` + inventaarion siementä varten aja world-stubin kautta.

**Riskit:** (1) `_bm()`-viittaukset ui.gd:ssä. (2) headless-testit: `build_bot` vaatii
`world.inventory` täytetyksi ensin (`set_inventory`-komento). (3) demo-kaari `_update_demo_arc` rivi
1781 (`bot_count() > 2`) toimii yhä.

---

### M3 — Akku + latauspaikat

**Tavoite:** boteilla akku joka hupenee työstä; botti hakeutuu itse lataukseen; base = 1
sisäänrakennettu paikka; rakennettava latauspaikka; trickle ilmainen/hidas, COAL-syöttö 6×; jono =
pehmeä cap (odota vuoroa, EI kuolemaa/deadlockia).

**Muutettavat + uudet tiedostot:**
- **UUSI** `scripts/charger.gd` (`class_name Charger extends RefCounted`) — latauspaikan data:
  slotit, sijainti, coal_buffer, lataustila.
- `scripts/bot.gd` — akkukenttä + 2 uutta tilaa.
- `scripts/bot_manager.gd` — akun kuluminen, latauspäätös, latauksen tilakoneet, charger-rekisteri,
  slot-varaus, idle-syyt (CHARGING/WAITING_CHARGER).
- `scripts/pixel_world.gd` — base-charger luonti `_init_bot_sim`:ssä; `_collect_light_emitters` (rivi
  1167) lisää chargerit emittereiksi; ScenarioRunner `set_battery`/`add_charger`/`feed_coal`.
- `scripts/ui.gd` — latauspaikka-popover (COAL-syöttö), akun tila bot-overlayssa.

**Bot-datamalli (`bot.gd`):**

```gdscript
enum BotState { IDLE, MOVE, WORK, CARRY_MOVE, DUMP, SEEK_CHARGE, CHARGING }
# HUOM: SEEK_CHARGE=5, CHARGING=6 LISATAAN LOPPUUN. Ala muuta 0-4 numerointia
# (skenaariot/UI/testit viittaavat niihin).

const BATTERY_MAX := 90.0
var battery: float = BATTERY_MAX
var charger_slot: int = -1       # varattu latausslotin globaali indeksi; -1 = ei varausta
```

**Charger-datamalli (`charger.gd`):**

```gdscript
class_name Charger
extends RefCounted

var id: int = -1
var slot_count: int = 1
var slot_positions: Array[Vector2] = []   # sim-px per slotti (dokkauspiste)
var is_base: bool = false                  # basen sisaanrakennettu (ei purettavissa)
var coal_buffer: float = 0.0               # jaljella oleva buustattu latausyksikkomaara
# Latausnopeus slottia kohden: coal_buffer>0 -> CHARGE_COAL, muuten CHARGE_TRICKLE.
func charge_rate() -> float:
    return BotManager.CHARGE_COAL if coal_buffer > 0.0 else BotManager.CHARGE_TRICKLE
func feed_coal(px: int) -> void:
    coal_buffer += float(px) * BotManager.COAL_UNITS_PER_PX
```

**Tilakone (`bot_manager.gd`):**
- **Akun kuluminen** `_update_bot`:ssa (rivi 776): `if b.state == WORK or b.state == DUMP: b.battery
  = maxf(0.0, b.battery - BATTERY_DRAIN * delta)`.
- **Latauspäätös:** tyonjaon (`_run_assignment`, rivi 501) IDLE-käsittelyssä JA työn valmistuessa
  (`_finish_mining`/`_finish_dump`): `if b.battery <= BATTERY_SEEK: _seek_charge(b); continue`.
  Näin botti lopettaa nykyisen työn normaalisti ja vasta sitten hakeutuu — ei jätä kuormaa/solua
  roikkumaan (miner: designaatio vapautuu kuten roolinvaihdossa; hauler: purkaa kuorman ensin).
- **`_seek_charge(b)`:** valitse lähin charger jolla on vapaa slotti → varaa slotti
  (`b.charger_slot`), reititä dokkauspisteeseen, `SEEK_CHARGE`. Jos yksikään slotti ei ole vapaa →
  jää IDLEen basen lähelle, idle_reason = WAITING_CHARGER (pehmeä cap, ei deadlock; yritetään joka
  tyonjakokierros uudelleen).
- **`_st_seek_charge`:** `_follow_path`; perillä → `CHARGING`.
- **`_st_charging`:** `b.battery += charger.charge_rate() * delta`; kuluta coal_buffer vastaavasti
  (`charger.coal_buffer = maxf(0, coal_buffer - (rate-CHARGE_TRICKLE)*delta*...)` — ks. mitoitus);
  kun `b.battery >= BATTERY_FULL_ENOUGH` → vapauta slotti, `IDLE`, `_run_assignment` hakee työn.
- **Slot-varaus:** JOHDA slot-miehitys bottien tilasta joka tyonjakokierros (sama pattern kuin
  `_round_hauler_claims`) → EI pysyvää varauslaskuria → ei varausvuotoa jos botti abortoi.

**Idle-syyt (`bot_manager.gd` vakiot, rivi 28–32):**
```gdscript
const IDLE_REASON_CHARGING := 5         # dokattu ja lataa (SEEK_CHARGE/CHARGING nakyy overlayssa)
const IDLE_REASON_WAITING_CHARGER := 6  # akku vahissa mutta kaikki slotit varattuja -> odottaa vuoroa
```
Päivitä `_idle_reason_for` (rivi 338) palauttamaan nämä. `get_fleet_stats` (rivi 288) lisää
`"waiting_charger": <lkm>` ja `"charging": <lkm>` — M4 lukee tätä disclosure-triggeriin.

**Charger-luonti:** `_init_bot_sim` luo base-chargerin (`is_base=true`, `slot_count=1`,
dokkauspiste basen kyljessä). Rakennettava latauspaikka tulee M4:n latausrivistö-moduulista
(`slot_count = CHARGER_BUILT_SLOTS`), rekisteröidään `bot_manager.chargers`-listaan.

**Valo:** `_collect_light_emitters` (rivi 1167) lisää per charger emitterin (radius ~50, intensity
~0.8) — sama pattern kuin koneilla.

**UI:** latauspaikka-popover: näyttää slotit, coal_buffer, **[Syötä hiiltä]** -nappi (kuluta
inventaarion COAL → `charger.feed_coal`). Bot-overlay (`ui_bot_status_overlay.gd`): pieni akkupalkki
per botti + CHARGING/WAITING-ikoni.

**MIKÄ SÄILYY ENNALLAAN:** kaikki nykyiset botti-tilat 0–4 ja niiden logiikka, ruuhkanhallinta,
louhinta/imu/dumppi, nav, designaatio, GPU-sim, fysiikka. Akku EI kulu MOVE/CARRY_MOVE/IDLE-tiloissa
(vain työstä).

**Testisuunnitelma:**
- **Uusi** `tests/unit/test_charger.gd`: `charge_rate` (trickle vs coal), `feed_coal`, slot-varaus.
- **Uusi** `tests/scenarios/battery_charge.json`: `set_battery` matalaksi → botti hakeutuu → lataa →
  `assert` akku noussut / botti palasi töihin. `feed_coal` → nopeampi lataus.
- **Uusi** `tests/scenarios/charger_queue.json`: monta bottia + 1 slotti → `assert` että joku on
  WAITING_CHARGER-tilassa (jono muodostuu, EI deadlock — assert että työ silti etenee).
- **Päivitä** `tests/unit/test_bot_manager.gd`: uudet tilat eivät riko olemassa olevia asserteja.

**Riskit:** (1) latausslotti-varausvuoto → JOHDA miehitys tilasta, älä pidä pysyvää laskuria. (2)
akun kuluminen headless-testeissä: pitkät `run_frames`-ajot voivat tyhjentää akun kesken vanhojen
skenaarioiden → vanhat skenaariot pitää joko täyttää akku (default MAX riittää ~90 s työhön) tai
lisätä `set_battery`-nollaus. Mitoita drain niin ettei mvp_core_loop/deep_ore_sale kuivu ennen
tavoitetta (90 s työtä on paljon; useimmat skenaariot alle sen — **varmista**). (3) deadlock-esto:
WAITING_CHARGER-botti ei saa jäädä ikuisesti; joka kierros uusi yritys, ja jos akku > 0 se voi vielä
tehdä työtä (älä pakota latausta ennen kuin akku = 0 ja työ mahdotonta — botti vain hidastuu).

---

### M4 — Haamumoduulit + progressive disclosure

**Tavoite:** basen kylkeen haamuääriviiva seuraavasta moduulista + täyttötarve → botit/pelaaja
täyttävät → moduuli rakentuu näkyvästi kiinni baseen ja avaa jotain. Build-menun itemit ilmestyvät
vasta kun ongelma on koettu.

**Muutettavat + uudet tiedostot:**
- **UUSI** `scripts/base_modules.gd` (`class_name BaseModules extends RefCounted` tai Node2D piirtoa
  varten) — moduuliketjun data + haamun piirto + täyttölogiikka.
- `scripts/pixel_world.gd` — moduuli-instanssi `_init_bot_sim`:ssä; täyttö-intake (haamun oma
  build-zone kuluttaa sopivat pikselit → fill-laskuri); moduulin valmistuminen (structure_pixels
  kirjoitetaan, `_register_building_pixels`, unlock-hook, charger-lisäys M3:lle).
- `scripts/ui.gd` — disclosure-triggerien laajennus (`_update_onboarding` rivi 1294 → yleisempi
  disclosure-järjestelmä); build-tray-itemien ehdollinen näkyvyys; haamun täyttötarpeen HUD.

**Moduuliketju + triggerit:**

| # | Moduuli | Trigger (toiminta/resurssi) | Täyttö | Unlock |
|---|---|---|---|---|
| 1 | Latausrivistö | `fleet_stats.waiting_charger > 0` (joku jonottanut) TAI `fleet ≥ 4` | 30 IRON_ORE | Charger `slot_count += CHARGER_BUILT_SLOTS` (M3) |
| 2 | Jalostamo-liitäntä | moduuli 1 valmis JA `inventory` piti joskus ≥ 40 IRON_ORE | 40 IRON_ORE + 20 COAL | furnace + crusher build-trayhin |
| 3 | Varastosiilo (valinn.) | moduuli 2 valmis | 60 STONE tai GRAVEL | +10 % myyntiarvo tai inventory-QoL |

**Haamun täyttömekaniikka:** moduulin haamu rekisteröi **täyttövyöhykkeen** (Logistics-tyyppinen
dump-vyöhyke basen kyljessä, `filter_mask` = moduulin tarvitsemat materiaalit). Kun materiaalipikseli
osuu vyöhykkeeseen (haulerien dump TAI pelaajan designaatio+dump), se **kuluu fill-laskuriin** sen
sijaan että kasautuisi. Kun `fill >= requirement`, moduuli rakentuu: `structure_pixels` kirjoitetaan
gridiin (näkyvä kasvu), `_register_building_pixels`, valo-emitteri, unlock-hook ajetaan.

> **Yksinkertaistus (valinnainen):** jos täyttövyöhyke-imu on liian iso urakka M4:lle, salli
> myös suora inventaariomaksu: pelaaja klikkaa haamua → "Rakenna (30 rautaa)" → `spend_materials`.
> Suosittu ratkaisu: **molemmat** — haamu täyttyy joko haulerien tuomana TAI klikkaamalla jos
> inventaariossa on varaa. Toteuttaja päättää; dokumentoi valinta.

**Progressive disclosure (`ui.gd`):** yleistä `_update_onboarding` (rivi 1294) disclosure-tilakoneeksi
joka lukee `bot_manager.get_fleet_stats()` + `pixel_world.inventory` + moduulien tilan. Build-trayn
itemit (`_build_build_tray` rivi 538) rakennetaan ehdollisesti: furnace/crusher-napit PIILOSSA kunnes
jalostamo-moduuli valmis; latauspaikka-nappi (jos erillinen) näkyy vasta kun latausrivistö-trigger
lauennut. Nykyinen `ONBOARDING_TEXTS`-vihjerivi säilyy mutta tekstit sidotaan disclosure-vaiheisiin.

**MIKÄ SÄILYY ENNALLAAN:** jalostuskoneet (furnace/crusher/conveyor) itse — vain niiden build-tray-
näkyvyys gettaa moduulin taakse; koneet toimivat identtisesti kun rakennettu. Base-popover (M1),
bot-tray, designaatio, actionbar-runko.

**Testisuunnitelma:**
- **Uusi** `tests/unit/test_base_modules.gd`: trigger-logiikka (fleet/inventory-ehdot),
  fill-laskuri, valmistuminen + unlock-hook.
- **Uusi** `tests/scenarios/module_build.json`: `set_inventory` iso IRON_ORE → täytä moduuli 1 →
  `assert` charger-slotit kasvoivat. Sitten moduuli 2 → `assert` furnace rakennettavissa
  (esim. `place_building furnace` onnistuu vasta unlockin jälkeen — tai erillinen assert-flag).
- UI-disclosure: verifioi manuaalisesti (feedback: UI vaatii oikean interaktion, ei vain lokia).

**Riskit:** (1) haamun täyttövyöhykkeen ja normaalin dump-vyöhykkeen erottelu — käytä uutta lippua
(esim. `is_module_fill`) samaan tapaan kuin `is_base_dropoff`. (2) disclosure ei saa piilottaa jo
rakennettua/aktiivista konetta. (3) moduulin structure_pixels ei saa mennä basen/dropoffin päälle
(sijoita basen kylkeen, tarkista `building_pixels`-törmäys).

---

### M5 — Laskeutumisintro + nopea startti

**Tavoite:** Title → klik → kapseli putoaa taivaalta falling sand -fysiikalla, laskeutuu alustalle,
aukeaa, 2 bottia ulos, EI tekstiä. Klik skippaa intron heti. World gen takaa näkyvän rautasuonen
alustan lähelle. Designaatiotila PÄÄLLÄ oletuksena. Kaikki triggerit toiminta-/resurssipohjaisia.

**Muutettavat tiedostot:**
- `scripts/pixel_world.gd` — laskeutumissekvenssi (visuaalinen), designaatiotilan oletus, bottien
  spawn-ajoitus.
- `scripts/world_gen.gd` — takuu-rautasuoni alustan viereen pintaan (`generate` rivi 136,
  `_stamp_platform`in jälkeen).
- `scripts/ui.gd` — Title-flow (`Flow.TITLE` rivi 207, `_build_title_overlay` rivi 2071,
  `_start_game`-polku rivi ~1957) → laukaisee laskeutumisen; klik skippaa.

**Laskeutumissekvenssi:** puhtaasti **visuaalinen kerros** — EI kytketä bottisimulaation
alustukseen (tests boottaavat suoraan botteihin). Toteutus:
- Title-klik → `_start_game` → `Flow.PLAYING`. Käynnistä `_landing_sequence` (windowed vain).
- Kapseli = pieni klusteri (esim. rigid body TAI väliaikaiset STONE/GLASS-pikselit) spawnataan
  alustan yläpuolelle → putoaa (fysiikka/CA) → laskeutuu → "aukeaa" (poista kapselipikselit) →
  2 aloitusbottia **paljastuvat/aktivoituvat** kapselin kohdalla.
- **Pöly:** spawnaa GRAVEL/SAND-granulaaripikseleitä + ruutu-shake laskeutumisiskussa.
- **Skip:** klik intron aikana → aseta kapseli välittömästi laskeutuneeksi + botit ulos.
- **Ajoitus:** `_init_bot_sim` spawnaa yhä 2 bottia (testit vaativat "aloituslauma = 2"). Windowed-
  introssa botit piilotetaan/pidetään kapselissa ~2 s ja paljastetaan kapselin auettua. Headless/
  scenario: intro ohitetaan kokonaan (botit heti aktiiviset). Gate: `if not gpu_ready or
  _scenario_active: skip intro`.

**Designaatiotila oletuksena PÄÄLLÄ:** aseta `designation_mode = true` uuden pelin windowed-startissa
(esim. laskeutumisen jälkeen, `_init_bot_sim`in lopussa tai `_start_game`ssä). Yksi verbi: vedä =
merkkaa kaivuu. Muistio [[project-grid-size-actual]] / designation_grid default FALSE — M5 kääntää
windowed-oletuksen. Headless ei riipu tästä (skenaariot kutsuvat `designate_rect` suoraan).

**World gen — takuu-rautasuoni:** `generate()` (rivi 136), `_stamp_platform`in (rivi 199) JÄLKEEN,
lisää `_place_starter_iron_vein()`: sijoita 1 lyhyt IRON_ORE-suoni (thickness ~3, len ~30) alkaen
juuri alustan reunan ULKOPUOLELTA (x ≈ `platform_x0 - 40` tai `platform_x0 + platform_w + 40`),
matalaan syvyyteen (surface_y + ~16…48 px) niin että se on **osittain pinnassa ja näkyvissä**
alustan vierestä. Käytä olemassa olevaa `_walk_vein`/`_carve_vein_disc`-koneistoa. Varmista ettei
mene BEDROCKin/alustan päälle.

**MIKÄ SÄILYY ENNALLAAN:** GPU-sim, CA, fysiikka, muu world_gen (suonet, tehdasalusta, reunat),
bottien init-logiikka, Title/Pause/DemoComplete-overlayt (vain Title→Play-siirtymä saa laskeutumisen).

**Testisuunnitelma:**
- **Uusi** `tests/scenarios/starter_vein.json` (tai laajenna `worldgen_stress.json`): `assert_count`
  IRON_ORE > 0 alustan viereisellä alueella (starter-suoni olemassa ja matalalla).
- Laskeutumisintro + designaatio-oletus: manuaalinen verifiointi windowed (feedback:
  [[feedback-ui-verification]] — simuloi klikkaus + lue screenshot). Varmista headless-skenaariot
  eivät regressoi (intro ohittuu).

**Riskit:** (1) intro ei saa blokata/viivästyttää headless-bottien spawnia. (2) kapseli-fysiikka ei
saa rikkoa alustaa (STONE-perustus) — käytä väliaikaisia pikseleitä jotka poistetaan. (3)
`designation_mode = true` ei saa vuotaa skenaarioihin (gate gpu_ready/scenario). (4) starter-suoni ei
saa spawnata alustan STONE-perustuksen tai basen päälle.

---

## 4. Yhteensopivuus

### 4.1 ScenarioRunner-komennot (`_scenario_execute_step`, rivi 4475)

**Uudet komennot (lisää M1/M2/M3 match-haaraan):**

| Komento | Kentät | Moduuli | Vaikutus |
|---|---|---|---|
| `set_inventory` | `mat:int, px:int` | M1 | `inventory[mat] = px` (deterministinen alkutila) |
| `add_inventory` | `mat:int, px:int` | M1 | `inventory[mat] += px` |
| `assert_inventory` | `mat, min, max, label` | M1 | assert `inventory_amount(mat)` välillä |
| `set_material_policy` | `mat:int, policy:int` | M1 | `set_material_policy` (0=SELL,1=STORE) |
| `sell_inventory` | `mat:int (-1=kaikki)` | M1 | `sell_from_inventory` / `sell_all_surplus` |
| `build_bot` | `role:int, count:int` | M2 | `bot_manager.build_bot` (kuluttaa inventaarion) |
| `assert_bot_cost` | `min, max, label` | M2 | assert `next_bot_cost()[IRON_ORE]` välillä |
| `set_battery` | `value:float` (kaikki botit) | M3 | testaa lataushakeutumista |
| `feed_coal` | `px:int` (base-charger) | M3 | `charger.feed_coal` |
| `assert_charging` | `min, label` | M3 | assert ≥min bottia CHARGING/SEEK_CHARGE-tilassa |
| `fill_module` | `n:int, mat:int, px:int` | M4 | syötä moduulin haamun täyttölaskuria |
| `assert_module_built` | `n:int, label` | M4 | assert moduuli n rakennettu |

**Migraatio (säilytä käytös):**
- `buy_bot` (rivi 4726): repurposoi kutsumaan `build_bot`ia (materiaalipohjainen). Koska vanhat
  skenaariot `set_money`aa ennen `buy_bot`ia, ne EIVÄT enää toimi ilman inventaarion siementä →
  **päivitä nuo skenaariot** (alla). Vaihtoehtoisesti poista `buy_bot`-komento ja korvaa `build_bot`illa.
- `set_money`/`assert_money_gt`/`assert_money_lt` SÄILYVÄT (raha on yhä olemassa myynti/unlock-puolella).

### 4.2 demo_complete-ehdon päivitys (`_update_demo_arc`, rivi 1804)

Nykyinen: `money >= 10000 or _rare_earth_sold`. RARE_EARTH menee nyt inventaarioon (STORE) — sen
"myynti" = manuaali. Päivitä:
```
if not _demo_completed and (money >= 10000 or _all_modules_built()):
```
missä `_all_modules_built()` kysyy M4:n moduuliketjun tilaa. Rahapolku (`money >= 10000`) säilyy
saavutettavana myynnin kautta. `_rare_earth_sold`-seuranta (rivi 1787–1799) voi jäädä milestone-
laukaisijaksi ("Harvinaista maametallia löytyi") mutta EI enää demo-completen ehdoksi (tai jätä sekä
raha että moduulit). Muut milestonet (rivi 1776–1803) säilyvät.

### 4.3 Skenaariot: päivitä vs. poista

| Skenaario | Toimenpide |
|---|---|
| `bot_buy.json` | **Päivitä:** `set_money` → `set_inventory {mat:12}`; `buy_bot` → `build_bot`; `assert_money_*` → `assert_inventory` + `assert_fleet`. Todistaa: materiaali kuluu, lauma kasvaa, kasvava resepti estaa rakentamisen kun rautaa ei riita. |
| `deep_ore_sale.json` | **Päivitä:** COPPER/RARE_EARTH default = STORE → premium-RAHAA ei synny automaattisesti. Lisää `set_material_policy {mat:20,policy:0}` + `{mat:21,policy:0}` (SELL) alkuun, TAI vaihda loppu-assert `assert_money_gt` → `assert_inventory`. Säilytä D3:n ydin (raaka premium-arvo). `set_money 1425`-bottiostot → `set_inventory`-pohjaiset build_botit. |
| `mvp_core_loop.json` | **Tarkista + säädä:** GRAVEL/DIRT default = SELL → raha nousee kuten ennen (`assert_money_gt 150` pitäisi pysyä vihreänä, koska louhittu kivi→gravel auto-myydään). Jos miner louhii rautaa (STORE), se ei tuota rahaa → varmista alue tuottaa myös roskaa, tai laske kynnystä / lisää `assert_inventory`. |
| `fleet_scale.json`, `pause_bots.json` | **Tarkista:** akku (M3) ei saa kuivua kesken pitkän ajon → default BATTERY_MAX riittää; jos ei, lisää `set_battery`. |
| muut (fysiikka/CA/hihnat/worldgen) | **Ei muutosta** — eivät koske talouteen/botteihin. |

`tests/scenarios/_audit_*.json` (git-statuksen uudet) — tarkista sisältö; jos ne mittaavat vanhaa
rahamallia, päivitä tai poista.

---

## 5. Toteutusjärjestys ja moduulien väliset sopimukset

**Järjestys on pakollinen: M1 → M2 → M3 → M4 → M5.** Jokainen olettaa edellisen API:n olemassaolevaksi.

### Sopimukset (mitä myöhemmät moduulit käyttävät edellisistä)

**M1 tarjoaa (pixel_world.gd) — M2/M3/M4/M5 nojaavat näihin:**
```gdscript
var inventory: Dictionary                      # mat_id -> px
var material_policy: Dictionary                # mat_id -> POLICY_SELL|POLICY_STORE
const POLICY_SELL := 0
const POLICY_STORE := 1
func deposit_material(mat_id: int, px: int) -> void
func deposit_cargo(cargo: Dictionary) -> void
func sell_from_inventory(mat_id: int, px: int = -1) -> int
func sell_all_surplus() -> int
func inventory_amount(mat_id: int) -> int
func inventory_total_value() -> int
func can_afford_materials(recipe: Dictionary) -> bool   # <- M2 build_bot, M3 build_charger, M4 fill/build
func spend_materials(recipe: Dictionary) -> bool        # <- sama
func set_material_policy(mat_id: int, policy: int) -> void
```

**M2 tarjoaa (bot_manager.gd) — M4 lukee disclosure-triggeriin:**
```gdscript
func next_bot_cost() -> Dictionary
func can_build_bot() -> bool
func build_bot(role: int) -> bool
# _bought_count (fleet-koon johdannainen) — M4 disclosure "fleet >= 4"
```

**M3 tarjoaa (bot_manager.gd + charger.gd) — M4 kytkee latausrivistön, M4/UI lukevat jonon:**
```gdscript
var chargers: Array[Charger]                   # M4 lisaa latausrivisto-moduulissa slotit
func get_fleet_stats() -> Dictionary           # LISATTY: "waiting_charger":int, "charging":int
# Bot.BotState.SEEK_CHARGE (5), CHARGING (6)
# IDLE_REASON_CHARGING (5), IDLE_REASON_WAITING_CHARGER (6)
```
M3:n `get_fleet_stats`-laajennus (`waiting_charger`) on M4:n **latausrivistö-triggerin** ehto — M3:n
on toteutettava tämä kenttä vaikka M4:ää ei vielä olisi.

**M4 tarjoaa (base_modules.gd + pixel_world.gd) — M5 kysyy demo-completeen:**
```gdscript
func _all_modules_built() -> bool              # pixel_world; _update_demo_arc kayttaa
# Moduulin valmistuminen kutsuu unlock-hookia joka: M3-chargerin slot_count += CHARGER_BUILT_SLOTS,
# tai furnace/crusher build-tray-nakyvyys.
```

**M5** käyttää kaikkea; ei tarjoa uutta API:a myöhemmille (viimeinen). Muutokset: intro (visuaalinen),
`world_gen._place_starter_iron_vein`, `designation_mode` windowed-oletus.

### Rajapinta-invariantit (älä riko)
- **Säilyvyys:** jokainen intake-/kuorma-px joko myydään (money) TAI varastoidaan (inventory) TAI
  kirjoitetaan maailmaan — ei koskaan kadoteta eikä tuplata (M1 `deposit_cargo`, M3 lataus).
- **Botti-tilat 0–4** ja niiden numerointi säilyy; uudet lisätään loppuun (M3: 5,6).
- **Bottisim-tiedostot ASCII**, pixel_world/ui/world_gen ä/ö — per tiedosto.
- **GPU-sim, CA, fysiikka, hihnat, jalostuskoneet, nav, designaatio, Margolus 2×2** koskematta.
- **Push constant ≤ 128 B, workgroup 16×16** — mikään moduuli ei kosketa shadereita.

---

## 6. Tulevaisuus (max 5 riviä — EI tässä speksissä)

- Viholliset / puolustus (Dyson-lore laajenee).
- Mk2-kristalliportit, maanalaiset latausasemat, kaukokuljetus.
- Automaatioketjut (botti rakentaa botin ilman baseä), moduuli-tech-puu.
- Save/load (nyt vain `_init_bot_sim`-polku, ei serialisointia).
- Useampi base / laajeneva emoalus.
