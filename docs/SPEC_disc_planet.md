# SPEC: Kiekkoplaneetta + sektorigravitaatio (prototyyppi)

**Branch:** `feature/disc-planet` · **Worktree:** `C:\Users\mauri\Desktop\Git\GodotMining-disc`
**Status:** prototyyppi — EI korvaa nykyistä peliä. Erillinen scene, jonka voi ajaa rinnakkain.

## Miksi

Nykyinen wrap-arkkitehtuuri (4096×448, x-wrap + polaarirender) ylinäytteistää syvyyksiä
(~35 % sim-työstä redundanttia), vaatii koko maailman SubViewport-kompositoinnin joka
frame (mitattu perf-pullonkaula) ja hajoaa matemaattisesti keskipisteessä (musta möhkäle
= singulariteetti). Kiekko Cartesian-gridissä poistaa kaikki kolme: vähemmän soluja,
render skaalautuu ruudun (ei maailman) mukaan, keskusta on olemassa.

Tämän prototyypin tarkoitus: **nähdä sektorigravitaatio-CA toiminnassa** ennen kuin
päätetään täysporttauksesta (botit, nav, logistiikka jne. EIVÄT kuulu tähän).

## Geometria (scripts/disc_geom.gd — VALMIS, älä muuta rajapintaa)

- Grid `GRID_N × GRID_N` = 1408×1408 (16:n monikerta → 88 tileä/akseli; PARILLINEN — invariantti)
- `R_PLANET = 640` (kiekko gridin keskellä), `R_CORE = 40` (bedrock-ydin)
- Solukeskipiste-symmetria 2x-skaalatuilla deltoilla: `dxc = 2x-(N-1)`, `dyc = 2y-(N-1)`.
  Koska N on parillinen, dxc/dyc ovat AINA parittomia → eivät koskaan 0 → sign aina ±1,
  ei puolen pikselin biasia, ei erikoistapauksia keskilinjoilla.
- **Sektori ja "alas"**: jos `|dxc| > |dyc|` → vaakasektori, `down = (-sign(dxc), 0)`;
  muuten pystysektori, `down = (0, -sign(dyc))`. Tasapeli (45°-diagonaali) → pysty.
- `perp = (-down.y, down.x)` — sivusuunta (diagonaalit, nestelevitys).
- GLSL toistaa saman matikan (ei importteja):

```glsl
// Sektorikohtainen "alas" kohti keskipistetta. Pidettava identtisena disc_geom.gd:n kanssa.
ivec2 down_of(uint x, uint y) {
    int dxc = 2 * int(x) - (int(p.width) - 1);
    int dyc = 2 * int(y) - (int(p.height) - 1);
    if (abs(dxc) > abs(dyc)) return ivec2(dxc > 0 ? -1 : 1, 0);
    return ivec2(0, dyc > 0 ? -1 : 1);
}
```

- Ytimen bedrock (R_CORE) peittää sektorien kohtauspisteen → ei patologioita keskustassa.
- Kiekon ulkopuoli gridin sisällä = avaruus (EMPTY). Sinne maalattu materiaali putoaa
  planeettaa kohti — se on feature.

## Vaihe 1A: `shaders/simulation_disc.glsl` (fork simulation.glsl:stä)

Mekaaninen kanta-käännös. simulation.glsl EI muutu — uusi tiedosto.

- **Poista wrap_x kokonaan** — kiekko ei wrappaa. KAIKKI naapurihaut bounds-checkataan
  molemmilla akseleilla (`0..width-1`, `0..height-1`). Apurit: `bool in_bounds(ivec2)`,
  `uint idx_of(ivec2)`.
