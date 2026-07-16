# Balanssiraportti — GodotMining Bot Mining -demo (T4.1)

**Päiväys:** 2026-07-17
**Tekijä:** QA/debugger-agentti (T4.1)
**Metodi:** Deterministinen headless-mittaus (ScenarioRunner, `cpu_ca:true`, kiinteä 1/60 s
aika-askel → toistettava, ei riipu fps:stä eikä törmää käyttäjän ikkunaan). Skenaariot:
`tests/scenarios/_audit_income.json` (eka-botti + 2-botin $/s), `_audit_fleet.json`
(fleet-skaalaus). Lokit: `scratchpad/hl_income.log`, `hl_fleet.log`.

> **Koodimuutos (additiivinen):** lisäsin `add_bot`-scenariokomennon (`pixel_world.gd`,
> scenario-dispatch) jotta fleet-koon voi asettaa deterministisesti headless-mittauksessa. Vain
> skenaarioajossa; ei vaikuta normaalipeliin. HUOM: muutos päätyi masteriin toisen agentin
> committiin `e8d376f` (laaja `git add` nappasi työpuun muutokseni mukaan) — nyt committoitu,
> benigni. Voidaan pitää test-infrana tai revertata erikseen.

---

## 1. Tiivistelmä

- **Eka lisäbotti ($300) ~1 min 57 s** kahdella aloitusbotilla → GDD-tavoite "2–3 min" **TÄYTTYY**.
- **Hauler on läpisyötön pullonkaula:** yksi miner tuottaa nopeammin kuin yksi hauler ehtii kantaa.
  Paras varhainen ostos on **toinen hauler** (ei toinen miner) — se ~tuplaa tulon (3,6 → 6,7 $/s).
- **Fleet skaalaa ~lineaarisesti** ~2:1 hauler:miner-suhteella ainakin 6 bottiin asti (ei
  havaittavaa congestion-kattoa vielä): 2 bottia 3,6 $/s → 6 bottia 13,4 $/s.
- **Raaka-materiaalitierit skaalaavat hinnalla** (hauler-throughput × $/px): dirt 3,6 → iron ~10,8
  → gold ~18 → rare earth ~28,8 $/s (2 botilla).
- **KRIITTINEN demo-riski:** GDD:n tier-2+ $/s-kerroin tulee JALOSTUKSESTA, mutta jalostusketju ei
  aktivoidu boteilla nykybuildissa (auditin P0-2: base hyväksyy kaiken → malmi myydään raakana).
  Demon "seuraava askel = jalostus moninkertaistaa tulon" -kaari EI ole saavutettavissa ennen
  P0-2-korjausta. Ilman jalostusta demo on läpäistävissä vain raaka-tiereillä + fleet-skaalauksella.
- **MITATTU jatko (§8): tier-progressio EI näkynyt $/s:ssä.** 6 bottia rautasyvyydessä = ~10,7 $/s
  (jopa alle pinta-13,4:n): hauler-pullonkaula estää laskeutumisen malmiin. Demo-projektio: price 1
  → ~32 min $10 000:een (LIIAN HIDAS); 15–25 min toteutuu VAIN efekt. price 2–3:lla, joka vaatii
  toimivan tier-progression (syvä malmi TAI jalostus) — molemmat nyt tukossa. **Demo-pacing on
  vaarassa ennen kuin (a) hauler-pullonkaula ja (b) P0-2 korjataan.**

---

## 2. Eka-botti-ajoitus + 2-botin $/s (mitattu, `_audit_income.json`)

2 aloitusbottia (1 miner + 1 hauler), iso pintadesignaatio (price 1: multa/kivi), 5 min:

| Aika | money | | Aika | money |
|---|---|---|---|---|
| 0:45 | $40 (eka tulo) | | 3:00 | $560 |
| 1:00 | $80 | | 4:00 | $760 |
| 1:30 | $200 | | 5:00 | $960 |
| **1:57** | **~$300 → eka lisäbotti** | | | |

- Vakaa tulovirta **~3,6 $/s** (t=45 s→300 s: $920 / 255 s). Designaatio ei ehtynyt → steady-state.
- Ensimmäinen tulo vasta ~45 s: miner kaivaa + hauler tekee ensimmäisen reissun. Tämä "kuollut
  alku" voi tuntua hitaalta (ks. tuning §5).

## 3. Fleet-skaalaus (mitattu, `_audit_fleet.json`)

