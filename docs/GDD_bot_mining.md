# GDD — "Bot Mining" (GodotMining redesign)

**Versio:** 0.1 (luonnos, arkkitehtiluonnos)
**Kohde:** Godot 4.2, GPU falling sand -simulaatio + CPU-agentit
**Status:** Suunnittelu — ei vielä toteutettu

---

## 0. TÄRKEÄ TEKNINEN KORJAUS ENNEN KAIKKEA MUUTA

> **Simulaatioruudukko on koodissa `1664 × 960`, EI `320 × 180`.**
> `pixel_world.gd`: `SIM_WIDTH := 1664`, `SIM_HEIGHT := 960` → **1 597 440 solua**.
> CLAUDE.md ja aiempi konsepti puhuvat 320×180:sta — se on vanhentunut. **Kaikki**
> tässä dokumentissa oleva mitoitus (designaatiogridi, navigaatiogridi, botin nopeus,
> kantokyky, talous) perustuu todelliseen 1664×960-kokoon. CLAUDE.md pitää päivittää.

Seuraukset redesignille:
- Per-pikseli A* on mahdoton (1.6 M solmua) → **pakollinen karkeampi navigaatiogridi**.
- Designaatiot eivät voi olla per-pikseli UI:ssa → **karkea designaatiogridi**.
- GPU-bufferi ladataan kokonaan CPU:lle joka frame jo nyt (`_download_from_gpu`).
  Botit ovat CPU-agentteja jotka lukevat saman `grid`-taulukon → **botit eivät maksa
  mitään GPU-budjetista**. Tämä on redesignin tärkein tekninen etu.

---

## 1. VISIO & CORE LOOP

**Pitch:** Pelaaja ei ole enää sankari kentässä. Pelaaja on kaivosyhtiön johtaja, joka
komentaa robottilaumaa. Maalaat gridiin alueen, jonka botit louhivat automaattisesti;
louhijat hakkaavat malmia maan uumenista, kuljettajarobotit tuovat saaliin pintaan
baseen, joka muuttaa sen rahaksi. Rahalla ostat lisää botteja ja rakennat jalostamon,
joka moninkertaistaa raaka-aineiden arvon. Syvemmältä löytyy arvokkaampaa tavaraa —
mutta matka pintaan pitenee. Peli on logistiikan optimointia elävässä hiekkasimulaatiossa.

**Core loop -kaavio:**

```
        ┌─────────────────────────────────────────────────────────────┐
        │                                                             │
        ▼                                                             │
  MAALAA KAIVUUALUE ──► MINER-botti louhii ──► irtomateriaali kasaan  │
        (designaatio)        (frontier)             (falling sand)     │
                                                        │              │
                                                        ▼              │
                                        HAULER-botti poimii saaliin    │
                                                        │              │
                            ┌───────────────────────────┤              │
                            ▼                           ▼              │
                    (raaka → BASE)              (raaka → JALOSTAMO)     │
                            │                           │              │
                            ▼                     furnace/crusher       │
                        $ RAHA                          │              │
                            │                     pickup point         │
                            │                           ▼              │
                            │                  (jalostettu → BASE)       │
                            │                           │              │
                            ▼                           ▼              │
                        ┌───────────  $$$ RAHA  ◄───────┘              │
                        │                                              │
                        ▼                                              │
                OSTA BOTTEJA / RAKENNA KONEITA / UPGRADET ─────────────┘
                        │
                        ▼
                KAIVA SYVEMMÄLLE (arvokkaampi malmi)
```

**Nollakitkainen aloitus:** Pelin alkaessa kentässä on valmiiksi base pinnalla,
1 miner ja 1 hauler basen vieressä, oletusdump = base. Pelaajan ainoa pakollinen teko
on maalata kaivuualue. Sekunneissa raha alkaa virrata. Kaikki muu (lisäbotit, koneet,
filtterit) on syventävää valinnaista optimointia.

---

## 2. BOTIT

### 2.1 Roolit (yksi rooli / botti — ei molempia)

| Rooli | Tehtävä | Ei tee |
|---|---|---|
| **Miner** | Louhii designoituja soluja frontier-järjestyksessä; muuntaa kiinteät pikselit irtomateriaaliksi | Ei kuljeta tavaraa baseen |
| **Hauler** | Poimii irtomateriaalin pickup-/designaatiovyöhykkeiltä ja kuljettaa dumppiin (base tai koneen input) | Ei louhi kiinteää kiveä |

Roolin voi vaihtaa lennossa (Miner ↔ Hauler) osta/rakenna-paneelista; botti ei tuhoudu,
se vain vaihtaa tilakoneen käyttäytymistä.

