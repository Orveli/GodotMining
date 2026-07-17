# SPEC: Planeetta — rullattu maailma (polaariprojektio)

**Versio:** 1.0 · **Laatija:** game-architect · **Tila:** toteutettavaksi (P1–P6)
**Kohde:** Opus-ohjelmoija-agentit, worktree-rinnakkaisuus branchilta `feature/planet` (haarautuu
781e80c:stä). Jokainen moduuli P1–P6 on itsenäisesti toteutettava ja testattava. Lue tämä koko
dokumentti ennen oman moduulisi aloittamista, mutta toteuta VAIN oman moduulisi osuus. Moduulien
väliset sopimukset ovat luvussa 5 — älä riko niitä.

> **Tyyliohje:** noudata KUNKIN tiedoston olemassa olevaa kommenttityyliä. Bottisim-tiedostot
> (`bot.gd`, `bot_manager.gd`, `logistics.gd`, `nav_grid.gd`, `designation_grid.gd`, `ccl.gd`,
> `physics_world.gd`, `wood_support.gd`, `light_field.gd`, uusi `planet_geom.gd`) ovat **ASCII-only**
> (ei ääkkösiä kommenteissa). `pixel_world.gd`, `ui.gd`, `world_gen.gd` käyttävät ä/ö:tä — jatka
> samalla tyylillä. Tyyppivihjeet aina, snake_case, `UPPER_CASE` vakiot, signaalit `.connect()`:lla.

> **Committaa AIKAISIN ja USEIN.** Jokainen moduuli on mitoitettu ~40 työkalukutsuun (vuoraja ~55).
> Tee jokaisesta loogisesta osavaiheesta oma commit — älä pidä koko moduulia yhdessä isossa diffissä.
> Jos urakka venyy, keskeneräinenkin commit on parempi kuin vuorajaan kaatuminen ja menetetty työ.

---

## 0. Toteutusjärjestys, rinnakkaisuus ja merge-juna

**Tämä on kaikkien moduulien tärkein luku — lue ensin.**

Simulaatioruudukko pysyy suorakulmaisena. **x = kulma planeetan ympäri (wräppää: x=0 ja x=W-1 ovat
naapureita), y = syvyys kohti keskipistettä (y+1 = kohti ydintä, EI wräppää).** Simulaation "alas"
on radiaalinen sisäänpäin, joten Margolus-säännöt ja falling sand -logiikka EIVÄT muutu — muuttuu vain
x-suunnan wräppäys ja renderöinnin polaarimuunnos.

### Aallot ja riippuvuudet

```
  AALTO 1 (rinnakkain, disjunktit tiedostot):
    P1  Sim wrap (GPU + CPU-CA) ....... shaders/simulation.glsl, pixel_world.gd (vain _step_cpu_ca),
                                        UUSI scripts/planet_geom.gd  <-- jaettu wrap-kontrakti
    P2  World gen sylinterijatkuvuus .. world_gen.gd (yksin)
    P3  Bottijarjestelmien wrap ....... nav_grid.gd, designation_grid.gd, bot_manager.gd,
                                        bot.gd, logistics.gd (yksin)
    P4  Fysiikka + fog wrap ........... ccl.gd, physics_world.gd, wood_support.gd, light_field.gd (yksin)

              |  (kaikki 4 mergataan masteriin: feature/planet)
              v
  AALTO 2:
    P5  Polaarirenderi + kamera + koordinaattimuunnokset
        ................................ pixel_world.gd (render/kamera/hiiri/scenepuu),
                                        shaders/pixel_render.gdshader, UUSI scripts/planet_camera.gd,
                                        paascene (main.tscn / vastaava)
              |
              v
  AALTO 3:
    P6  Ohjaus + UI-sopeutus + intro
        ................................ pixel_world.gd (input + intro), ui.gd
```

### Rinnakkaisuussäännöt

- **Aalto 1 (P1–P4) ajetaan täysin rinnakkain omissa worktree-branchoissaan.** Niiden tiedosto-omistus
  on disjunkti (ainoa jaettu tiedosto `pixel_world.gd`: P1 koskee VAIN `_step_cpu_ca`-runkoa; muut
  P2–P4 eivät koske `pixel_world.gd`:tä lainkaan). **P1 luo `planet_geom.gd`:n ENSIN ja pushaa sen** —
  P3 ja P4 nojaavat sen staattisiin apufunktioihin (luku 5). Jos P3/P4 aloittaa ennen kuin
  `planet_geom.gd` on saatavilla, ne saavat kopioida signatuurit luvusta 5 ja olettaa tiedoston
  ilmestyvän merge-junassa.
- **P5 alkaa vasta kun P1–P4 on mergattu** `feature/planet`iin. P5 on renderöinnin ydin ja koskee
  `pixel_world.gd`:n kamera-/hiiri-/render-osioita raskaasti — ajamalla se yksin aallossa 2 vältetään
  merge-konfliktit kaikkien muiden kanssa.
- **P6 alkaa vasta kun P5 on mergattu.** P6 kuluttaa P5:n `PlanetCamera`-muunnokset (ohjaus, popover-
  sijoittelu, intro).

### Integraattorin merge-junajärjestys

1. `P1` (sisältää `planet_geom.gd`) → 2. `P2` → 3. `P3` → 4. `P4` → **verifioi headless
(`bash tests/run_all.sh`) vihreä** → 5. `P5` → **ikkunallinen verifiointi (polaarirender näkyy,
sauma huomaamaton, kamera pyörii)** → 6. `P6` → **ikkunallinen verifiointi (A/D pyöritys, W/S syvyys,
zoom, popoverit kohdallaan, intro)**.

Ikkunallinen verifiointi on **integraattorin** vastuulla — agentit eivät voi ajaa ikkunallista
Vulkania eivätkä simuloida hiirtä. Agentit todistavat oman moduulinsa headless-skenaarioilla ja
yksikkötesteillä; kaikki visuaalinen jää integraattorin tarkistettavaksi.

### Moduulien yhden rivin tiivistelmä

| Moduuli | Tiivistelmä |
|---|---|
| **P1** | simulation.glsl x-modulo + CPU-CA wrap + jaettu `planet_geom.gd` (wrap/etäisyys/polaari-apurit). W pariton kielletty. |
| **P2** | world_gen sylinterijatkuva pinta (kohina ympyrällä), x-reunabedrock pois, bedrock-ydinrengas + syvyys, suonet/blobit wräppäävät. |
| **P3** | nav A* + oktiili-heuristiikka wräppää sauman yli; bottien liike/separaatio/etäisyydet/skannaus/designaatio toroidaalisia; NW/NH johdetaan koosta. |
| **P4** | CCL toroidaalinen; light_field-blur+emitterit wräppäävät; wood_support wräppää; physics rigid body -saumasääntö (v1-rajaus). |
| **P5** | SubViewport-komposiitti → polaarilämärrender (pixel_render), `PlanetCamera` (kulma/säde/zoom), käänteispolaari hiiri→grid, eteenpäin grid→ruutu, ydinmöhkäle. |
| **P6** | A/D pyörittää planeettaa, W/S säteittäin, zoom (pinta↔koko pallo), ui.gd zoom/rotaatio + popover-sijoittelu uudella muunnoksella, laskeutumisintro planeetalle. |

---

## 1. Visio ja tekniset päätökset (sitovat)

Koko pikselimaailma on **jättimäinen pallo — oikea planeetta, vetovoima keskipisteeseen päin.**
Planeettaa kaivetaan kuten nykyistä maailmaa. Nykyinen seed-ship-pelisisältö (inventaariotalous,
bottireplikaatio, akut/laturit, haamumoduulit, laskeutumisintro — `docs/SPEC_seed_ship.md`, kaikki
toteutettu HEAD 781e80c:ssä) **säilyy toimivana planeetalla.**

**Valittu tekninen ratkaisu — "rullattu maailma":**

1. **Sim-ruudukko pysyy suorakulmaisena.** x = kulma, y = syvyys. Simulaation painovoima on ruudukon
   +y (kohti ydintä). Ei aitoa säteittäistä per-pikseli-painovoimaa, ei sektorilohkotusta — **hylätty.**
2. **x-suunnan wräppäys** compute shaderissa (modulo-indeksointi). Maailma kiertyy saumatta.
   Margolus-offset-logiikka säilyy (ks. §6, W-pariteettivaatimus).
3. **Renderöinti: käänteinen polaarimuunnos fragmenttishaderissa.** Ruutupikseli → (kulma, säde) →
   (u,v) → sim-sisältö. Pinta = ulkokehä, ydin = keskellä. **P5 tarkentaa lead-briefin "raakaan
   sim-tekstuuriin" verrattuna:** polaarimuunnos tehdään **komposoidulle SubViewport-tekstuurille**
   (terrain + kaikki Node2D-overlayt), EI raakaan grid-tekstuuriin. Perustelu luvussa §2.3 — ilman
   tätä botit/designaatiot/esikatselut (lineaariset Node2D-lapset) eivät osuisi polaariin.

**Syvyysvääristymän fix (sitova):**
- **Bedrock-ydinrengas** alkaa ~65 % syvyydestä (P2).
- Aivan ytimessä ruudukosta **IRTI** oleva iso rikkoutumaton **ydinmöhkäle** (core object) joka peittää
  keskipisteen singulariteetin. Piirretään polaarinäkymän keskelle levynä (P5). Kevyt pelimekaaninen
  rooli: syvin kaivuu **törmää** siihen (bedrock-renkaan alla ei pääse pidemmälle) → myöhemmin
  mysteeriobjekti. Ei paisuteta scopea v1:ssä.