- Basis per solu: `ivec2 down = down_of(x, y); ivec2 perp = ivec2(-down.y, down.x);`
- Käännöstaulukko (vanha → uusi):
  - alas (`idx + p.width`) → `pos + down`
  - ylös (`idx - p.width`) → `pos - down` (öljy nousee vedessä, tuli/höyry nousee)
  - diagonaali alas → `pos + down + dir*perp`
  - sivulle → `pos ± perp` (nestelevitys, steam-sivuaskel)
  - tulen/höyryn nousun satunnainen sivujitter: `pos - down + j*perp`, j ∈ {-1,0,1}
  - tulen 3×3-sytytysnaapurusto: pysyy absoluuttisena 3×3:na (suunnaton) — vain bounds-check
- Nesteen sivuskannaus: perp-suunnassa, spread-cap `WATER = 64`, `OIL = 32` (EI koko
  kehää, ei wrapia; break vieraaseen materiaaliin kuten ennen).
- P2-aktiivisuustilet: naapuritilehaku **clamp molemmilla akseleilla** (poista x-wrap-modulo).
  Muu P2-logiikka (atomicMax-leimat, early-out, itseleimat) säilyy täsmälleen.
- 4-faasi-checkerboard (`pass_id % 4`) säilyy TÄSMÄLLEEN ennallaan — älä koske.
- Atomiikka (try_atomic_move/swap) säilyy ennallaan (indeksit vain lasketaan kannalla).
- Gravity gun -haara: säilytä (toimii jo absoluuttisilla suunnilla).
- Push constants: sama Params-rakenne, `width = height = GRID_N`. Ei uusia kenttiä
  (keskipiste lasketaan widthistä).

## Vaihe 1B: `scripts/disc_cpu_ca.gd` (CPU-referenssi headless-testeihin)

- Deterministinen CPU-steppaus samalle `PackedInt32Array`-gridille ((seed<<8)|mat -soluformaatti).
- Peilaa GLSL:n sääntöjä kannan kautta (DiscGeom.down_of/perp_of). Kattavuus riittää:
  jauheet (suora + diagonaali + uppoaminen nesteeseen), nesteet (alas + diag + perp-levitys
  + öljy nousee vedessä), WOOD_FALLING (+ laskeutuminen takaisin WOODiksi), STEAM (nousu).
  Tuli EI pakollinen.
- Ei atomiikkaa: yksinkertainen solujärjestysiteraatio riittää. Ei tarvitse olla bitilleen
  sama kuin GPU — determinismi ja oikea gravitaatiosuunta riittävät.
- API: `class_name DiscCpuCa`, `func step(grid: PackedInt32Array, n: int, frame: int) -> void`
  (tai vastaava olio-API — dokumentoi selkeästi, disc_world.gd kutsuu tätä headlessissä).

## Vaihe 1C: `tests/unit/test_disc_gravity.gd`

SceneTree-skripti samaan tyyliin kuin test_planet_geom.gd (PASS/FAILED-printit,
`RESULT: N passed, M failed`, quit-koodi). Testit vähintään:

1. `down_of`-yksiköt: 4 sektoria, diagonaalirajat, ei koskaan nollavektori, symmetria.
2. Hiekka pudotettuna pinnan yläpuolelle 4 ilmansuunnasta → CPU-CA N askelta → etäisyys
   keskipisteestä pienenee, päätyy pinnan tuntumaan ja PYSÄHTYY (kiinteää vasten).
3. Sama 45°-diagonaalisuunnista (sektorirajan yli).
4. Vesi kaivetussa kuopassa eri sektoreissa asettuu eikä karkaa.
5. Steam nousee poispäin keskipisteestä joka sektorissa.

Aja: `godot --headless --path . --script res://tests/unit/test_disc_gravity.gd`

## Vaihe 2A: `scripts/disc_world_gen.gd` + `tests/unit/test_disc_worldgen.gd`