### 2.2 Botti agenttina (EI CA-pikselinä)

Botit ovat **CPU-overlay-agentteja**, kuten rakennukset (`building_layer`-Node2D:t),
**eivät** simulaatioruudukon pikseleitä. Perustelu:
- Margolus-CA ei saa "pyyhkiä" bottia pois. Botilla on pysyvä identiteetti + reitti.
- Suorituskyky: kourallinen agentteja päivitetään CPU:lla, ei GPU-passia.
- Malli on jo olemassa: `player.gd` on juuri tällainen (RefCounted-agentti joka lukee
  `grid`:iä ja piirretään overlaynä). `bot.gd` on käytännössä `player.gd`:n perillinen.

**Päätös — lentävät dronet.** Botit leijuvat (8-suuntainen liike vapaassa tilassa) sen
sijaan että tarpeisiin kuuluisi tasohyppely, tikkaat tai painovoimakäsittely. Tämä
poistaa valtaosan reitityksen monimutkaisuudesta: mikä tahansa avoin navigaatiosolu on
läpikuljettava. Teemallisesti perusteltua ("bot/drone mining").

### 2.3 AI-tilakone

```
IDLE ──► (pyydä työ jonosta)
  │                  │
  │            ei työtä → jää IDLEen basen lähelle
  ▼
GET_JOB ──► MOVE_TO_TARGET ──► WORK ──► CARRY ──► DUMP ──► IDLE
                   │              │        │         │
              (A* reitti)   (kaiva/poimi) (täynnä  (pura
                                          tai valmis) dumppiin)
```

**Miner-sykli:** IDLE → varaa lähin louhittava designaatiosolu (frontier) → MOVE_TO
viereiseen avoimeen navigaatiosoluun → WORK: muunna solun kiinteät pikselit
irtomateriaaliksi `mine_rate` px/s tahdilla → kun solu tyhjä, vapauta designaatio ja
hae seuraava.

**Hauler-sykli:** IDLE → etsi lähin irtomateriaali sallitulla pickup-vyöhykkeellä →
MOVE_TO → WORK: imuroi loose-pikselit `carry_capacity` asti → CARRY → valitse dump jonka
filtteri hyväksyy kuorman → MOVE_TO dump → DUMP: pudota kuorma dumpin intake-alueelle →
IDLE.

**Tikkitaajuus:** botti-AI ajetaan CPU-logiikkavaiheessa `_process`:ssa (uusi "Vaihe 5.x"
`pixel_world.gd`:ssä, ks. §8). Reitinlaskenta (A*) tehdään harvakseltaan (esim. joka
0.25 s / botti tai vain kun target vaihtuu), liike joka frame.

### 2.4 Reititys pikselimaailmassa (konkreettinen ratkaisu)

**Kaksitasoinen:**

1. **Navigaatiogridi** (`nav_grid.gd`): 16×16 px navigaatiosolut → **104 × 60 = 6 240
   solmua**. Jokainen navsolu on `OPEN` jos ≥ ~70 % sen pikseleistä on EMPTY/nestettä,
   muuten `SOLID`. Johdetaan CPU:lla `grid`:stä. Ei lasketa joka frame — **dirty-flag**:
   päivitä vain ne navsolut joiden alueella louhinta/fysiikka muutti pikseleitä
   (miner ja fysiikka merkkaavat dirtyn). Full-rebuild vain worldgenin jälkeen.

2. **A*** navigaatiogridillä (6 240 solmua = halpa). Botti seuraa waypointteja; solujen
   välissä suora leijunta. Local steering hoitaa pikselitason (väistä juuri pudonnut
   kivi).

**Louhinnan ja reitityksen suhde (päätös):**
- **Miner ei reititä kiinteän kiven läpi.** Se louhii vain designaatiosoluja jotka ovat
  **saavutettavissa** = joiden viereinen navigaatiosolu on `OPEN`. Näin louhinta etenee
  luonnollisesti avoimesta pinnasta sisäänpäin (Dwarf Fortress / Oxygen Not Included
  -tyyli). Miner *tekee* tunnelin louhimalla designaation — tunneli ON designoitu alue.
- **Umpeen jäänyt designaatio** (ei avointa naapuria) on tilassa `BLOCKED`, näytetään
  himmennettynä, ja aktivoituu automaattisesti kun naapurisolu avautuu.
- **Hauler ei koskaan louhi.** Se kulkee vain `OPEN`-navsoluja pitkin (mukaan lukien
  juuri louhitut designaatiosolut jotka muuttuivat avoimiksi).