---

## 2. Polaarigeometria ja kokopäätös

### 2.1 Koordinaattimuunnos (kanoninen — `planet_geom.gd` toteuttaa, P5 käyttää)

Olkoon sim-ruudukko `W × H` (leveys × korkeus). Määritellään pinnan säde niin että
**pikselit ovat neliömäisiä pinnalla** (yksi grid-x = yksi ruutupikseli kulman suunnassa pinnalla):

```
R_surface = W / (2*PI)            # pinnan sade px (ulkokeha)
R_inner   = R_surface - H         # ytimen sade px (ydinmohkaleen sade); VAADITAAN > 0
r(y)      = R_surface - y         # grid-y -> sade (lineaarinen, neliopikselit pinnalla)
theta(x)  = (x / W) * 2*PI        # grid-x -> kulma [0, 2PI)
```

Käänteismuunnos (renderöinti, hiiri): ruudun keskipisteestä `C` mitattu pikseli `p`:
```
d      = p - C                    # kameran skaalaus/rotaatio huomioituna (P5)
r      = length(d)
theta  = atan2(d.y, d.x)
grid_y = R_surface - r
grid_x = wrap( theta / (2*PI) * W )      # + kameran kulmaoffset, modulo W
```
`r > R_surface` → taivas/avaruus (renderöi taustaväri/tähdet). `r < R_inner` → ydinmöhkäle (P5 piirtää
levyn; ei sim-sisältöä). `grid_x` wräpätään aina `[0, W)`; `grid_y` clampataan `[0, H)`.

**Vaatimus:** `R_inner > 0`, ts. `H < W / (2*PI)`. Ellei tämä päde, ydin invertoituu — valitse koko
sen mukaan (§2.2).

### 2.2 Kokopäätös (v1)

Nykyinen ruudukko 1664×960 EI kelpaa planeetaksi: `H=960 > R_surface = 1664/2π ≈ 265`, joten
`R_inner < 0` (ydin invertoituisi). Koko on valittava planeetta-proportioiden mukaan.

Rajoitteet (edellisestä perf-analyysistä): nykykoko 1664×960 ≈ 1,6M solua toimii; ~2,5× (≈4M) toimii
suoraan nykyarkkitehtuurilla; ~6× vaatii GPU-passien harvennusta; ~28×+ vaatii chunkatun simin (EI
tähän versioon). Rajoittava tekijä: 12 passia/frame kaikille soluille + koko puskurin CPU↔GPU-synkka
maalauksen jälkeen (nyt ~6,4 MB) + CPU-järjestelmät skaalautuvat pinta-alan mukana.

**PÄÄTÖS: v1 ruudukko = `W = 4096`, `H = 448`.**

| Suure | Arvo | Perustelu |
|---|---|---|
| Solumäärä | 4096×448 = **1,83M** (≈1,15× nykyinen) | perf-turvallinen, selvästi alle 2,5× budjetin |
| `R_surface` | 4096/2π ≈ **652 px** | |
| `R_inner` (ydinmöhkäle) | 652−448 = **204 px** (0,31·R_surface) | keskikompressio ~0,31 — hyväksyttävä; möhkäle peittää sisimmän 31 % säteestä |
| Mineraalisyvyys | 448 px radiaalinen; bedrock-ydinrengas ~65 % → y≈291 | |
| Molemmat 16-jaollisia | 4096=16·256, 448=16·28 | nav/desig-solut (16 px) menevät tasan; W parillinen (Margolus) |

**Skaalausvara (integraattorin päätös, jos perf sallii):** `W = 4992, H = 544` (2,72M solua ≈1,7×,
R_surface≈794, R_inner≈250, syvyys 544). Molemmat 16-jaollisia. Pysyy alle 2,5× budjetin ja antaa
isomman, syvemmän planeetan. **Älä** ylitä ~4M solua ilman GPU-passien harvennusta.

**Milestone 0 -optio (nopea perf/pipeline-todiste):** P5 voi ensin todistaa polaarirenderin +
wräppäyksen **teknisesti** vaikka nykykoolla 1664×960 (proportiot rumat, R_inner<0 → aja ilman
ydinmöhkälettä / clampaa r). Tämä ei ole julkaisukoko, vaan pipeline-savutesti. Vaihda vakiot
4096×448:aan heti kun putki toimii. **Kokopäätös 4096×448 on v1:n oletus.**

### 2.3 Miksi SubViewport-komposiitti (renderöinnin arkkitehtuuri)

Nykytila (varmistettu koodista): terrain on `TextureRect` + `pixel_render.gdshader`, ja **zoom/pan
tehdään Controlin `scale`/`position`-transformilla** (`_update_camera`), EI shaderissa. Botit,
designaatiot, rakennus-esikatselut ja laskeutumiskapseli piirretään **lineaarisina Node2D-lapsina**
(`building_layer.scale = size/W`). Jos polaarimuunnos tehtäisiin pelkkään grid-tekstuuriin
(`pixel_render`-fragmentti), overlayt jäisivät lineaarisiksi eivätkä osuisi vääntyneeseen maastoon.

**Ratkaisu (P5):** renderöi terrain + kaikki overlayt ensin grid-avaruudessa **SubViewportiin** (1:1,
ei kameratransformia), ja **vääntele koko komposoitu tekstuuri kerran** polaarilämä-shaderilla
täysruutu-TextureRectillä (`PlanetView`). Näin:
- Kaikki nykyinen overlay-/piirtokoodi säilyy grid-avaruudessa **muuttumattomana** (designaatiorect
  vääntyy automaattisesti oikeaksi kaareksi).
- Polaarimatematiikka on **yhdessä paikassa** (yksi shader + `planet_camera.gd`).
- Zoom/rotaatio siirtyvät Control-transformista **shader-uniformeiksi** (kulma/säde/zoom).
- Hiiri: `_mouse_to_grid` delegoi `PlanetCamera`:lle (käänteispolaari). Kaikki nykyiset kutsujat
  toimivat ennallaan.

---

## 3. Moduulispeksit P1–P6

### P1 — Sim wrap (GPU + CPU-CA) + jaettu `planet_geom.gd`

**Tavoite:** x-suunta wräppää simulaatiossa. Sama wräppäys GPU-shaderissa JA headless-CPU-CA:ssa.
Luo jaettu geometria-apuluokka jota P3/P4/P5/P6 käyttävät.

**Uudet/muutettavat tiedostot:**
- **UUSI** `scripts/planet_geom.gd` (`class_name PlanetGeom`, `extends RefCounted`, staattiset funktiot).
- `shaders/simulation.glsl` — x-naapuruus modulo-indeksointiin.
- `scripts/pixel_world.gd` — VAIN `_step_cpu_ca()` (headless-CA) + `SIM_WIDTH`/`SIM_HEIGHT`-vakiot
  uuteen kokoon (§2.2). ÄLÄ koske kamera-/hiiri-/render-osioihin (ne ovat P5).

**`planet_geom.gd` (kanoninen wrap-kontrakti — luku 5):**
```gdscript
class_name PlanetGeom
extends RefCounted

# Wrappaa x-koordinaatin valille [0, w). Toimii myos negatiivisille.
static func wrap_x(x: int, w: int) -> int:
    return ((x % w) + w) % w

# Lyhin etumerkillinen x-erotus toruksessa: tulos valilla (-w/2, w/2].
# Kayta AINA kun lasketaan "suuntaa" tai "etaisyytta" x:ssa (heuristiikka, liike, separaatio).
static func wrap_dx(from_x: float, to_x: float, w: float) -> float:
    var d := to_x - from_x
    d = fposmod(d + w * 0.5, w) - w * 0.5
    return d

# Lyhin toroidaalinen euklidinen etaisyys (x wrap, y suora).
static func torus_dist(a: Vector2, b: Vector2, w: float) -> float:
    var dx := wrap_dx(a.x, b.x, w)
    var dy := b.y - a.y
    return sqrt(dx * dx + dy * dy)

# Polaarigeometria (P5/P6 kayttaa). r_surface = w / (2*PI).
static func r_surface(w: float) -> float:
    return w / TAU

# grid (x,y) -> napa (kulma rad, sade px). Kulmaan EI lisata kameraoffsettia (se on P5:ssa).
static func grid_to_polar(gx: float, gy: float, w: float) -> Vector2:
    return Vector2((gx / w) * TAU, r_surface(w) - gy)

# napa (kulma, sade) -> grid (x wräpätty [0,w), y clampaamaton — kutsuja clamppaa).
static func polar_to_grid(theta: float, radius: float, w: float) -> Vector2:
    var gx := fposmod(theta / TAU * w, w)
    var gy := r_surface(w) - radius
    return Vector2(gx, gy)
```

**`simulation.glsl`-muutokset (KRIITTINEN — Margolus säilyy):**
- Lisää apuri heti `get_mat`:n viereen:
  ```glsl
  uint wrap_x(int x) { int w = int(p.width); return uint(((x % w) + w) % w); }
  ```
