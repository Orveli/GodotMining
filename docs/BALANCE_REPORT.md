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
- **JALOSTUS KORJATTU (§5, commit 70e2b26): nyt value-positive.** Reseptit count=4 + 2×2-harkkobody →
  SAND→GLASS 3,0×, IRON 1,67×, GOLD 2,4× (arvo koodivarmennettu). Vastaus "tuottaako jalostus enemmän
  kuin raakamyynti": KYLLÄ nyt. (Aiempi count-12/16/8-resepti TUHOSI 70–86 % arvosta — korjattu.)
  **HUOM: end-to-end $/s:ää ei voi mitata headlessina** (furnace-sulatus + harkkofysiikka ovat
  GPU-only → furnace inertti headless); arvo todennettu koodista. **2 käytännön kitkaa jäljellä:**
  furnacen läpisyöttö ~2,67 malmia/s (ylivuoto isolla laumalla) + harkot vaativat HIHNAN baseen (UX).
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

## 5. Jalostus KORJATTU — nyt value-positive (commit 70e2b26), arvo koodivarmennettu

**Historiaa:** aiemmat reseptit (count 12/16/8, output 1 px) tuhosivat 70–86 % arvosta → furnace oli
ansa. **KORJATTU 2026-07-17 (70e2b26):** RECIPES `count=4` kaikille, output = 2×2 rigid body (4 px)
→ 1:1 tilavuuskonversio. Nyt per pikseli arvo nousee PRICES-taulun kertoimella:

| Resepti | count:output px | Raaka-arvo (4 × $/px) | Jalostettu (4 × $/px) | **KERROIN** |
|---|---|---|---|---|
| SAND($1) → GLASS($3) | 4 : 4 | 4 × $1 = $4 | 4 × $3 = $12 | **3,0×** |
| IRON_ORE($3) → IRON($5) | 4 : 4 | 4 × $3 = $12 | 4 × $5 = $20 | **1,67×** |
| GOLD_ORE($5) → GOLD($12) | 4 : 4 | 4 × $5 = $20 | 4 × $12 = $48 | **2,4×** |

**Jalostus on nyt value-positive** ja täsmää GDD:n intenttiin. Vastaus tehtävän kysymykseen
"tuottaako IRON_ORE→IRON enemmän kuin raakamyynti": **KYLLÄ nyt — 1,67× (iron), 2,4× (gold), 3× (glass)
per pikseli.** P0-2-reititys todistettu toimivaksi aiemmin (`refine_route_test.gd`).

**MITTAUSRAJOITE (tärkeä): end-to-end $/s:ää EI voi mitata headlessina.** `_update_furnaces` (malmin
sulatus) JA `physics_world.step` (2×2-harkkobodyjen liike) ajetaan VAIN GPU-polussa (pixel_world.gd:853),
EIVÄT headless cpu_ca -haarassa → **furnace on inertti headlessina** (ei sulata, harkot eivät liiku).
Siksi arvo on todennettu koodista (resepti + PRICES), ei end-to-end-simulaatiosta. Aiemman confounded-
ajon "refined-hyöty" oli pelkkä ylivuoto-raakamyynti (§9), EI furnacea — koska furnace ei toiminut lainkaan.

**KAKSI KÄYTÄNNÖN KITKAPISTETTÄ jäljellä demolle (eivät arvo-, vaan käytettävyys-/skaalausongelmia):**
1. **Läpisyöttö:** SMELT_COOLDOWN=1,5 s × 4 malmia = **~2,67 malmia/s per furnace.** Iso lauma toimittaa
   malmia nopeammin → ylivuoto (myydään raakana) tai backlog. Suositus: SMELT_COOLDOWN 1,5→~0,75 s
   TAI INTAKE_W 6→8–10, jotta yksi furnace ehtii jalostaa ~5–8 malmia/s.
2. **Harkot ovat rigid-bodyja joita hauler EI imuroi** → tarvitaan HIHNA furnace→base (extra rakennusaskel).
   Tämä on UX-kitka: jalostusketju vaatii furnace + hihna + malmireititys. Onboarding/opaste tarpeen.

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