Tämä välttää kalliin "kaiva reitti kohteeseen" -ongelman kokonaan.

### 2.5 Kantokyky & upgrade-tierit

Kuorma = **irtopikselien lukumäärä** (esim. 40 px), tallennettuna materiaalikohtaisina
lukuina (`{IRON_ORE: 30, DIRT: 10}`), ei fyysisinä pikseleinä kuormassa.

| Tier | Hauler kapasiteetti | Miner louhintanopeus | Liikenopeus | Erikoisuus |
|---|---|---|---|---|
| **Mk1** | 40 px | 25 px/s | 40 px/s | perus |
| **Mk2** | 90 px | 50 px/s | 70 px/s | — |
| **Mk3** | 180 px | 90 px/s | 110 px/s | Miner: louhii bedrockin viereltä turvallisesti; Hauler: 2 dump-suodatinta muistissa |

Upgrade ostetaan per botti tai globaalina tier-lukituksena (ks. Avoimet kysymykset).
Numeroarvot ovat balanssin lähtöarvoja, hienosäädetään pelaamalla.

---

## 3. TYÖJONO & DESIGNAATIOT

### 3.1 Designaatiogridi (`designation_grid.gd`)

**Päätös — designaatiosolu = 8 × 8 px** → **208 × 120 = 24 960 solua**. Yksi tavu/solu
(≈ 24 KB) → triviaali muistijalanjälki, ladattavissa kokonaan overlay-piirtoon.
Perustelu: 8 px vastaa rakennusgridin `GRID_SIZE = 8` snappia — designaatiot ja
rakennukset kohdistuvat samaan ruudukkoon. 4×4 olisi tarpeettoman hienojakoinen
(99 840 solua) ja 16×16 liian karkea tarkalle louhinnalle.

Solun tilat (enum):
```
NONE     = 0   # ei designaatiota
QUEUED   = 1   # merkitty louhittavaksi, odottaa
BLOCKED  = 2   # louhittava mutta ei saavutettavissa (ei OPEN-naapuria)
CLAIMED  = 3   # miner varannut tämän
MINING   = 4   # louhinta käynnissä
DONE     = 5   # louhittu tyhjäksi (vapautetaan → NONE)
```

Designaatiogridi mäppäytyy CA-gridiin: designaatiosolu (dx,dy) kattaa pikselit
`x ∈ [dx*8, dx*8+8)`, `y ∈ [dy*8, dy*8+8)`.

### 3.2 Louhintatyön syntyminen ja jako minereille

- Kun pelaaja maalaa alueen → kyseiset designaatiosolut `QUEUED`.
- Joka AI-tikki: `job_system` skannaa `QUEUED`-solut ja merkkaa `BLOCKED`/louhittaviksi
  navigaatiogridin `OPEN`-naapuruuden perusteella (vain reunaskannaus, ei koko gridiä).
- Vapaa miner pyytää työn: **lähin louhittava solu** botin sijainnista (heuristiikka:
  Manhattan-etäisyys navsoluina). Varattu solu → `CLAIMED`, ei muille.
- **Työvarkaus:** jos miner on idlenä ja lähempänä toisen minerin `CLAIMED`-solua kuin
  varaaja, ja varaaja ei ole vielä aloittanut (`MINING`), varaus voi siirtyä. MVP:ssä
  yksinkertaisempi: ei työvarkautta, vain "lähin vapaa vapaalle". Lisätään myöhemmin jos
  botit ruuhkautuvat.

### 3.3 Hauler-työn syntyminen

Hauler-työ = "on olemassa poimittavaa irtomateriaalia sallitulla vyöhykkeellä".
Lähteet:
1. **Irtopikselit designaatioalueella** — louhittu materiaali joka on valunut kasaan.
2. **Pickup-pointtien vyöhykkeet** — esim. jalostuskoneen output-pään alue.

`job_system` ylläpitää kevyttä "loose material -indeksiä": skannaa pickup-/designaatio-
vyöhykkeet harvakseltaan (esim. joka 0.5 s) ja pitää listaa kasoista (navsolu + arvioitu
px-määrä + dominoiva materiaali). Hauler varaa lähimmän kasan jonka materiaalin jokin
dump hyväksyy.

---

## 4. LOGISTIIKKA

### 4.1 Base / Money box

Base on laajennettu `MoneyExit` (§8 mapping): intake-vyöhyke jonne haulerit purkavat,
muuntaa materiaalin rahaksi (`money += PRICES[mat]`). Base on samalla:
- **Bottien spawn-piste** (ostetut botit ilmestyvät basesta).
- **Oletusdump** — pelin alussa kaikki botit dumppaavat kaiken tänne.