- **Korvaa KAIKKI x-naapuritarkistukset** wräppäävällä indeksoinnilla. Nykyinen koodi tarkistaa aina
  `nx <= max_x` / `nx >= 0` / `nx <= max_x && y < max_y` ja hylkää reunan yli menevän. Uusi malli:
  x-naapuri on **aina olemassa** (wräpätty), vain y-rajat (`y < max_y`, `y > 0u`) säilyvät.
  Muutoskohdat (rivinumerot 781e80c):
  - Jauhe diagonaali (rivit 217–231): `uint nx = wrap_x(int(x) + dx);` poista `nx <= max_x`-ehto,
    säilytä `y < max_y`.
  - Putoava puu diagonaali (rivit 249–259): sama, `nx = wrap_x(int(x)+dx)`, poista x-raja.
  - Neste diag (rivit 292–302): sama.
  - Neste sivuleviäminen (rivit 306–333): molemmat silmukat — `int nx_s = int(x) + dir*int(i);`
    `uint nx = wrap_x(nx_s);` **poista `if (nx_s < 0 || nx_s > max_x) break;`** (leviäminen jatkuu
    sauman yli). HUOM: `spread`-etäisyys `p.width` (vesi) tarkoittaa nyt että vesi voi kiertää koko
    planeetan — se on OK (tasoittuu rengasmaisesti), mutta pidä `break` eri aineeseen törmätessä
    (`side_mat != mat`) ENNALLAAN jotta kiertosilmukka pysähtyy esteeseen.
  - Tuli: ylös (rivit 346–355), sytytä naapurit -tuplasilmukka (rivit 359–382): `nx = wrap_x(int(x)+dx)`,
    poista x-rajat, säilytä y-rajat.
  - Tuli→tuhka, höyry ylös (rivit 400–409) ja höyry sivulle (rivit 411–419): sama.
  - Gravity gun (`try_gravity_gun`, rivit 103–160): poistettu käytöstä pelistä, mutta jos kosket,
    wräppää x samalla logiikalla. **Ei pakollinen** (grav_gun_mode = 0 aina).
- **Margolus-faasi (rivit 170–173) EI muutu.** Faasimaski `(x & 1u) != ox` on jatkuva sauman yli VAIN
  jos `W` on parillinen (x=W-1 pariton → x=0 parillinen). §6 asettaa tämän invariantiksi. ÄLÄ koske
  faasilogiikkaan.
- `max_x = p.width - 1u` jää käyttöön vain siellä missä sitä yhä tarvitaan (jos jää); useimmat
  käyttökohdat poistuvat wräppäyksen myötä.

**`_step_cpu_ca()` (pixel_world.gd, headless-CA):** grep `_step_cpu_ca` ja peilaa GLSL:n wräppäys
CPU-puolelle. Sama sääntö: x-naapuri wräppää (`PlanetGeom.wrap_x(x + dx, W)`), y-rajat säilyvät. Tämä
on pakollinen — headless-skenaariot (`cpu_ca=true`) ajavat tätä, ja P3:n botti-sauma-testi nojaa
siihen että irtomateriaali valuu sauman yli myös headlessina.

**`SIM_WIDTH`/`SIM_HEIGHT`:** vaihda `pixel_world.gd`:n vakiot (`SIM_WIDTH := 4096`, `SIM_HEIGHT := 448`).
Tämä vaikuttaa koko peliin — P2/P3/P4 lukevat koon näistä (tai johtavat NW/NH-vakionsa, ks. P3).

**MIKÄ SÄILYY ENNALLAAN:** Margolus-offset-sykli, passimäärä (`GPU_PASSES_BASE`), push constant
-layout (≤128 B), workgroup 16×16, kaikki materiaalisäännöt (vain naapuri-indeksointi wräppää),
transfer/download-polut, `render_compute` (yhä pois päältä).

**Testisuunnitelma:**
- **Uusi** `tests/scenarios/wrap_sand.json` (`cpu_ca=true`, headless): täytä pystyseinä lähelle
  saumaa, pudota hiekkaa/soraa yli x=0/x=W-1 -rajan → `assert_count` että materiaali ilmestyy sauman
  TOISELLE puolelle (esim. `assert_material_at` x≈W-1 kun lähde oli x≈0). Todistaa GPU:n JA CPU-CA:n
  wräppäyksen (aja sekä headless- että ikkunallisena run_all.sh:n kautta).
- **Uusi** `tests/unit/test_planet_geom.gd` (extends SceneTree): `wrap_x` (negatiiviset, ylivuoto),
  `wrap_dx` (lyhin suunta sauman yli: `wrap_dx(10, W-10, W)` ≈ −20, ei +(W−20)), `torus_dist`,
  `grid_to_polar`/`polar_to_grid` edestakaisin (round-trip identiteetti ±epsilon).
- **Regressio:** olemassa olevat CA-skenaariot (`sand_falls`, `water_flows`, `stone_stacks`,
  `steam_rises` jne.) pysyvät vihreinä — wräppäys ei saa muuttaa käytöstä poissa saumasta.

**Riskit:** (1) W pariton rikkoo Margolus-faasin → §6-invariantti, valittu W=4096 on parillinen.
(2) Veden `spread = p.width` + wrap → vesi voi kiertää koko planeetan yhdessä passissa; varmista ettei
synny värähtelyä (edestakaista siirtoa) — `break` eri aineeseen pysäyttää sen. Jos ilmenee, rajaa
`spread` pienemmäksi (esim. `p.width / 4u`). (3) Vanhat skenaariot olettavat 1664×960-kokoa
(fill_rect-koordinaatit) → tarkista ettei mikään skenaario kirjoita ruudukon ulkopuolelle uudella
koolla; useimmat käyttävät pieniä `_ca_bounds`-alueita ja pysyvät sisällä.

---

### P2 — World gen: sylinterijatkuvuus + bedrock-ydin

**Tavoite:** maailma generoituu sylinterinä — sauma x=0/x=W-1 on huomaamaton. x-reunabedrock pois,
tilalle bedrock-ydinrengas syvyydessä. Alusta + base + starter-suoni pintaan.

**Muutettavat tiedostot:** `scripts/world_gen.gd` (yksin — ei muita).

**Muutokset:**

1. **Sylinterijatkuva pinta (`_generate_terrain`, rivit 226–285).** Nykyinen korkeuskohina
   `noise.get_noise_2d(float(cx), 0.0)` EI ole periodinen → sauma näkyisi korkeushyppäyksenä. Korvaa
   **ympyrältä näytteistetyllä kohinalla** jotta profiili on jatkuva x-akselin ympäri:
   ```gdscript
   # gx = grid-sarake, gw = sarakemaara. Naytteista kohina yksikkoympyralta:
   var ang := float(gx) / float(gw) * TAU
   var nx := cos(ang) * NOISE_CIRCLE_R    # NOISE_CIRCLE_R esim. 220.0 (saataa taajuutta)
   var ny := sin(ang) * NOISE_CIRCLE_R
   var n := noise.get_noise_2d(nx, ny)    # jatkuva: gx=0 ja gx=gw-1 vierekkain ymyralla
   ```
   Tämä takaa `top_cell[0]` ja `top_cell[gw-1]` naapuruuden. **Poista 45°-viisteen tasoituksen (rivit
   257–260) reunaehdot** niin että sarake 0:n ja gw-1:n välinen ero pakotetaan myös ≤1 solu:
   lisää wräppäävä tasoituspari, esim. `top_cell[0] = clampi(top_cell[0], top_cell[gw-1]-1,
   top_cell[gw-1]+1)` ja päinvastoin, mukaan tasoitussilmukkaan. Alusta pysyy pinnitettynä keskelle
   (`plat_gx0..plat_gx1`) — se on kaukana saumasta, ei ongelmaa.

2. **Poista x-reunabedrock (`_enforce_edges`, rivit 860–868).** Nykyinen kirjoittaa BEDROCKia
   `x < EDGE_THICKNESS` ja `x >= w - EDGE_THICKNESS` → **pystysuora bedrock-seinä sauman kohdalle**,
   mikä on täsmälleen väärin. **Poista x-ehto kokonaan.** Säilytä pohjabedrock (`y >= h -
   EDGE_THICKNESS`) — se on ytimen alin kerros. Kaikki muut `x < EDGE_THICKNESS || x >= w -
   EDGE_THICKNESS`-clampit generaattorissa (`_carve_circle` r393, `_place_single_deposit` r504,
   `_place_deposit_set` r651, `_walk_vein` r739, `_carve_vein_disc` r762, `_stamp_platform` r785) →
   ks. kohta 4 (wräppäys vs. clamp).

3. **Bedrock-ydinrengas + ytimen syvyys.** Lisää generointivaihe (esim. `_enforce_core`) joka
   kirjoittaa BEDROCKia syvimpiin riveihin: `for y in range(int(H * CORE_BEDROCK_FRAC), H): for x in W:
   grid[y*W+x] = MAT_BEDROCK` (ellei jo bedrock). `CORE_BEDROCK_FRAC := 0.85` (v1: bedrock alkaa 85 %
   syvyydestä = y≈380/448, jolloin mineraalivyöhyke 65–85 % on syvin louhittava). Tämä tekee ytimestä
   tuhoamattoman kuoren ydinmöhkäleen (P5) ympärille. **Säädä `CORE_BEDROCK_FRAC` niin että
   mineraalisuonet (rare_earth syvin, depth 0,75–1,0) mahtuvat sen yläpuolelle** — tai anna suonien
   ulottua bedrockiin asti (ne carvaavat vain STONEen, eivät ylikirjoita bedrockia, joten ei
   konfliktia).