Sama pintaterrain (price 1), 30 s mittausikkuna per kokoonpano, botteja lisätty `add_bot`illa:

| Kokoonpano | Miner/Hauler | $/s | Muutos |
|---|---|---|---|
| A | 1 / 1 | **~3,6*** | *tämän ajon 30 s-ikkuna osui ramp-vaiheeseen (1,3); steady-arvo §2:n täysajosta |
| B | 1 / 2 | **6,7** | +1 hauler → ~2× (vahvistaa hauler-pullonkaulan) |
| C | 2 / 2 | **8,0** | +1 miner → vain +1,3 (2 hauleria ei ime edes ~1,5 minerin tuotosta) |
| D | 2 / 4 | **13,4** | +2 hauleria → ~1,7× (hauler on läpisyötön ajuri) |

**Tulkinta:** läpisyöttö on hauler-rajoitettu. Miner tuottaa irtomateriaalia nopeammin kuin
hauler kantaa (mittauksissa 20–38 keräämätöntä `dig_site`-kasaa jatkuvasti). Optimaalinen suhde
~2 hauleria / miner. 2:1-suhteella fleet skaalaa ~lineaarisesti (B 3 bottia 6,7 → D 6 bottia 13,4),
eli congestion-kattoa ei näy vielä 6 botilla. Tämä on hyvä uutinen skaalautuvuudelle, mutta
tarkoittaa että **pelaajan pitää tajuta ostaa haulereita** — peli ei ohjaa tähän (auditin P1-4).

## 4. Raaka-materiaalitierit ($/px → $/s, malli)

Läpisyöttö on materiaaliriippumaton (hauler kantaa 40 px/reissu riippumatta lajista; base maksaa
`$/px`). Siksi raaka-$/s ∝ hinta, ankkuroituna dirt=3,6 $/s (2 bottia):

| Materiaali | $/px | Raaka-$/s (2 bottia, malli) | Syvyystier (GDD) |
|---|---|---|---|
| DIRT / STONE | 1 | 3,6 (mitattu) | pinta |
| COAL | 2 | ~7,2 | 0.0–0.35 |
| IRON_ORE | 3 | ~10,8 | 0.10–0.55 |
| COPPER_ORE | 4 | ~14,4 | 0.35–0.75 |
| GOLD_ORE | 5 | ~18 | 0.55–0.90 |
| RARE_EARTH | 8 | ~28,8 | 0.75–1.0 |

*Varaus:* suora IRON-mittaus epäonnistui test-artefaktin takia (fill_rect loi ison PUHTAAN
granular-malmi-slabin, joka valuu/luhistuu cpu_ca:ssa → hauler ei löytänyt keräyskelpoisia kasoja,
money jäi $0:aan; luonnossa malmi on upotettuna kiveen, ei puhtaana slabina). Malli perustuu
todennettuun läpisyöttö×hinta-logiikkaan. **Sivuhavainto (P2, tutkittava erikseen):** iso puhdas
granular-malmikappale saattaa jumittaa haulerin — kannattaa varmentaa realistisella suonisetupilla.

## 5. Jalostuskerroin (PRICES) — mutta BLOKATTU (auditin P0-2)

| Resepti | Raaka $/px → Jalostettu $/px | Kerroin |
|---|---|---|
| SAND(1) → GLASS(3) | 1 → 3 | 3,0× |
| IRON_ORE(3) → IRON(5) | 3 → 5 | 1,67× |
| GOLD_ORE(5) → GOLD(12) | 5 → 12 | 2,4× |

Nämä kertoimet ovat demon tier-2+ $/s-hypyn KDin — mutta ne EIVÄT toteudu boteilla nykybuildissa:
base-pudotus hyväksyy kaiken (`filter_mask=0`), joten hauler myy malmin raakana ennen kuin se
päätyy furnaceen (auditin P0-2). **Ilman P0-2-korjausta jalostuksen $/s-kerroin on saavuttamaton
normaalipelissä**, ja tier-2+ eteneminen nojaa pelkkään syvempään raakamalmiin (§4).

## 6. Demo-kaari 15–25 min (mallinnettu)

- **0–3 min (Tier 1):** 2 bottia, pintadirt/kivi ~3,6 $/s → eka lisäbotti ~2 min. **Mitattu, OK.**
- **3–8 min (Tier 2):** jos pelaaja ostaa haulereita (→ ~7–13 $/s) ja kaivaa hiili/rautasyvyyteen
  (price 2–3 → ~15–30 $/s 4–6 botilla), talous kasvaa jyrkästi. Jalostus-kerroin PUUTTUU (P0-2).