### 4.2 Dump-pisteet ja filtterit

**Dump** = kohde jonne hauler saa purkaa kuorman. Jokaisella dumpilla on
**materiaalisuodatin** (mitä materiaaleja saa purkaa):
- **Base**: oletus = kaikki (raha). Voi rajata (esim. "vain jalostettu") ohjatakseen
  raakamalmin jalostamoon.
- **Koneen input-dump** (furnace/crusher intake): filtteri = koneen reseptin inputit
  (esim. furnace = `IRON_ORE, GOLD_ORE, SAND`).

Filtteri on bittimaski materiaali-ID:istä. Hauler valitsee kuormalleen dumpin jonka
filtteri hyväksyy suurimman osan kuormasta ja on lähinnä.

### 4.3 Pickup-pointit

**Pickup-point** = asetettava vyöhyke (säde tai laatikko) jolta haulerit hakevat
irtomateriaalia. Käyttö: koneen output-pään viereen → haulerit vievät jalostetun
tuotteen eteenpäin (baseen tai seuraavaan koneeseen). Parametrit:
- Sijainti + koko (esim. 24×24 px oletus).
- Materiaalisuodatin (mitä poimitaan; oletus kaikki).
- Prioriteetti (valinnainen; korkea prio = haetaan ensin).

### 4.4 Liukuhihnat + jalostuskoneet (säilyvät)

Nykyinen `conveyor_belt.gd`, `furnace.gd`, `crusher.gd`, `money_exit.gd` toimivat
sellaisenaan — ne liikuttavat/muuntavat pikseleitä CA-gridissä. Integraatio botteihin:
- **Hauler → koneen input:** hauler purkaa raakamalmin koneen intake-aukon päälle
  (dump-piste koneen intakessa). Kone kerää ja jalostaa (jo olemassa).
- **Kone → pickup-point → hauler:** koneen output pudottaa jalostetun (jo olemassa,
  `_spawn_smelted_body` / `_spawn_crusher_output`), pickup-point outputin alla → hauler
  vie baseen.
- **Hihna vaihtoehtona haulerille:** lyhyillä väleillä liukuhihna voi korvata haulerin
  (input → kone → output → base). Pelaaja valitsee: hihna = kertainvestointi, ei tarvitse
  bottia; hauler = joustava mutta sitoo botin. Molemmat validit — emergentti optimointi.

---

## 5. KARTTA & WORLD GEN

Nykyinen `world_gen.gd` on **jo lähellä haluttua** — luolat on jo kytketty pois
(`_generate_caves` kommentoitu), pinta on suht tasainen ja materiaalit kerrostuvat
syvyyden mukaan. Tarvittavat muutokset ovat pieniä.

### 5.1 Nykytila (säilyy)

- Koko 1664×960, pinta n. 40 % korkeudella (`base_y = h*0.40`), multakerros 5 px, sitten
  kivi. Reunat + pohja bedrockia (tuhoamaton).
- Syvyyskerrostuneet malmiblobit (normalisoitu syvyys pinnasta, `max_dp = h*0.60`):

| Materiaali | Syvyysvyöhyke | Arvo (raaka) |
|---|---|---|
| Hiekka (SAND) | 0.00–0.25 | matala |
| Hiili (COAL) | 0.10–1.0 | matala |
| Rautamalmi (IRON_ORE) | 0.05–0.80 | keski |
| Öljy (OIL) | 0.30–1.0 | (poltto/erikois) |
| Kultamalmi (GOLD_ORE) | 0.45–1.0 | korkea |

### 5.2 Muutokset

1. **Loivempi pinta:** pienennä `_generate_terrain`:n amplitudeja (`low*90` → `low*40`)
   jotta pinta on tarpeeksi tasainen tehdas-alustalle. Säilytä pientä vaihtelua visuaaliksi.
2. **Tehdas-alusta pinnalle:** tasoita ~300 px levyinen alue kartan keskeltä pinnan
   tasolle (base + koneet mahtuvat). Kirjoita ohut bedrock/kivi-alusta jottei tehdas vaju.
3. **Syvyys = arvo -periaate terävämmäksi:** varmista ettei kultaa/arvokasta ole ~ylimmän
   kolmanneksen sisällä → pelaajan on pakko kaivaa syvälle. Nykyiset syvyysvyöhykkeet ovat
   jo ok; hienosäädä `gold_depth` ylöspäin (arvokkaampi = syvemmällä).