4. **Suonet ja blobit wräppäävät saumassa (kosmeettinen jatkuvuus).** `_walk_vein` (rivit 714–746)
   katkeaa reunaan (`if cx < EDGE_THICKNESS+2 or cx >= w-EDGE_THICKNESS-2: break`). Vaihda: **wräppää
   x** kävelyssä (`cx = fposmod(cx, float(w))`) ja carvaa `_carve_vein_disc`in x-indeksointi
   wräppääväksi (`px = PlanetGeom.wrap_x(icx+dx, w)` — poista `px < EDGE_THICKNESS`-clamp x:stä,
   säilytä y-rajat ja bedrock-lopetus). Sama `_place_deposit_set`/`_place_single_deposit`/`_carve_circle`:
   x-skannaus wräppää (`px = PlanetGeom.wrap_x(cx+dx, w)`), y-rajat säilyvät. **Näin sauman yli osuva
   suoni/blob näkyy ehjänä molemmilla laidoilla.** (Jos tämä on liian iso urakka, hyväksyttävä
   v1-yksinkertaistus: pidä clampit x:ssä → suonet eivät ylitä saumaa, mutta pinta ON jatkuva (kohta 1)
   ja bedrock-seinä poistettu (kohta 2) → sauma on jo huomaamaton maastossa. Dokumentoi valinta.)

5. **Alusta + starter-suoni pysyvät keskellä (x ≈ W/2), kaukana saumasta.** `_stamp_platform` (r784),
   `_place_starter_iron_vein` (r810), `platform_x0 = w/2 - platform_w/2` — **ei muutosta tarpeen**,
   koska keskikohta on ~2048 px etäällä saumasta (x=0/W-1). Tämä on tarkoituksellista:
   **sauma jää planeetan "takapuolelle"**, pois pelaajan aloitusnäkymästä.

**MIKÄ SÄILYY ENNALLAAN:** generointipipeline (Phase 1–4), mineraalien syvyysvyöhykkeet,
tehdasalusta, `get_platform_rect`, pohjabedrock, `_make_noise`/`_noise_to_bytes`, luolat (pois
käytöstä), järvet (pois käytöstä). Vain x-reunakäsittely + pinnan jatkuvuus + ydinrengas muuttuvat.

**Testisuunnitelma:**
- **Uusi** `tests/scenarios/planet_seam.json` (headless): generoi maailma → `assert` että pinnan
  korkeusero sarakkeiden x=0 ja x=W-1 välillä on ≤ 1 solu (16 px), ts. sauma jatkuu. Toteuta uusi
  assert-komento (esim. `assert_surface_seam`, max korkeusero px) tai lue kaksi saraketta ja vertaa.
- **Uusi/laajenna** `tests/scenarios/worldgen_stress.json`: `assert` ettei bedrockia ole sarakkeissa
  x < EDGE_THICKNESS pinnan yläpuolella (x-seinä poistettu), ja että bedrock löytyy syvyydestä
  `CORE_BEDROCK_FRAC` alaspäin (ydinrengas olemassa).
- **Regressio:** `_place_starter_iron_vein` tuottaa yhä IRON_ORE:a alustan viereen (nykyinen
  starter-vein-assert pysyy vihreänä).

**Riskit:** (1) `NOISE_CIRCLE_R` väärä → pinta liian tasainen/rosoinen; säädä taajuus (nykyinen
`amp_cells=2.0` säilyy). (2) 45°-viistetasoituksen wräppäys voi luoda oskilloinnin sauman ympärillä
jos alusta-pinnaus taistelee sitä vastaan — alusta on kaukana, ei konfliktia. (3) ydinrengas ei saa
peittää alustaa/basea (ne ovat pinnalla y≈180, kaukana ytimestä).

---

### P3 — Bottijärjestelmien wrap

**Tavoite:** botit navigoivat ja laskevat etäisyydet sauman yli lyhintä reittiä. Designaatio,
polunhaku, liike, separaatio, työnjako ja materiaaliskannaus toroidaalisia. Grid-vakiot johdetaan
uudesta koosta.

**Muutettavat tiedostot:** `nav_grid.gd`, `designation_grid.gd`, `bot_manager.gd`, `bot.gd`,
`logistics.gd`. **Riippuvuus:** `PlanetGeom` (P1). Käyttää `PlanetGeom.wrap_x/wrap_dx/torus_dist`.

**0. Grid-vakiot uuteen kokoon (KAIKKI kolme tiedostoa).** Nyt kovakoodattu `NW=104, NH=60, GW=104,
GH=60, SIM_W=1664, SIM_H=960`. Johda koosta: `SIM_W = 4096`, `SIM_H = 448`, `NW = SIM_W/CELL = 256`,
`NH = SIM_H/CELL = 28`, `GW=256`, `GH=28`. **Tärkeää:** `nav_grid.gd:NODE_MASK = 0xFFFF` olettaa
`node < 65536`; nyt `NW*NH = 256*28 = 7168` < 65536 → OK, ei muutosta. Tarkista kaikki paikat joissa
104/60/1664/960 esiintyy literaalina.

**1. `nav_grid.gd` — A* + heuristiikka toroidaaliseksi (KRIITTISIN):**
- Naapurilaskenta (`find_path_px`, rivit 171–184): `var ncx := PlanetGeom.wrap_x(cx + _DX[dir], NW)`;
  **poista `ncx < 0 or ncx >= NW`-ehto** (jätä vain `ncy < 0 or ncy >= NH`). Diagonaalitarkistus
  (rivi 183) käyttää wräpättyä x:ää: `_open[cy*NW + ncx]` ja `_open[ncy*NW + cx]` — cx on jo laillinen,
  ncx wräpätty.
- Oktiili-heuristiikka (`_octile`, rivit 263–267): **wräppää x-komponentti** — muuten heuristiikka
  yliarvioi sauman ohittavan reitin eikä A* löydä lyhintä:
  ```gdscript
  var dx := int(absf(PlanetGeom.wrap_dx(float(ax), float(bx), float(NW))))
  var dy := absi(ay - by)
  ```
- Reitin suoristus (`_simplify`, rivit 217–229): suuntavektori `path[i]-path[i-1]` menee pieleen kun
  askel ylittää sauman (cx 255→0 näyttää −255-hyppäykseltä). **Wräppää x-erotus** kollineaarisuus-
  vertailussa (`PlanetGeom.wrap_dx`), TAI yksinkertaisin turvatoimi: älä suorista askelta jonka
  `abs(dx) > NW/2` (sauman ylittävä segmentti jätetään suoristamatta). Dokumentoi valinta.
- `mark_dirty_px_rect` (rivit 72–76), `is_open` (rivi 117), `_snap_to_open` (rivit 236, 251): x-clampit
  → wräppäys. `is_open(cx,cy)`: `cx = PlanetGeom.wrap_x(cx, NW)` ennen rajatarkistusta (poista x-raja,
  säilytä y). `mark_dirty_px_rect`: jos rect ylittää sauman, jaa kahteen segmenttiin TAI iteroi
  wräppäävästi.

**2. `designation_grid.gd` — sauman yli maalaus:**
- `get_cell`/`set_cell` (rivit 36, 44): `dx = PlanetGeom.wrap_x(dx, GW)`, poista x-raja (säilytä y).
- `paint_px_rect` (rivit 70–77): jos veto ylittää sauman (px0 > px1 kääriytyneenä TAI leveys lähellä
  W), iteroi wräppäävästi modulo-x:llä. Käytännössä: laske sarakkeet `cx = wrap_x(px/CELL, GW)` ja
  maalaa segmentteinä. **Salli sauman yli vedetyt kaivuulaatikot.**

**3. `bot_manager.gd` — liike, separaatio, etäisyydet, skannaus (LAAJIN):**
- **Position-wräppäys (KRIITTISIN este):** `_apply_separation` rivi 563 `clampf(b.pos.x, 0, SIM_W-1)`
  → `b.pos.x = fposmod(b.pos.x, float(SIM_W))`. y-clamp säilyy. Tämä on ainoa asia joka nyt estää
  botin liikkeen sauman yli.
- `_follow_path` (rivit 1129–1145): waypoint-vektori `to = wp - b.pos` → x wräpätään:
  `to.x = PlanetGeom.wrap_dx(b.pos.x, wp.x, float(SIM_W))`. Liikkeen jälkeen `b.pos.x =
  fposmod(b.pos.x, SIM_W)`. Näin botti seuraa sauman ylittävää polkua lyhintä reittiä.
- `_st_idle` leijunta (rivi 889), separation-työntö (rivi 558), crowd-naapurin `distance_to` (rivi
  528), miner reach (rivi 906): käytä `PlanetGeom.wrap_dx`/`torus_dist` x-suunnassa.
- **Crowd-index** (`_build_crowd_index` r496, `_crowd_neighbors` r511–521): solu `cx = wrap_x(
  int(b.pos.x)/NCELL... )`; 3×3-naapurusto wräppää (`cx = PlanetGeom.wrap_x(bcx+ox, NW)`, poista
  x-raja).
- **"Lähin X" -etäisyydet** (kaikki neljä): `_assign_miner` Manhattan (r696), `_assign_hauler_dig`
  Manhattan (r750), `_assign_hauler_pickup` `distance_to` (r808), `_seek_charge` `distance_to` (r1557)
  → wräppää x-komponentti (`wrap_dx`/`torus_dist`). Muuten reunabotti valitsee kaukaisen kohteen
  lähemmän sijaan.