- **8–25 min (Tier 3–4):** kulta/harvinaismaa (price 5–8) + iso fleet → ~40–80 $/s mahdollinen.
  $10 000-maali on saavutettavissa raaka-tiereillä ~15–25 min jos fleet skaalaa ja syvyys kasvaa.

**Arvio:** demo on todennäköisesti läpäistävissä 15–25 min RAAKA-materiaaleilla + fleet-skaalauksella,
MUTTA suunniteltu "jalostus moninkertaistaa tulon" -tier-hyppy ei toimi (P0-2). Tarkka läpipeluu-
mittaus vaatii joko P0-2-korjauksen tai jalostuksen käsin-reitityksen — suositus §7.

## 7. Tuning-suositukset

1. **Korjaa P0-2 (jalostuksen reititys)** ENNEN balanssilukkoa — muuten tier-2+ $/s-kaari on kuollut
   suunnittelupaperilla. Suositus: kun furnace/crusher rakennetaan, poista sen reseptin input-malmi
   basen hyväksytyistä automaattisesti.
2. **Ohjaa pelaaja haulereihin** varhain (auditin P1-4). Optimaalinen ~2 hauleria/miner; peli ei
   kerro tätä. Vaihtoehto: aloita 1 miner + 2 haulerilla, tai vihje kun `dig_sites` kasautuu.
3. **"Kuollut alku" (~45 s ennen ekaa tuloa):** harkitse pientä aloituspuskuria tai nopeampaa ekaa
   louhintaa jottei uusi pelaaja ehdi päätellä "mitään ei tapahdu".
4. **Bottihinta 300×1,5^n** (300/450/675/1012/1518/2277...) toimii Tier 1:ssä (~2 min välit), mutta
   validoi ettei myöhempi hinta ohita raaka-$/s-kasvua ilman jalostusta (jos P0-2 jää auki, tulo
   nojaa syvyyteen — varmista että syvempi malmi on saavutettavissa bottien louhinnalla).
5. **Raaka-tierien hinnat** (COAL 2 / IRON 3 / COPPER 4 / GOLD 5 / RARE 8) antavat siistin 2–8×
   kertaluokan raaka-hypyn — riittävä tier-erottelu jos jalostus jää toissijaiseksi.

## 8. Mid-game-käyrä + demo-complete-projektio (T4.1 jatko)

### 8.1 Mid-game mitattu (6 bottia 2m4h, designaatio rautasyvyyteen y≈370→636)
set_money 2500 → buy_bot 1 miner + 3 hauleria (2m4h), designaatio pinnalta rautatieriin, 5 min:

| Aika | money | $/s (Δ30s) | desig | dig_sites |
|---|---|---|---|---|
| 0:30 | 222 | (ramp) | 112 | 16 |
| 1:00 | 576 | 11,8 | 109 | 19 |
| 2:00 | 1246 | ~11 | 106 | 22 |
| 3:00 | 1886 | 10,7 | 102 | 26 |
| 4:00 | 2526 | 10,7 | 98 | 30 |
| 5:00 | 3166 | 10,7 | 96 | 32 |

**Johtopäätös (tärkeä):** $/s asettui **~10,7 $/s** — EI hyppyä, itse asiassa hieman ALLE pinta-6-botin
baselinen (13,4). Kaksi syytä: (a) **syvyyspenalty** (pidemmät hauler-reissut kuoppaan), (b) frontier
tuskin eteni (136→96 solua 5 min:ssä) ja **32 keräämätöntä kasaa** — **hauler-pullonkaula estää
laskeutumisen** malmisyvyyteen. Miner ei ehdi kaivautua alas malmiblobeihin koska haulerit eivät
tyhjennä kasoja. **Tier-progressio EI näkynyt $/s:ssä tässä ajossa.** *(Todiste: `scratchpad/hl_midgame.log`.)*