4. **Bedrock-pohja pysyy** turvarajana (`_enforce_edges`). Syvin kerros juuri bedrockin
   päällä = arvokkain "endgame"-malmi (uusi materiaali myöhemmin, esim. platina).
5. **Kasvillisuus (WOOD-ruoho/pensaat) valinnainen** — visuaalinen, ei toiminnallinen;
   voi jättää tai poistaa. Ei kriittinen.

Ei uusia noise-algoritmeja tarvita — vain parametrisäätöjä ja yksi tasoitusfunktio.

---

## 6. MATERIAALIT & TALOUS

### 6.1 Materiaalit (nykyiset, säilyvät)

`EMPTY=0, SAND=1, WATER=2, STONE=3, WOOD=4, FIRE=5, OIL=6, STEAM=7, ASH=8,`
`WOOD_FALLING=9, GLASS=10, DIRT=11, IRON_ORE=12, GOLD_ORE=13, IRON=14, GOLD=15,`
`COAL=16, GRAVEL=18, BEDROCK=19`

Louhinnan tuottama "irtomuoto": louhittaessa kiinteä pikseli muuntuu granulaariseksi
(putoavaksi) muodoksi joka valuu kasaan ja on haulerin poimittavissa. Mäppäys:
- STONE → GRAVEL (jo olemassa, murskattava crusherissa hiekaksi)
- DIRT → DIRT (kohdellaan granulaarisena; tarkista CA-käytös)
- IRON_ORE/GOLD_ORE/COAL/SAND → säilyttävät ID:n, putoavat (SAND putoaa jo)

> **Huom (avoin):** DIRT/malmien CA-putoamiskäytös pitää varmistaa shaderista. Jos malmi
> ei putoa CA:ssa, joko (a) lisätään putoamissääntö `simulation.glsl`:ään, tai (b) miner
> muuntaa louhitun malmin abstraktiksi kasaksi joka ei hajoa. Suositus: (a) — pysyy
> engine-linjassa. Ks. §10.

### 6.2 Jalostusketjut & arvokertoimet

Nykyiset reseptit (säilyvät):

| Kone | Input → Output | Arvo raaka → jalostettu |
|---|---|---|
| Furnace | 16× SAND → GLASS | 1 → 3 (3×) |
| Furnace | 12× IRON_ORE → IRON | 3 → 5/px (yli 15× per input-batch) |
| Furnace | 8× GOLD_ORE → GOLD | 5 → 12/px (~19×/batch) |
| Crusher | 1× GRAVEL → 3× SAND | välivaihe (kiven kierrätys) |

### 6.3 Hinnasto (lähtöarvot, `PRICES` päivitys)

Raaka-aineet (money box):

| Materiaali | $/px |
|---|---|
| DIRT, SAND, STONE, GRAVEL | 1 |
| COAL | 2 |
| IRON_ORE | 3 |
| GOLD_ORE | 5 |
| GLASS (jalostettu) | 3 |
| IRON (jalostettu) | 5 |
| GOLD (jalostettu) | 12 |

Rakennukset & botit (osto):

| Tuote | Hinta | Huom |
|---|---|---|
| Botti (Miner tai Hauler) | 300 (nouseva) | 3. botti; hinta +50 % / seuraava |
| Hihna | 50 | per segmentti (nykyinen) |
| Furnace | 150 | nykyinen |
| Crusher | 120 | nykyinen |
| Pickup-point | 80 | uusi |
| Dump-point (extra) | 60 | uusi |
| Upgrade Mk1→Mk2 | 400 | per botti |
| Upgrade Mk2→Mk3 | 900 | per botti |

Myynti palauttaa 50 % (nykyinen mekaniikka säilyy).

### 6.4 Karkea balanssi — "eka bottiosto ~2–3 min"

Lähtötilanne: 1 miner (25 px/s) + 1 hauler (40 px kuorma, 40 px/s) pintakerroksen
dirt/stone (arvo 1/px) kimpussa. Arvio:
- Hauler-kierros lähellä pintaa ~10–14 s (matka + poiminta + purku) → ~3 px/s
  toimitettuna → **~$3/s**.
- 2 min → ~$360, 3 min → ~$540.
- 3. botti $300 → **saavutettavissa ~1.7–2 min kohdalla**. ✅ Osuu tavoitteeseen.

Kun pelaaja kaivaa syvemmälle rautaan/kultaan ja rakentaa jalostamon, $/s
moninkertaistuu → eksponentiaalinen kasvukäyrä joka rahoittaa laajemman lauman ja
Mk2/Mk3-upgradet. Kaikki numerot ovat säädettäviä; nämä ovat aloituspiste.

---

## 7. UI

### 7.1 Osta/rakenna-paneeli (strategiapelityyli)