- **Naapurustotarkistukset** `_mark_miner_penalty` (r619), `_has_open_neighbor` (r670), `_reeval_cell`
  (r1243): x-naapuri wräppää.
- **Pikseliskannaus/kirjoitus** (deposit/drop/pile/vacuum, rivit 1049–1510): `_find_pile`,
  `_dig_site_has_material`, `_vacuum`, `_find_pile_in_rect`, `_deposit_cargo_to_zone`,
  `_drop_cargo_above_base`, `_cell_solids`, `_work_mine`: x-indeksointi wräppää
  (`x = PlanetGeom.wrap_x(x0+xx, SIM_W)`, poista `x<0||x>=SIM_W`-hylkäys, säilytä y). **Massakeskipiste**
  `_find_pile_in_rect` (r1329 `sx += x`): jos kasa hajoaa sauman yli, laske keskipiste wräppäävästi
  (ankkuroi ikkunan alkuun ja summaa `wrap_dx`-offsetit) — tai v1-yksinkertaistus: pidä pile-skannaus
  ei-wräppäävänä (kasat harvoin sauman päällä koska sauma on takapuolella) ja dokumentoi. Botti-LIIKE
  ja A* ovat pakollisia; pile-skannauksen sauma-tarkkuus on nice-to-have.

**4. `logistics.gd` — dump-valinta:** `choose_dump` (r221–224) `distance_squared_to` → toroidaalinen
etäisyys (`PlanetGeom.torus_dist`). `_rect_center` säilyy.

**5. `bot.gd`:** ei omaa x-logiikkaa; vain `pos`-kentät. Ei muutosta paitsi jos vakioita.

**MIKÄ SÄILYY ENNALLAAN:** botti-tilat 0–6 ja logiikka, ruuhkanhallinnan kerrokset, louhinta/imu/dumppi/
lataus-mekaniikka, roolijako, `mvp_write_pixel`, `building_pixels`, designaatio-työkalumoodit (P6 hoitaa
inputin), nav-solukoko 16 px.

**Testisuunnitelma:**
- **Uusi** `tests/scenarios/bot_seam_path.json` (headless, `cpu_ca=true`): base/botti lähellä x=0,
  designaatio lähellä x=W-1 (sauman toisella puolella) → `run_frames` → `assert_bots_moved` +
  `assert_desig_consumed_pct` että botti valitsi **sauman yli** lyhyimmän reitin (matka ~40 px eikä
  ~4000 px). Voi vaatia uuden assertin (esim. botti saavutti kohteen alle N framessa).
- **Päivitä** `tests/unit/test_nav_grid.gd`: A* löytää sauman yli menevän polun (lähtö x-solu 2,
  maali x-solu NW-2, odotettu polku kulkee sauman kautta, pituus ~4 solua eikä ~NW-4). Oktiili-
  heuristiikan wräppäysassertti.
- **Päivitä** `tests/unit/test_designation_grid.gd`, `test_bot_manager.gd`: uudet vakiot (NW=256 jne.)
  eivät riko olemassa olevia asserteja; sauman yli maalaus toimii.
- **Regressio:** `mvp_core_loop.json` pysyy vihreänä (alusta keskellä, ei sauman lähellä → sama käytös).

**Riskit:** (1) `wrap_dx`-unohdukset yhdessäkin etäisyys-/liikekohdassa → botti "teleporttaa" tai
jumittuu saumalla; käy KAIKKI luetellut kohdat läpi. (2) A*-heuristiikan ei-admissiivisuus (jos x ei
wräpätty) → epäoptimaalinen mutta toimiva reitti; korjaa heuristiikka. (3) Vakiomuutos NH 60→28 (matala
planeetta) → varmista ettei mikään olettanut NH≥jokin. (4) `mark_dirty_px_rect` sauman yli jakaminen —
jos liian työlästä, hyväksy että reunan dirty-merkintä ei wräppää (nav päivittyy hitaammin saumalla),
dokumentoi.

---

### P4 — Fysiikka + fog wrap

**Tavoite:** CCL yhdistää sauman yli menevät kappaleet; fog-valo ei katkea saumaan; puun tuki wräppää;
rigid body -fysiikka ei kimpoa saumasta (v1-rajaus jos täysi tuki liian iso).

**Muutettavat tiedostot:** `ccl.gd`, `physics_world.gd`, `wood_support.gd`, `light_field.gd`.
**Riippuvuus:** `PlanetGeom` (P1).

**1. `light_field.gd` (fog of war) — HALVIN, TÄRKEIN VISUAALISESTI:**
- `DS := 8` (downscale). `_blur_3x3` vaakapassi (rivit 200–207): reunasarakkeet x=0 ja x=lw-1
  clamppaavat nyt reunaan → **valo katkeaa saumaan** (näkyvä raita). Vaihda toroidaaliseksi:
  ```gdscript
  # x=0: naapuri vasemmalle = lw-1
  _blur_f[row_base] = (_light_f[row_base + lw - 1] + _light_f[row_base] + _light_f[row_base + 1]) * _ONE_THIRD
  # x=lw-1: naapuri oikealle = 0
  _blur_f[last] = (_light_f[last - 1] + _light_f[last] + _light_f[row_base]) * _ONE_THIRD
  ```
  (Sisäsilmukka `range(1, lw-1)` säilyy.) Pystypassi (y) EI muutu (ydin-akseli).
- `_apply_emitters` (rivit 155–183): etäisyys `dist = sqrt(dx*dx+dy*dy)` → wräppää x
  (`dx = PlanetGeom.wrap_dx(ecx, cx, float(lw))` valosolu-avaruudessa), ja bounding box (rivit 169–170)
  kääritään reunan yli (iteroi wräppäävästi `cx = wrap_x(x, lw)`). Reunaemitteri valaisee sauman yli.
- Taivasvalo (`_apply_sky_light`) ja explored-muisti EIVÄT muutu (y-suuntaisia).
- **Huom:** `lw = ceil(sim_w/DS)`. Jos `sim_w` (4096) on jaollinen DS:llä (4096/8=512, tasan) →
  toroidaalinen blur on symmetrinen. **4096 on 8-jaollinen** → ei epäsymmetriaa. (Toinen syy valita
  16-jaollinen koko.)

**2. `wood_support.gd` — BFS-tuki (PIENI):** naapurihaku molemmissa vaiheissa (tukipisteet rivit
34–46, BFS-levitys rivit 65–68): `x > 0`/`x < width-1` → wräppäävä naapuri (`PlanetGeom.wrap_x`).
`y == height-1` (ydin = ankkuri) säilyy. Sauman yli tuettu puu ei enää putoa väärin.

**3. `ccl.gd` — connected components toroidaaliseksi:**
- `find_components_fast` (BFS, rivit 74–83) ja `find_components` (Union-Find, rivit 108–111):
  x-naapuri wräppää (vasen `wrap_x(cx-1,W)`, oikea `wrap_x(cx+1,W)`), poista x-rajaehto, säilytä y.
  Sauman yli menevä kivi = yksi kappale.
- `check_connectivity` (rivit 134–218): käyttää **paikallista AABB:tä** `min_x..max_x`. Sauman yli
  menevä kappale saisi `min_x=0, max_x=W-1` → `flat_w=W` (koko maailma) + kaksi puolikasta AABB:n
  vastakkaisilla reunoilla. **v1-ratkaisu:** tämä funktio ajetaan vain splittauksen yhteydessä
  (räjähdys-debug); jos rigid bodyt eivät ylitä saumaa (kohta 4, v1-rajaus), `check_connectivity`
  toimii ennallaan. **Dokumentoi:** täysi toroidaalinen CCL (AABB-origon valinta kappaleen "aukosta")
  on myöhempi työ; v1:ssä `find_components_fast`/`find_components` wräppäävät (skannaus toimii), mutta
  splittauksen AABB-malli olettaa ettei kappale ylitä saumaa.

**4. `physics_world.gd` — rigid body (LAAJIN; v1-RAJAUS suositeltu):**
Rigid bodyt tulevat käytännössä VAIN räjähdyksistä (debug) ja maalatusta kivestä. Bot mining -pelissä
ne eivät ole ydinsilmukkaa. Täysi toroidaalinen rigid body (rasterointi modulo-W, törmäysreunan
poisto, toroidaaliset etäisyydet, tipping/split-reunaehdot) on **iso** urakka.
- **v1-suositus (RAJAUS):** koska sauma on planeetan takapuolella (alusta keskellä), rigid bodyt eivät
  synny sauman lähellä normaalipelissä. **Poista x-reunan "kova seinä" -törmäys** (`_check_env_collision`
  r368, `_find_env_collision` r385–390) niin ettei näkymätön seinä ilmesty saumaan, JA wräppää
  rasteroinnin/erase/write x-indeksointi (`_get_filled_world_pixels` r270–274, `_erase_body` r316,
  `_write_body` r329) modulo-W:llä jotta kappale ei katoa jos se ajautuu saumaan. **Jätä** tipping/split/
  attraction toroidaali-tarkennukset tekemättä (v1-rajaus) — dokumentoi että sauman päällä lepäävä iso
  rigid body voi käyttäytyä epätarkasti. `_split_if_needed` reunaehto (r799 `p.x <= 0 or p.x >= w-1`):
  poista x-osa (x-reuna ei ole enää maailman reuna → pala ei jäädy staattiseksi x:n takia); säilytä
  y-alareuna (ydin) ankkurina.
