# GodotMining

GPU-kiihdytetty falling sand -simulaatio Godot 4.2:lla.

## Työskentelytapa — Automaattinen orkestrointi

Käyttäjä kertoo mitä haluaa tehdä. Sinä orkestroit työn automaattisesti oikeille agenteille. Käyttäjän EI tarvitse mainita agentteja nimeltä.

### Workflow

1. **Analysoi pyyntö** — Mitä käyttäjä haluaa? Onko se feature, bugikorjaus, refaktorointi, analyysi?
2. **Suunnittele** — Jos tehtävä on ei-triviaali, kutsu ensin `game-architect` tekemään suunnitelma
3. **Toteuta** — Kutsu `programmer` toteuttamaan koodi suunnitelman pohjalta
4. **Tarkista** — Kutsu `debugger` tarkistamaan kriittiset muutokset (GPU-koodi, materiaalivuorovaikutukset)
5. **Katselmoi** — Kutsu `reviewer` tekemään pikatarkistus lopuksi
6. **Raportoi** — Kerro käyttäjälle lyhyesti mitä tehtiin ja mikä on tulos

### Milloin mitäkin agenttia

| Tilanne | Agentit |
|---|---|
| Uusi feature / iso muutos | architect → programmer → debugger → reviewer |
| Pieni muutos / bugikorjaus | programmer → reviewer |
| "Mikä on vialla?" / analyysi | debugger |
| Arkkitehtuurikysymys / suunnittelu | architect |
| Koodimuutos + GPU-shader | programmer → debugger → reviewer |
| Uusi grafiikka / sprite | artist |
| Feature joka vaatii uuden assetin | architect → artist → programmer |

### Rinnakkaisuus

- Kutsu agentteja rinnakkain kun ne eivät riipu toisistaan (esim. debugger voi analysoida samalla kun architect suunnittelee)
- Älä kutsu kaikkia agentteja pienille tehtäville — käytä harkintaa
- Yksinkertaisiin kysymyksiin vastaa itse ilman delegointia

## Arkkitehtuuri

- **GPU Compute Shader** (`shaders/simulation.glsl`): Margolus-naapurusto 2x2 lohkoissa, 12 passia/frame. Materiaalit uint32: `(seed << 8) | material_id`
- **Renderöinti** (`shaders/pixel_render.gdshader`): Materiaali-ID → väri + variaatio + efektit (tulen välke, veden aalto, höyryn häive)
- **Pelilogiikka** (`scripts/pixel_world.gd`): TextureRect, CPU↔GPU synkronointi, input-käsittely, maalaus
- **Fysiikkamoottori** (`scripts/physics_world.gd`): Noita-tyylinen hybridi — rigid body -kappaleet CPU:lla
- **Rigid Body** (`scripts/rigid_body_data.gd`): Yksittäisen kappaleen tiedot (massa, sijainti, kulma, nopeus)
- **CCL** (`scripts/ccl.gd`): Union-Find connected component labeling — tunnistaa yhtenäiset kappaleet
- **Puun tuki** (`scripts/wood_support.gd`): BFS-tukitarkistus puupikseleiden putoamiselle
- **UI** (`scripts/ui.gd`): Materiaalinapit, pensselikoko, FPS-näyttö

## Materiaalit

EMPTY=0, SAND=1, WATER=2, STONE=3, WOOD=4, FIRE=5, OIL=6, STEAM=7, ASH=8, WOOD_FALLING=9

## Simulaatioruudukko

320×180 pikseliä, näytetään 1280×720 ikkunassa (4x skaalaus, nearest-filter)

## Koodauskonventiot

- Kieli: GDScript (Godot 4.2), GLSL 450 compute shaderit
- Kommentit suomeksi
- snake_case funktioille ja muuttujille, UPPER_CASE vakioille
- Materiaalivakiot: `MAT_` prefix GDScriptissä, pelkkä nimi GLSL:ssä
- Tyyppivihjeet aina (`var x: int`, `func foo() -> void`)
- Godot-signaalit `.connect()` -kutsulla, ei editorissa

## Komennot

- Aja peli: Godot-editorissa F5 tai `godot --path . --main-loop`
- Materiaalinvaihto: näppäimet 1-6, E = tyhjennys
- Maalaus: vasen hiiri = maalaa, oikea = pyyhi
- Leikkaus: X = leikkaustila päälle/pois, vasen hiiri leikkaa kiveä/puuta
- Tyhjennys: C = tyhjennä kenttä
- **I** = tallentaa AI-debugdata: `game_view.png` (kuvakaappaus) + `game_state.json` (pelitila)

## AI-pelinäkymä

Kun käyttäjä viittaa kuvakaappaukseen, screenshottiin, pelimaailmaan tai tallentamaansa debugdataan — **lue aina ensin**:
- `C:\Users\mauri\Desktop\Git\GodotMining\game_view.png` (visuaalinen näkymä, Read-työkalu)
- `C:\Users\mauri\Desktop\Git\GodotMining\game_state.json` (pelitila: pelaaja, ase, gravity gun, FPS jne.)

Jos tiedostoja ei löydy: pyydä käyttäjää painamaan I pelissä ensin.

## Tärkeät rajoitteet

- Compute shader käyttää push constanteja (max 128 tavua)
- GPU-bufferi on 320×180×4 = 230KB, ladataan kokonaan joka maalauksen jälkeen
- Margolus-offset vaihtuu joka passilla — älä riko offset-logiikkaa
- RenderingDevice luodaan _ready():ssa ja vapautetaan NOTIFICATION_PREDELETE:ssä

## Fysiikkamoottori (Noita-tyylinen hybridi)

- CA-simulaatio GPU:lla + rigid body -fysiikka CPU:lla
- Kivi-kappaleet: CCL tunnistaa yhtenäiset alueet → RigidBodyData
- CPU erase/write -sykli: poista vanhat pikselit → integroi fysiikka → kirjoita uudet
- Staattinen kivi (lattia) ei liiku, irrallinen kivi putoaa ja pyörii
- Leikkaus jakaa kappaleen: BFS-yhteyden tarkistus → split → pienet palaset mursketta
- Puu putoaa kun tuki katoaa: WoodSupport BFS joka 10. frame → WOOD_FALLING
- WOOD_FALLING palautuu WOODiksi kun laskeutuu