Korvaa nykyisen materiaalimaalaus-palkin (`ui.gd`) pelaajakäytössä (materiaalimaalaus
jää debug-menuun). Uusi paneeli, välilehdet:

- **Botit:** osta Miner / osta Hauler (hinta näkyy), lista boteista, per-botti Mk-upgrade.
  Globaalit +/- säätimet: "Minereitä: [-] N [+]", "Hauler: [-] M [+]" (muuntaa roolia
  lennossa lauman sisällä).
- **Rakennukset:** Furnace, Crusher, Hihna, (Drill valinnainen). Klikkaa → sijoitustila
  (nykyinen `build_mode`-logiikka).
- **Logistiikka:** Pickup-point, Dump-point, Base-filtteriasetukset. Klikkaa → sijoita
  vyöhyke; valittu vyöhyke → filtteri-checkboxit materiaaleille.

### 7.2 Kaivuumaalaustyökalu

Kolme moodia (näppäin tai paneelin nappi):
- **Yksittäinen solu:** klikkaa → toggle designaatio yhteen 8×8-soluun.
- **Laatikkoveto:** paina + vedä → suorakulmainen alue designoiduksi (kuten valintalaatikko).
- **Pensseli:** pidä pohjassa + liikuta → maalaa säteellä (pensselin koko liukurilla,
  nykyinen `brush_size` uusiokäyttö).

Oikea hiiri = poista designaatio (sama moodi käänteisenä).

### 7.3 Overlayt & näytöt

- **Designaatio-overlay:** puoliläpinäkyvä värikoodi designaatiosoluille (QUEUED = keltainen,
  BLOCKED = himmeä punainen, MINING = vihreä pulssi). Piirretään `building_layer`-tyylisenä
  overlaynä, skaalattuna grid→screen.
- **Botti-visualisointi:** jokainen botti piirretään pienenä spritenä (Miner vs Hauler eri
  väri/ikoni); valinnainen reittiviiva debugissa. Kuormaindikaattori (täyttöaste).
- **Resurssi- & rahanäyttö:** raha (nykyinen `money_label`) + valinnainen live "$/s"
  -mittari. Bottien tila (idle/working) yhteenlaskettuna: "Miner 2/3 aktiivista".
- **Materiaaliskanneri** (`ui.gd`, olemassa) säilyy hyödyllisenä syvyyskartoituksessa.

---

## 8. TEKNINEN MÄPPÄYS

| Nykyinen järjestelmä | Kohtalo | Perustelu |
|---|---|---|
| GPU CA-sim (`simulation.glsl`, 8 passia, sim_speed) | **SÄILYY** | Ydin. Louhittu materiaali käyttäytyy sim:ssä (valuu kasaan). |
| `transfer.glsl`, `pixel_render.gdshader` | **SÄILYY** | Renderöinti ennallaan. |
| CPU-download joka frame (`_download_from_gpu`) | **SÄILYY** | Botit lukevat `grid`:iä tästä — ei lisä-GPU-kuormaa. |
| `physics_world.gd` (rigid bodyt) | **SÄILYY** | Louhinta aiheuttaa kivipalojen putoamista/sortumia — emergenttiä syvyyttä. |
| `ccl.gd`, `wood_support.gd`, `rigid_body_data.gd` | **SÄILYY** | Fysiikan tukirakenne. |
| `conveyor_belt.gd` | **SÄILYY** | Logistiikan vaihtoehto haulerille. |
| `furnace.gd`, `crusher.gd` | **SÄILYY** | Jalostusketju, botti-integraatio dumppien kautta. |
| `money_exit.gd` | **MUOKATAAN → Base** | Lisää: spawn-piste, oletusdump, materiaalifiltteri. |
| `world_gen.gd` | **MUOKATAAN** | Loivempi pinta, tehdas-alusta, syvyys=arvo terävämmäksi (§5). |
| `ui.gd` | **MUOKATAAN raskaasti** | Osta/rakenna-paneeli, välilehdet, designaatiotyökalu. |
| `build_preview.gd` | **MUOKATAAN** | Lisää designaatio-/vyöhyke-esikatselu. |
| `pixel_world.gd` `_process`-logiikka | **MUOKATAAN** | Uusi "Vaihe 5.x": bot_manager.tick + designaatio-input. |
| `player.gd` (sprite/jetpack) | **POISTUU pelistä** | Sankari poistuu. Koodi = pohja `bot.gd`:lle; vapaakamera on jo olemassa. |
| Aseet (rifle/rocket/gravity gun) | **DEBUG-ONLY** | Jo stubattu; siirretään debug-menuun. |
| Pommit/räjähdykset | **DEBUG-ONLY** | Hyödyllinen testaus; ei core gameplay. |
| `launcher.gd` / `sling.gd` (hissilinko) | **POISTUU coresta** | Haulerit + hihnat korvaavat. Voi jättää valinnaiseksi. |
| `sand_mine.gd` (ääretön hiekkalähde) | **POISTUU** | Ristiriidassa louhintatalouden kanssa. |
| `drill.gd` (putoava autoporata) | **VALINNAINEN / DEMOTE** | Voi jäädä late-game "auto-miner -rakennukseksi"; ei MVP. |
| `chicken_spawner.gd` | **POISTUU** | Ei liity konseptiin. |