- **Täysi toteutus (jos aikaa):** toroidaaliset etäisyydet impulssi/attraction/throw-funktioihin
  (`PlanetGeom.torus_dist`), `body.position.x = fposmod(..., W)` joka framen lopussa. Ei pakollinen v1.

**MIKÄ SÄILYY ENNALLAAN:** CA-sim (P1), fysiikan integrointi/uni/lepo, puun tuki-BFS-rakenne (vain
naapurit wräppää), fog:n taivasvalo/explored/DS, valokentän blur-rakenne (vain reunat toroidaaliksi).

**Testisuunnitelma:**
- **Uusi** `tests/unit/test_ccl_wrap.gd`: rakenna kivikappale joka koskettaa x=0 ja x=W-1 →
  `find_components_fast` palauttaa **yhden** komponentin (ei kahta).
- **Uusi** `tests/unit/test_wood_support.gd` (tai laajenna): sauman yli tuettu puu ei muutu
  WOOD_FALLINGiksi.
- **light_field:** verifiointi visuaalinen (integraattori) — headless ei renderöi. `light_field_test.gd`
  jos olemassa: lisää assertti että sarakkeen 0 ja lw-1 blur-arvot ovat lähellä toisiaan jatkuvassa
  valokentässä (ei katkosta).
- **Regressio:** `explosion_fragments.json`, `stone_*.json` pysyvät vihreinä (rigid bodyt eivät
  regressoi keskellä karttaa).

**Riskit:** (1) physics-täystoteutus paisuu → pitäydy v1-rajauksessa (poista seinä + wräppää
raster/erase/write, muu ennallaan). (2) CCL `check_connectivity` AABB sauman yli → v1-rajaus (rigid
bodyt eivät ylitä saumaa). (3) fog-blur toroidaalinen mutta emitteri euklidinen unohtuu → sauma
näkyisi emitterivalossa; muista molemmat.

---

### P5 — Polaarirenderi + kamera + koordinaattimuunnokset (AALTO 2, iso)

**Tavoite:** maailma näkyy pallona. Terrain + kaikki overlayt vääntyvät polaariin yhtenäisesti.
Kamera = kulma (rotaatio) + säde (syvyys) + zoom shader-uniformeina. Hiiri↔grid molempiin suuntiin.
Ydinmöhkäle peittää keskipisteen.

**Uudet/muutettavat tiedostot:**
- **UUSI** `scripts/planet_camera.gd` (`class_name PlanetCamera`, `extends RefCounted` tai Node) —
  kameran tila + muunnokset.
- **UUSI** paascenen solmut: `SubViewport` (grid-avaruus) + `PlanetView` (täysruutu-TextureRect,
  ViewportTexture + polaari-shader). Toteuta koodista (`_ready`) tai scenessä — dokumentoi kumpi.
- `shaders/pixel_render.gdshader` — muuta polaarilämä-shaderiksi (näytteistää ViewportTexturea
  käänteispolaarilla) TAI luo **UUSI** `shaders/planet_warp.gdshader` ja jätä `pixel_render` grid-
  avaruuden materiaalivärjäykseen SubViewportin sisään. **Suositus:** uusi `planet_warp.gdshader`
  (selkeämpi), `pixel_render` säilyy SubViewportin terrain-shaderina.
- `scripts/pixel_world.gd` — scenepuun uudelleenjärjestely (`_ready`/`_setup_*`), `_mouse_to_grid`
  (rivi 1196) + `grid_to_screen` (rivi 1257) delegoi `PlanetCamera`:lle, `_update_camera` (rivi 1390)
  korvataan planeettakameralla, `set_impact`/`flash`-UV:t (polaariin). ÄLÄ koske sim-osioihin (P1).

**Renderöintiputki (SubViewport-komposiitti, §2.3):**
1. **SubViewport `WorldViewport`** kokoa `W × H` (4096×448), `render_target_update_mode = ALWAYS`,
   `transparent_bg = false`. Siirrä `pixel_world` (TextureRect, terrain + `building_layer`-overlayt)
   tämän lapseksi. TextureRectin koko = `W×H`, **ei kameratransformia** (scale=1, position=0) —
   `_update_camera`in Control-scale/position-logiikka POISTUU (korvautuu shaderilla). `pixel_render`
   värjää materiaalit kuten ennen (fog, efektit) grid-avaruudessa.
2. **`PlanetView`** (täysruutu-TextureRect, koko = ikkuna 1664×960) näyttää `WorldViewport`:n
   `ViewportTexture`:n ja ajaa `planet_warp.gdshader`:n uniformeilla:
   ```
   uniform sampler2D world_tex;      // ViewportTexture (grid-avaruus, W x H)
   uniform float view_angle;         // kameran kulmaoffset (rad) — A/D pyorittaa
   uniform float view_radius_center; // sateittainen keskitys (px) — W/S siirtaa
   uniform float view_zoom;          // 1 = koko pallo ruudulla, isompi = lahikuva
   uniform float r_surface;          // W/(2PI)
   uniform float r_inner;            // R_surface - H (ydinmohkaleen sade)
   uniform vec2  screen_size;        // 1664x960
   uniform vec3  core_color;         // ydinmohkaleen vari
   uniform vec3  sky_color;          // avaruus (r > r_surface)
   ```
   Fragmentti: laske `d = (FRAGCOORD - center)/view_zoom` (skaalattu), `r = length(d)`,
   `theta = atan(d.y,d.x) + view_angle`. Jos `r > r_surface` → `sky_color` (+ tähdet valinn.). Jos
   `r < r_inner` → `core_color` (ydinmöhkäle). Muuten `u = fract(theta/TAU)`, `v = (r_surface - r)/H`,
   `COLOR = texture(world_tex, vec2(u, v))`. `view_radius_center`+`view_zoom` säätävät mitä sädeväliä
   näytetään (pinnan lähikuva ↔ koko pallo).
3. **Ikkuna pysyy 1664×960.** Vain `PlanetView` on ikkunan kokoinen; `WorldViewport` on grid-kokoinen
   render target.

**`planet_camera.gd` (kameran tila + muunnokset):**
```gdscript
class_name PlanetCamera
extends RefCounted

var angle: float = 0.0            # kameran kulmaoffset (rad); A/D muuttaa
var radius_center: float = 0.0   # sateittainen keskitys (px); W/S muuttaa
var zoom: float = 1.0            # 1 = koko pallo, isompi = lahi
var world_w: float               # SIM_WIDTH
var world_h: float               # SIM_HEIGHT
var screen_size: Vector2         # 1664x960

# Ruutupikseli -> grid (kaanteispolaari). Palauttaa Vector2i(-1,-1) jos taivas/ydin.
func screen_to_grid(screen_px: Vector2) -> Vector2i
# grid -> ruutupikseli (eteenpain). Popover-sijoittelu (ui.gd grid_to_screen).
func grid_to_screen(grid_pos: Vector2) -> Vector2
# Paivita shader-uniformit (PlanetView-material)
func apply_to_shader(mat: ShaderMaterial) -> void
```
Käytä `PlanetGeom`:n `r_surface`/`polar_to_grid`/`grid_to_polar`-apureita; `PlanetCamera` lisää
`angle`/`zoom`/`radius_center`-muunnoksen niiden päälle.

**Hiiri (`pixel_world._mouse_to_grid`):** korvaa nykyinen lineaarinen mappaus:
`return planet_camera.screen_to_grid(get_viewport().get_mouse_position())`. Kaikki nykyiset kutsujat
(maalaus, designaatio, louhinta, hover, zone-veto) toimivat ennallaan.

**`grid_to_screen` (popoverit):** delegoi `planet_camera.grid_to_screen`. UI-popoverit (base/kone/
vyöhyke) sijoittuvat oikeaan kohtaan pallolla.

**Ydinmöhkäle:** piirretään `planet_warp.gdshader`:ssa (`r < r_inner` → `core_color`), EI grid-
sisältönä. Pelimekaaninen törmäys: bedrock-ydinrengas (P2) estää kaivamisen jo ennen ydintä, joten
möhkäle on visuaalinen keskustan peite v1:ssä. (Myöhempi mysteeri-mekaniikka: erillinen hook.)

**Impact/flash-UV:t:** `set_impact` (rivi 1439), räjähdysflash (`_upload_render` rivi 2838) laskevat
UV:n `world_pos / (W,H)` — nämä ovat grid-UV:ita jotka menevät `pixel_render`:iin SubViewportin sisään
→ **toimivat ennallaan** (efektit ovat grid-avaruudessa, vääntyvät komposiitissa). Ei muutosta paitsi
jos jokin efekti oli ruutu-avaruudessa (screenshake `position`/`scale` — nyt PlanetView:iin tai
poista, ks. alla).

**Screenshake:** nykyinen heiluttaa `pixel_world.position`/`scale` (Control). Uudessa putkessa siirrä
shake `PlanetView`:iin (position-offset) TAI `view_angle`/`view_radius_center`-pieneen nykäykseen.
Yksinkertaisin: `PlanetView.position = shake_offset`. Säilytä `add_trauma`-API.