0. **[TEHTY] Furnace-reseptien arvo (§5)** — korjattu commitissa 70e2b26 (count=4, value-positive). ✓
1. **[KORKEA] Furnacen läpisyöttö** (`furnace.gd`): SMELT_COOLDOWN 1,5 s → **~0,75 s** TAI INTAKE_W 6 →
   **8–10**. Nyt yksi furnace jalostaa vain ~2,67 malmia/s → iso lauma ylivuotaa (malmi myydään raakana,
   jalostuskerroin jää saamatta). Nopeampi/leveämpi intake antaa ~5–8 malmia/s → jalostus ehtii skaalata.
2. **[KORKEA] Jalostusketjun UX:** harkot ovat rigid-bodyja joita hauler ei imuroi → pelaaja tarvitsee
   HIHNAN furnace→base. Lisää onboarding-opaste ("Rakenna furnace + hihna baseen") tai auto-connect
   (kuten crusherilla). Muuten value-positive-jalostus jää löytämättä/rakentamatta.
3. **[KESKI] Ohjaa pelaaja haulereihin** varhain (auditin P1-4). Optimaalinen ~2 hauleria/miner; peli ei
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
- **Jalostus:** EI blokattu enää (P0-2 mergattu ja reitittää malmin furnaceen), mutta jalostus TUHOAA
  arvoa (§5, 0,14× iron) → furnacen rakentaminen ROMAHDUTTAA tulon. Aktiivisesti pahempi kuin "blokattu".
→ Pelaaja jää käytännössä ~10–13 $/s:ään (price ~1) → **~32 min $10 000:een = liian hidas demolle.**

## 9. End-to-end jalostusmittaus (place_building nyt toteutettu) — vahvistaa: EI $/s-hyötyä
`place_building type=furnace` + `set_base_filter` on nyt toteutettu (commit 6e50655). Ajoin
end-to-end-mittauksen (mine iron → RAW-vaihe → place furnace → REFINED-vaihe). **Tulos: jalostus ei
tuota $/s-hyötyä missään kokoonpanossa** — kaksi ajoa, molemmat vahvistavat §5:n arvohäviön:

- **Furnace LÄHELLÄ basea (x=720):** REFINED-vaiheen money nousi NOPEAMMIN (~38 $/s vs raw ~10),
  mikä NÄYTTÄÄ jalostushyödyltä — mutta on artefakti: $1164/30 s = 233 IRON myyty → vaatisi 2796
  malmin jalostuksen (mahdotonta furnacen läpisyötöllä). Todellisuudessa **granular-malmi ylivuotaa
  furnacen 6 px intaken ja VALUU basen intakeen → myydään RAAKANA $3/px**; "hyöty" oli vain lyhyemmät
  hauler-reissut (furnace lähempänä louhintaa kuin base). Furnace ei siis jalostanut käytännössä mitään.
- **Furnace KAUKANA basesta (x=440):** prosessi kaatui/tapettiin (exit 137) furnacen sijoituksen
  jälkeen — epävakaus (todennäköisesti CA-alueen/reitityksen laajeneminen kauas). Ei refined-dataa.

**Johtopäätös (2 mekanismia, molemmat = ei hyötyä):**
1. Jos furnace EHTII kuluttaa malmin (läpisyöttö ≥ toimitus): 0,14× arvo → tulo ROMAHTAA (§5).
2. Jos furnace YLIVUOTAA (6 px intake + 12:1 + smelt-cooldown < toimitusnopeus): ylivuoto myydään
   raakana → furnace HYÖDYTÖN (paras tapaus, ~raw).
→ **Jalostus ei koskaan nosta $/s:ää.** Parhaimmillaan neutraali (hyödytön furnace), pahimmillaan
0,14× romahdus. Demon tier-2 "jalostus moninkertaistaa tulon" ei toteudu kummallakaan mekanismilla.
Root cause = resepti (§5); toissijainen ongelma = furnacen läpisyöttö (6 px intake liian pieni).

*(Todiste: `scratchpad/hl_refine.log`, `hl_refine2.log`, `refine_route_test.gd`.)*
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