**Uudet tiedostot:**

| Tiedosto | Vastuu |
|---|---|
| `scripts/bot.gd` | Yksittäisen botin data + tilakone (rooli, tila, pos, cargo, target). RefCounted, pohjautuu `player.gd`:hen. |
| `scripts/bot_manager.gd` | Kaikkien bottien päivitys, osto/spawn, roolinvaihto, tikki `_process`:sta. |
| `scripts/designation_grid.gd` | 208×120 designaatiogridi, tilat, overlay-piirto, grid↔pikseli-mäppäys. |
| `scripts/nav_grid.gd` | 104×60 walkability-gridi + A*. Dirty-flag-päivitys. |
| `scripts/job_system.gd` | Louhinta- ja haul-työjonot, työn jako, loose-material-indeksi. (Voi olla osa bot_manageria.) |
| `scripts/logistics.gd` | Base, dump-pisteet, pickup-pointit, filtterit. |

**Ratkaisut mitoitukseen (kootusti):**
- Designaatiogridi: **8×8 px → 208×120** (matches building GRID_SIZE).
- Navigaatiogridi: **16×16 px → 104×60** (A* halpa, 6 240 solmua).
- Botit: **overlay-agentteja**, ei CA-pikseleitä.
- Botti-määrä realistinen ylä: kymmeniä (esim. cap 50) — kaikki CPU:lla, halpaa.

**Push constant -budjetti:** bottilogiikka ei kosketa shadereita → ei push constant
-painetta. Louhinta kirjoittaa `grid`:iin CPU:lla (kuten `drill.gd` jo tekee), lataus
GPU:lle olemassa olevalla `_upload_paint_to_gpu`-polulla (`paint_pending`).

---

## 9. MVP-VAIHEISTUS

### Vaihe 1 — Pelattava ydin (designaatio + 2 bottia + base)

**Sisältö:**
- `nav_grid.gd` + A* (leijuva liike).
- `designation_grid.gd` + maalaustyökalu (yksittäinen solu + laatikkoveto) + overlay.
- `bot.gd` + `bot_manager.gd`: 1 miner + 1 hauler, tilakoneet, cargo.
- Miner louhii frontier-designaatioita → irtomateriaali kasaan.
- Hauler poimii irtomateriaalin designaatioalueelta → kuljettaa baseen.
- Base = muokattu `money_exit`, oletusdump, raha kertyy.
- Worldgen: loiva pinta + tehdas-alusta + base valmiiksi pinnalla.

**Definition of Done:**
1. Käynnistys → base + 1 miner + 1 hauler näkyvissä pinnalla.
2. Maalaa alue → miner alkaa louhia sekunneissa, hauler tuo saaliin baseen, raha nousee.
3. Ei kaatumisia; 60 fps 1664×960:llä tyypillisellä designaatiomäärällä.
4. Botit eivät jää jumiin (umpeen jäänyt designaatio → BLOCKED, ei loop).

### Vaihe 2 — Osta/rakenna-paneeli, lisäbotit, pickup-pointit

**Sisältö:**
- `ui.gd`-paneeli välilehdillä (Botit / Rakennukset / Logistiikka).
- Bottien osto (spawn basesta) + Miner/Hauler +/- assignment.
- Pickup-pointtien sijoitus (`logistics.gd`) + hauler hakee niiltä.
- Hihnojen sijoitus paneelista (nykyinen logiikka kytketty paneeliin).
- Työvarkaus / parempi työnjako jos ruuhkaa.

**Definition of Done:**
1. Osta 3. botti → ilmestyy basesta, alkaa toimia.
2. Muuta miner/hauler-suhdetta paneelista → botit vaihtavat roolia lennossa.
3. Aseta pickup-point → hauler hakee sen vyöhykkeeltä.
4. Talous skaalautuu (enemmän botteja = enemmän $/s), hinnat nousevat oston myötä.