**MIKÄ SÄILYY ENNALLAAN:** `pixel_render.gdshader`in materiaalivärjäys/fog/efektit (ajetaan
SubViewportin sisällä grid-avaruudessa), `building_layer`-overlayt ja niiden piirto (grid-avaruus,
vääntyvät automaattisesti), `light_field`-tekstuuri (grid-UV), kaikki `_mouse_to_grid`-kutsujat, sim
(P1). Bottien/designaatioiden piirtokoodia EI muuteta.

**Testisuunnitelma:**
- **Ei headless-testejä** (renderöinti). `PlanetCamera.screen_to_grid`/`grid_to_screen` round-trip
  yksikkötestattavissa: **Uusi** `tests/unit/test_planet_camera.gd`: aseta angle/zoom/radius_center,
  `grid_to_screen(screen_to_grid(p)) ≈ p` (±epsilon) näkyvällä sädealueella.
- **Ikkunallinen verifiointi (integraattori):** pallo näkyy, sauma huomaton, A/D pyörittää, W/S
  syvyys, zoom pinta↔pallo, hiirimaalaus osuu oikeaan grid-kohtaan (maalaa → tarkista sim), popover
  osuu base-kohtaan.

**Riskit:** (1) SubViewport-input: `pixel_world._handle_input` käyttää `get_local_mouse_position` —
SubViewportin sisällä tämä ei vastaa ruutua. **Ratkaisu:** `_mouse_to_grid` EI enää käytä
`get_local_mouse_position`ia vaan `planet_camera.screen_to_grid(get_viewport().get_mouse_position())`
(globaali ruutupos). UI-paneelien hit-test (`_handle_input` rivit 1011–1016) käyttää globaalia
`get_viewport().get_mouse_position()` — säilyy. (2) `ViewportTexture` v-akselin flip / sRGB — testaa
näytteistyssuunta. (3) suuri `WorldViewport` (4096×448) render target -muisti ~7 MB — OK. (4) zoom-
matematiikan center/scale-järjestys helppo mokata → yksikkötesti round-trip. (5) `_update_camera`in
`cam_grid_pos`/`cam_vel` WASD-logiikka POISTUU/korvautuu — varmista ettei P6:n W/S-radiaali jää
riippumaan poistetusta koodista (sovi rajapinta P6:n kanssa: `PlanetCamera.radius_center`/`angle`/
`zoom` ovat P6:n ohjaamat kentät).

---

### P6 — Ohjaus + UI-sopeutus + laskeutumisintro (AALTO 3)

**Tavoite:** A/D pyörittää planeettaa, W/S liikkuu säteittäin, zoom pinnan lähikuvasta koko palloon.
UI-popoverit ja HUD kohdallaan polaarinäkymässä. Laskeutumisintro sopeutettu planeetalle.

**Muutettavat tiedostot:** `scripts/pixel_world.gd` (input + intro), `scripts/ui.gd`.
**Riippuvuus:** `PlanetCamera` (P5).

**1. Ohjaus (`pixel_world` input, korvaa `_update_camera`in WASD-logiikan):**
- **A/D → `planet_camera.angle`.** "Pyörittää planeettaa sopivalla nopeudella — kamera pysyy, planeetta
  kääntyy." Käytännössä: `planet_camera.angle += ROTATE_SPEED * delta * dir` (wräppää `TAU`).
  `ROTATE_SPEED` säädetään niin että pinnan pyörimisnopeus ruudulla tuntuu luontevalta (esim. ~0,6
  rad/s zoomilla 1; skaalaa zoomilla jotta lähikuvassa hitaampi).
- **W/S → `planet_camera.radius_center`.** Säteittäinen liike syvemmälle/pinnalle (Terraria-tyyli).
  Clamppaa `[r_inner, r_surface]`. Skaalaa nopeus zoomilla.
- **Zoom → `planet_camera.zoom`.** Portaaton (kuten nykyinen `target_zoom`-lerp). Alue:
  `ZOOM_MIN` = koko pallo ruudulla (planeetan halkaisija `2*r_surface*view` ≤ ikkunan korkeus) …
  `ZOOM_MAX` = pinnan lähikuva. Reuse nykyinen zoom-lerp-idea (`zoom_level`→`target_zoom`), mutta arvo
  menee `planet_camera.zoom`iin, ei Control-scaleen. **Zoomatessa koko palloon** `radius_center`
  keskitetään planeetan keskipisteeseen; **pinnan lähikuvassa** `radius_center` seuraa W/S-syvyyttä.
- Nykyiset näppäinvakiot (KEY_A/D/W/S) säilyvät; vain vaikutus muuttuu.

**2. UI-sopeutus (`ui.gd`):**
- **Popover-sijoittelu:** kaikki `world.grid_to_screen(...)`-kutsut (base/kone/vyöhyke-popoverit,
  bottien tilapalkit) menevät nyt P5:n `PlanetCamera.grid_to_screen`-muunnoksen läpi → ei
  koodimuutosta ui.gd:hen JOS ui käyttää `world.grid_to_screen`ia (varmista; jos ui laskee itse
  lineaarisesti, vaihda `world.grid_to_screen`iin).
- **Zoom/rotaatio-kontrollit:** jos UI:ssa on zoom-napit (ks. aikanopeus-widget oikea yläkulma),
  kytke ne `planet_camera.zoom`iin. Lisää valinnainen "koko pallo" -pikanäppäin/nappi (zoom_min).
- **Aikanopeus-widget, actionbar, popover-runko, amber-teema:** säilyvät (ruutu-avaruuden UI
  CanvasLayerissa, ei polaaria).
- **Orientaatioapu (valinnainen, nice-to-have):** pieni "syvyysmittari" tai kompassi joka näyttää
  kameran kulman/syvyyden. EI pakollinen v1.

**3. Laskeutumisintro (`pixel_world` `_update_landing_intro` rivit 1784+, `_intro_*`-kentät):**
Nykyinen kapseli on overlay joka putoaa sim-px:ssä +y-suuntaan alustan ylle. Planeetalla "taivas" on
pinnan yläpuolella (`r > r_surface`, avaruus). Vaihtoehdot:
- **Suositus (yksinkertaisin):** intro on windowed-only kosmeettinen kerros. Aja intro **zoom
  pinnan lähikuvassa alustan kohdalla** (kamera keskitetty alustaan) ja pudota kapseli-overlay
  **grid-avaruudessa** alustan ylle pienestä negatiivisesta "korkeudesta" (piirrä kapseli
  `bot_overlay`-tyyliin gridissä, y alustan yläpuolella; koska overlay on SubViewportissa, se vääntyy
  polaariin ja näyttää tulevan avaruudesta pintaa kohti). `INTRO_FALL_HEIGHT` (240 px) → kapseli
  alkaa `surface_y - 240` (grid-y negatiivinen/pieni) ja putoaa alustaan. Toimii jos SubViewport
  renderöi myös `y < 0` -overlayn (piirto ei clamppaa). Varmista overlay-piirto sallii negatiivisen y:n.
- **Vaihtoehto:** piirrä kapseli PlanetView:iin ruutu-avaruudessa putoamassa kohti alustan
  polaari-ruutupositiota (`planet_camera.grid_to_screen(platform_center)`). Enemmän työtä.
- **Skip/ajoitus:** säilyy (klik skippaa, `_finish_landing_intro`). Gate `if not gpu_ready or
  _scenario_active: skip` säilyy (headless ohittaa).

**MIKÄ SÄILYY ENNALLAAN:** aikanopeus/pause, actionbar, popover-runko, amber-teema, designaatio-
työkalumoodit, kaikki gameplay-input (maalaus/designaatio/louhinta `_mouse_to_grid`in kautta),
demo-kaari, `_init_bot_sim`-bottispawn, Title/Pause/DemoComplete-overlayt.

**Testisuunnitelma:**
- **Ikkunallinen verifiointi (integraattori):** A/D pyörittää sulavasti wräpäten, W/S syvyys clamppaa,
  zoom pinta↔pallo, popover osuu baseen zoom-tasosta riippumatta, intro näyttää kapselin tulevan
  avaruudesta alustaan, klik skippaa.
- **Headless-regressio:** kaikki botti-/CA-skenaariot pysyvät vihreinä (intro ohittuu, ohjaus ei
  vaikuta headlessiin).

**Riskit:** (1) rotaationopeus zoom-riippumaton tuntuu väärältä → skaalaa `ROTATE_SPEED` zoomilla.
(2) W/S-clamp `radius_center` väärin → pääsee ytimen sisään/avaruuteen; clamppaa `[r_inner, r_surface]`
huomioiden zoom-näkyvä sädeväli. (3) intro-overlay negatiivinen y ei renderöidy → käytä vaihtoehtoa
(ruutu-avaruus). (4) popover-sijoittelu zoomissa ulos → popover voi mennä ruudun reunan yli; clamppaa
ruudulle (todennäköisesti jo tehty).

---

## 4. Yhteensopivuus ja testit

### 4.1 ScenarioRunner (headless — säilyy grid-avaruudessa)

Simulaatio ja bottisim toimivat **grid-avaruudessa** — polaari on vain windowed-render. Kaikki
olemassa olevat headless-skenaariot (`tests/scenarios/*.json`) ja yksikkötestit (`tests/unit/*.gd`)
**pysyvät vihreinä** kun:
- P1: sim-koko muuttuu (4096×448) → skenaariot jotka fill_rectaavat pieniä alueita pysyvät sisällä;
  tarkista ettei mikään kirjoita x≥1664 olettaen vanhaa leveyttä (useimmat käyttävät `_ca_bounds`-
  rajattua aluetta lähellä origoa). Jos jokin skenaario olettaa keskikohdan x=832, päivitä x=2048.