- `class_name DiscWorldGen`, `static func generate(seed_val: int, n: int = DiscGeom.GRID_N) -> PackedInt32Array`
- Solu = `(seed << 8) | mat` — seed-variaatio ylätavuun kuten world_gen.gd:ssä.
- Kerrokset etäisyyden r (DiscGeom.radius_of) mukaan, syvyys `d = R_PLANET - r`:
  - `r > R_PLANET`: EMPTY (avaruus)
  - pinta: DIRT ~24 px kerros
  - alla STONE + malmisuonet syvyyden mukaan (blob-suonet riittävät prototyyppiin):
    IRON_ORE matalalla, COAL keskisyvyydellä, GOLD_ORE syvällä, COPPER/RARE_EARTH syvimmällä
  - `r < R_CORE`: BEDROCK
- Determinismi: sama seed → sama grid.
- Testit: avaruus tyhjä, ydin bedrockia, pinta oikealla säteellä, malmiosuudet järkevät
  (esim. 0.5–10 % kivestä per malmi), determinismi.

## Vaihe 3: `scripts/disc_world.gd` + `scenes/disc_main.tscn`

Oma lean scene — EI riippuvuutta pixel_world.gd:hen (saa kopioida sieltä patterneja).

- GPU-polku: RenderingDevice-compute kuten pixel_world.gd:ssä (buffer, shader-load
  simulation_disc.glsl, 12 passia/frame, aktiivisuusbufferi). Renderöinti:
  pixel_render.gdshader UUDELLEENKÄYTETÄÄN sellaisenaan grid-teksturiin.
- EI SubViewport-koko-maailman-komposiittia: TextureRect + kameratransformi →
  renderkustannus = ruutupikselit. Tämä on koko pointti.
- Kamera: pan (WASD + keskihiiren raahaus) + zoom (rulla, kohti kursoria).
- Maalaus: vasen hiiri = maalaa valittu materiaali (1-6 + Q/R = malmit tms.),
  oikea = pyyhi. Screen→grid kameran läpi. Pensselikoko +/-.
- Headless-fallback: `DisplayServer.get_name() == "headless"` → DiscCpuCa-steppaus.
- `func save_debug_png(path: String)` — CPU-renderi materiaaliväreillä (toimii headless).
- Cmdline: `--disc-frames=N --disc-out=path.png` → headless-savuajo: generoi maailma,
  steppaa N framea CPU-CA:lla, tallenna PNG, quit.
- F12 = screenshot (ikkunallinen).
- Aja: `godot --path . scenes/disc_main.tscn`

## Vaihe 4: savutesti `tests/unit/test_disc_smoke.gd`

Boottaa worldgen + CPU-CA 300 framea, assertoi: (1) hiekkaa/vettä liikkunut kohti
keskustaa, (2) grid-invariantit säilyvät (ei materiaalia avaruudessa R_PLANET+marginaalin
ulkopuolella ellei sinne maalattu), (3) tallentaa `tests/output/disc_smoke.png`.

## Konventiot ja työtapa (KAIKILLE AGENTEILLE)

- Työskentele VAIN worktreessä `C:\Users\mauri\Desktop\Git\GodotMining-disc`.
  ÄLÄ koske hakemistoon `C:\Users\mauri\Desktop\Git\GodotMining` (siellä on committoimatonta WIPiä).
- Kommentit suomeksi, tyyppivihjeet aina, snake_case, MAT_-vakiot GDScriptissä / pelkät nimet GLSL:ssä.
- **Commitoi aikaisin ja usein** (prefiksi `disc:`, viesti suomeksi). Jokaisen toimivan
  osakokonaisuuden jälkeen commit — keskeneräinenkin committi on parempi kuin menetetty työ.
- Godot: `C:\Users\mauri\Desktop\Godot\Godot_v4.6.1-stable_win64_console.exe`
- Uuden class_name-luokan jälkeen aja kerran: `<godot> --headless --path . --import`
  (class_name-cache), sitten testit. Commitoi myös generoituvat .uid-tiedostot.
- VAIN --headless-ajoja. Ikkunallisen verifioinnin tekee integraattori lopuksi.
- Olemassaolevia tiedostoja (simulation.glsl, pixel_world.gd, world_gen.gd, ...) EI muuteta
  tässä prototyypissä — kaikki uusi koodi uusiin tiedostoihin.