### Vaihe 3 — Jalostusintegraatio, dump-filtterit, upgrade-tierit

**Sisältö:**
- Dump-filtterit (base + koneiden input-dumpit) UI:ssa.
- Reititys: hauler vie raakamalmin furnaceen/crusheriin → pickup outputilla → base.
- Upgrade-tierit Mk1/Mk2/Mk3 (kapasiteetti, nopeus, erikoisuudet).
- Syvyys=arvo -balanssi hiottu; syvät kerrokset kannattavia.

**Definition of Done:**
1. Rakenna furnace, aseta dump-filtteri (vain IRON_ORE) intakeen + pickup outputiin →
   IRON_ORE jalostuu IRONiksi ja tuottaa ~5× raakaan verrattuna.
2. Upgradea botti Mk2 → mitattava kapasiteetti-/nopeusparannus.
3. Kaivaminen kultakerrokseen (syvä) on selkeästi kannattavampaa kuin pintadirt.
4. Base-filtteri ("vain jalostettu") ohjaa raakamalmin koneelle automaattisesti.

---

## 10. AVOIMET KYSYMYKSET (kukin suosituksen kera)

1. **Resurssimalli: irtopikselit vs. abstrakti kuorma.**
   *Suositus:* Louhittu materiaali = oikeita CA-irtopikseleitä jotka valuvat kasaan;
   hauler imuroi ne. Pysyy engine-linjassa ja on visuaalisesti tyydyttävää. Fallback jos
   kasojen poiminta on epädeterminististä: miner deponoi abstraktiin "malmikasaan" (ei-
   simuloitu overlay-klusteri). **Aloita irtopikseleillä, pidä fallback varalla.**

2. **Malmien CA-putoamiskäytös.** DIRT/IRON_ORE/GOLD_ORE/COAL — putoavatko ne
   `simulation.glsl`:ssä? *Suositus:* varmista shaderista; jos eivät, lisää
   putoamissääntö (kuten SANDilla). Tämä on **Vaiheen 1 este** ja pitää selvittää heti.

3. **Botit: lentävät dronet vs. kävelevät.** *Suositus:* **lentävät dronet** — poistaa
   tasohyppelyn ja tikkaat, tekee reitityksestä 8-suuntaisen. Teema tukee tätä.

4. **Grid-koko 1664×960 vs. 320×180.** *Suositus:* pidä **1664×960** (koodin totuus),
   päivitä CLAUDE.md. Jos performanssi ei riitä boteille + CA:lle, harkitse pienempää
   maailmaa erikseen — mutta älä oleta 320×180.

5. **Designaatiosolun koko 8×8.** *Suositus:* **8×8** (matches GRID_SIZE). Vahvista
   pelituntumalla; helppo vaihtaa vakiona.

6. **Sortumat & botit.** Louhinta voi pudottaa kiveä (physics_world) haulerin/minerin
   päälle. *Suositus:* Vaiheessa 1 botit ovat overlay-agentteja ja **immuuneja
   murskautumiselle**; Vaiheessa 3 harkitse "botti voi jäädä jumiin/tuhoutua sortumassa"
   -mekaniikkaa lisäsyvyydeksi (kallis mutta jännittävä).

7. **Upgrade: per-botti vs. globaali tier-lukitus.** *Suositus:* **per-botti** upgrade
   antaa hienojakoisemman talouspäätöksen; globaali tier on yksinkertaisempi UI. Aloita
   per-botti, arvioi UI-kuorma.

8. **Poistuvat järjestelmät (launcher/sand_mine/drill/aseet).** *Suositus:* poista
   `sand_mine`, `chicken_spawner`; siirrä aseet/pommit/räjähdykset debug-menuun; jätä
   `launcher` ja `drill` valinnaisiksi (älä kytke MVP:hen). Vahvista ettei mikään UI/
   worldgen-polku riko poiston yhteydessä.

9. **Yksi vai useampi base.** *Suositus:* **yksi base** MVP:ssä. Useampi base + oma
   spawn/dump per base on luonteva laajennus mutta ei tarpeen ydinsilmukalle.

10. **Loose-material-poiminnan determinismi.** Jos irtopikselit hajoavat/valuvat liikaa
    ennen kuin hauler ehtii, hauling muuttuu epäluotettavaksi. *Suositus:* pickup-vyöhyke
    "scooppaa" kaikki sallitut irtopikselit säteeltä (ei yksittäisiä pikseleitä jahdaten),
    ja miner deponoi louhitun kompaktiksi kasaksi juuri louhintakohdan reunalle. Testaa
    Vaiheessa 1.