- P3: nav/desig-vakiot muuttuvat (NW=256, NH=28) → `test_nav_grid`/`test_designation_grid`-
  odotusarvot päivitetään.
- `mvp_core_loop.json`, `mvp_gpu_probe.json` ym.: alusta keskellä (x≈2048), designaatio sen viereen →
  sama käytös kuin ennen (ei sauman lähellä).

**Uudet skenaariokomennot (jos tarpeen):** `assert_surface_seam` (P2, pinnan jatkuvuus saumassa),
`assert_material_at x y mat` (P1, wräppäystodiste) — toteuta `_scenario_execute_step`-match-haaraan.

**Ikkunalliset skenaariot (`run_all.sh` ajaa ilman `--headless`):** `conveyor_*.json`, `belt_ore.json`
vaativat Vulkanin. Polaarirender (P5) ei saa rikkoa näitä — ne testaavat grid-avaruuden CA:ta/hihnoja,
eivät renderöintiä. Varmista P5:n scenepuu-muutos ei kaada näitä (SubViewport-render toimii myös
ilman että kukaan katsoo).

### 4.2 Headless-ajo

`bash tests/run_all.sh` (Godot: `C:/Users/mauri/Desktop/Godot/Godot_v4.6.1-stable_win64_console.exe`).
Yksikkötestit `--headless --script`, skenaariot `--scenario=`. `cpu_ca=true`-skenaariot ajavat
CPU-CA:ta (P1 wräppää sen). Aja run_all jokaisen moduulin lopuksi ja ennen merge-junaa.

---

## 5. Moduulien väliset sopimukset (älä riko)

### P1 tarjoaa — P3/P4/P5/P6 nojaavat

**`scripts/planet_geom.gd` (staattiset apufunktiot, ASCII-kommentit):**
```gdscript
class_name PlanetGeom
static func wrap_x(x: int, w: int) -> int
static func wrap_dx(from_x: float, to_x: float, w: float) -> float   # lyhin etumerkillinen erotus
static func torus_dist(a: Vector2, b: Vector2, w: float) -> float
static func r_surface(w: float) -> float                              # w / TAU
static func grid_to_polar(gx: float, gy: float, w: float) -> Vector2  # -> (theta, radius)
static func polar_to_grid(theta: float, radius: float, w: float) -> Vector2  # -> (x wräpätty, y)
```
**Wrap-konventio (kaikki moduulit):** x-koordinaatti on jaksollinen `[0, W)`. "Suunta" tai "etäisyys"
x:ssä lasketaan AINA `wrap_dx`/`torus_dist`-kautta (lyhin reitti sauman yli). y ei wräppää.

**Sim-koko:** `pixel_world.SIM_WIDTH = 4096`, `SIM_HEIGHT = 448` (kanoninen; P3 johtaa NW/NH tästä).
**W on parillinen** (Margolus-invariantti, §6).

### P2 tarjoaa — P5 renderöi seamless-maailman
- Pinta jatkuva sauman yli, x-reunabedrock poistettu, bedrock-ydinrengas syvyydestä
  `CORE_BEDROCK_FRAC` (~0,85). Ydinmöhkäle-alue (`r < R_inner`) on ruudukon ULKOPUOLELLA — P5 piirtää
  sen; P2 ei kirjoita sinne mitään (grid loppuu y=H-1 = juuri möhkäleen yläpuolella).

### P3/P4 tarjoavat — toroidaalinen simulaatio-/agenttikäytös
- Botit, nav, designaatio, CCL, fog, wood_support wräppäävät x:ssä `PlanetGeom`-apureilla. Grid-
  avaruus pysyy suorakulmaisena (headless-testit toimivat).

### P5 tarjoaa — P6 kuluttaa

**`scripts/planet_camera.gd`:**
```gdscript
class_name PlanetCamera
var angle: float           # P6 A/D kirjoittaa (rad, wräppää TAU)
var radius_center: float   # P6 W/S kirjoittaa (clamp [R_inner, R_surface])
var zoom: float            # P6 zoom kirjoittaa (ZOOM_MIN=koko pallo .. ZOOM_MAX=lahi)
func screen_to_grid(screen_px: Vector2) -> Vector2i
func grid_to_screen(grid_pos: Vector2) -> Vector2
func apply_to_shader(mat: ShaderMaterial) -> void
```
- `pixel_world._mouse_to_grid` delegoi `screen_to_grid`iin; `grid_to_screen` (popoverit) delegoi.
  P6 EI muuta näitä delegointeja, vain ohjaa `angle`/`radius_center`/`zoom`-kenttiä.
- `PlanetView`-materiaali + `planet_warp.gdshader`-uniformit ovat P5:n; P6 säätää niitä VAIN
  `PlanetCamera.apply_to_shader`in kautta.

### Rajapinta-invariantit
- **Grid-avaruus pysyy suorakulmaisena.** Kaikki gameplay/sim/testit toimivat grid-koordinaateissa;
  polaari on pelkkä windowed-render + hiiri-/popover-muunnos.
- **x-jaksollisuus:** ei koskaan `clampf(x, 0, W-1)` liikkeessä — aina `fposmod`/`wrap_x`.
- **Botti-tilat 0–6, materiaali-ID:t, Margolus 2×2, push constant ≤128 B, workgroup 16×16**
  koskematta.
- **W parillinen** (Margolus-faasi jatkuu sauman yli).
- **ASCII vs. ä/ö per tiedosto** (tyyliohje ylhäällä).

---

## 6. Rajoitteet (sitovat)

- **Margolus-faasin jatkuvuus vaatii parillisen W:n.** Faasimaski `(x & 1u) != ox` alternoi oikein
  sauman yli vain jos x=W-1 on pariton (→ W parillinen). Pariton W → kaksi samanpariteettista
  saraketta vierekkäin saumassa → race/duplikaatio. **v1 W=4096 (parillinen, 16-jaollinen).**
- **Push constant ≤ 128 B**, nykyinen `Params` (48 B käytössä) — P1 ei lisää kenttiä (wräppäys on
  indeksointilogiikkaa, ei uutta dataa). Polaariparametrit ovat `planet_warp.gdshader`-uniformeja
  (canvas_item, ei push constant -rajaa).
- **Workgroup 16×16** — P1 ei muuta dispatch-geometriaa (`ceili(W/16)`, `ceili(H/16)` — W/H
  16-jaollisia → tasan).
- **RenderingDevice elinkaari:** `rd` luodaan `_ready`:ssä, vapautetaan `NOTIFICATION_PREDELETE`:ssä.
  P5 lisää SubViewportin/PlanetView'n — nämä ovat Godot-scene-solmuja, EIVÄT local RD -resursseja;
  älä sekoita niitä `rd`-elinkaareen.
- **CPU↔GPU-synkka:** koko `grid_buffer` ladataan alas joka maalauksen jälkeen (4096×448×4 ≈ 7,3 MB).
  Pysyy nykyluokassa (~1,15×). Älä lisää per-frame-latauksia.
- **cpu_ca-headless-fallback:** headless ilman GPU:ta ajaa CPU-CA:ta (`_step_cpu_ca`). P1 wräppää sen
  MYÖS — muuten headless-sauma-testit epäonnistuvat.
- **Ikkuna pysyy 1664×960** (nearest-filter). Vain `WorldViewport` on grid-kokoinen render target.

---

## 7. Tulevaisuus (EI tässä speksissä)

- Ydinmöhkäleen mysteeri-mekaniikka (syvin kaivuu → tapahtuma/palkinto).
- Aito säteittäinen painovoima erikoismateriaaleille (nyt kaikki putoaa +y = kohti ydintä).
- Chunkattu sim isommalle planeetalle (28×+ solua).
- Useampi planeetta / kiertorata / avaruusnäkymä (zoom ulos planeetalta).
- Rigid body -täystoroidaali (v1: sauman yli epätarkka).
- Save/load (nyt vain `_init_bot_sim`/world_gen-polku).

---

## 8. Avoimet kysymykset (integraattorille / tuoteomistajalle)

1. **Lopullinen koko:** 4096×448 (turvallinen, matala planeetta) vai 4992×544 (isompi, syvempi,
   1,7×)? Speksin oletus on 4096×448; vaihto on yhden vakioparin muutos (P1) + P3:n johdetut vakiot.
2. **Rotaationopeuden tuntuma** (P6 `ROTATE_SPEED`): säädetään ikkunallisessa testissä; ei ratkaistavissa
   koodista.
3. **Rigid body -saumatuki:** v1-rajaus (poista seinä + wräppää raster; muu ennallaan) riittänee koska
   sauma on takapuolella. Vahvista ettei pelissä synny isoja rigid bodyja sauman lähelle.
4. **Ydinmöhkäleen rooli:** v1 = visuaalinen keskustan peite. Halutaanko heti kevyt "törmää ytimeen"
   -toast/tapahtuma, vai jätetäänkö kokonaan myöhempään?
5. **Intro-toteutus** (P6): grid-avaruuden overlay (yksinkertaisin) vai PlanetView-ruutuoverlay?
   Riippuu siitä renderöikö SubViewport `y<0`-overlayn — varmennettava P5:n jälkeen.