### 8.2 Raaka-malmin eristys ei onnistunut headlessina (harness-rajoite)
Yritin eristää MATERIAALIARVON syvyyspenaltysta täyttämällä IRON-lohkon pinnalle (2 bottia). Mining
pysähtyi ~60 s:ssa (frontier jäätyi, kasat jäivät): `fill_rect`illä tehty PUHDAS granular-malmilohko
valuu/luhistuu cpu_ca:ssa (sama artefakti kuin §4). **Johtopäätös: cpu_ca-headless ei sovi puhtaan
malmi-$/s:n mittaukseen `fill_rect`illä.** Malli (base maksaa $/px PRICES-taulusta, koodivarmennettu;
läpisyöttö materiaaliriippumaton → raaka-$/s ∝ hinta) pysyy parhaana arviona §4:n tiereille, mutta
sitä EI voitu empiirisesti vahvistaa tällä harnessilla.

### 8.3 Demo-complete-projektio ($10 000, kasvumalli)
Greedy-kasvusimulaatio (`scratchpad/growth.awk`): 2 aloitusbottia, osta 2:1 hauler:miner-suhteella
kun varaa riittää; $/s(m,h)=min(6,7·m, 3,35·h)·PMULT (mitattu price-1-malli × materiaalikerroin):

| Materiaalikerroin (efekt. hinta) | Aika $10 000:een | Loppufleet |
|---|---|---|
| **1,0** (pelkkä pintakivi) | **~32 min** — LIIAN HIDAS | 4m7h (11 bottia) |
| **2,0** (hiili/rauta-sekoitus) | **~16 min** — tavoitteessa | 4m7h |
| **3,0** (rautatier) | **~11 min** — hieman nopea | 4m7h |

**Herkkyys:** botti-määrä ei ole pullonkaula (11 bottia riittää kaikissa) — **rajoittava tekijä on
efektiivinen materiaalihinta (syvyys/jalostus).** Pintakivellä (price 1) demo kestää ~32 min vaikka
lauma kasvaisi; **15–25 min toteutuu vain jos pelaaja pääsee price ~2–3 materiaaliin.**

### 8.4 SYNTEESI — demo-pacing on rikki ilman toimivaa tier-progressiota
Demon 15–25 min-tahti VAATII tier-progression (efekt. price 2–3), MUTTA molemmat reitit sinne ovat
tällä hetkellä tukossa:
- **Syvempi malmi:** hauler-pullonkaula estää laskeutumisen (§8.1) — miner ei ehdi kaivautua malmiin.
- **Jalostus:** blokattu (auditin P0-2) + ScenarioRunner ei voi edes testata sitä (§9).
→ Pelaaja jää käytännössä ~10–13 $/s:ään (price ~1) → **~32 min $10 000:een = liian hidas demolle.**

## 9. Puuttuvat skenaariokomennot (jalostusketjun testaukseen)
ScenarioRunner EI voi rakentaa/testata jalostusketjua. Puuttuu (EN lisännyt näitä — pixel_world.gd
on toisen agentin omistuksessa):
- **`place_building` on TYNKÄ** (`pixel_world.gd`, vain `push_warning` default-haara — ei sijoita
  furnacea/crusheria eikä rekisteröi input-dump/output-pickup-vyöhykkeitä).
- **Ei filtterikomentoa** (`set_base_filter` / `set_zone_filter`) → malmia ei voi reitittää furnaceen.
- Jotta jalostus-delta voidaan mitata skenaariolla, tarvitaan: toimiva `place_building type=furnace`
  (+ zone-rekisteröinti) JA `set_base_filter mask`. Vaihtoehtoisesti P0-2-korjaus, jos se auto-säätää
  base-filtterin furnacea rakennettaessa → silloin riittää toimiva `place_building`.
- **Uudelleenajovalmius:** kun P0-2 mergeytyy, jalostusmittaus voidaan ajaa samalla harnessilla heti
  kun em. komennot ovat olemassa. Harness (`scratchpad/mg_*.json`, `growth.awk`) on tallessa.

## 10. Mitä EI mitattu / rajoitteet

- **Täysi 15–25 min läpipeluu jalostuksella:** estyy P0-2:sta (jalostus ei aktivoidu boteilla) +
  ScenarioRunnerissa ei rakennuskomentoja. Mallinnettu §6.
- **Congestion-katto >6 botilla:** ei mitattu (skaalaus oli lineaarinen 6:een asti; isompi lauma
  jää fleet_scale-skenaarion / erillisen ajon varaan).
- **Per-malmi suora mittaus:** iron-slab-artefakti (§4); käytetty läpisyöttö×hinta-mallia.
- **Windowed-läpipeluu:** vältetty tarkoituksella (käyttäjä koneella → syöteristiriita, ks. T1.1 §4).
