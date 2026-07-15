# Demo-version suunnitelma — Bot Mining

**Päiväys:** 2026-07-15
**Pohja:** `docs/GDD_bot_mining.md` (aktiivinen GDD), `docs/fog_and_veins_spec.md`, kartoitus 4 rinnakkaisella agentilla
**Tavoite:** Pelattava DEMO, jonka ydinfiilis on kasvuluuppi:

> **mainaa → osta lisää droneja → mainaa enemmän → osta laitteita ja jalosta → tienaa enemmän → osta lisää botteja → rinse & repeat seuraavaan tieriin → kasvata tehdasta ja tuotantolinjastoa**

Kaikki priorisointi tehdään tämän luupin ehdoilla: jokainen ostettu asia nostaa $/s:ää näkyvästi, ja seuraava askel on aina näkyvissä mutta juuri liian kallis.

---

## 1. Nykytila (kartoitettu 15.7.2026)

### Toimii (GDD Vaihe 1 = MVP, työpuussa committoimattomana)
- Ydinluuppi: V-designaatio (pensseli) → miner louhii → irtomateriaali kasaan → hauler imuroi → base muuttaa rahaksi
- `nav_grid.gd` (A*), `designation_grid.gd`, `bot.gd`/`bot_manager.gd` tilakoneet, 1+1 botti kovakoodattu
- Worldgen: loiva pinta + ~300 px tehdasalusta, syvyyskerrostetut malmi-BLOBIT (COAL/IRON/GOLD/OIL/SAND), bedrock-reunat
- Furnace: SAND→GLASS (16), IRON_ORE→IRON (12), GOLD_ORE→GOLD (8); Crusher: GRAVEL→3×SAND
- simulation.glsl: kaikki malmit + DIRT + GRAVEL putoavat jauheina
- PRICES-hinnasto money_exit.gd:ssä, raha-label
- Testi-infra: 7 unit-testiä, 20 skenaariota, run_all.sh, cpu_ca-headless-fallback (mvp_core_loop)
- I-näppäin: game_view.png + game_state.json

### Puuttuu / rikki (gap-analyysi)

**Talous on yksisuuntainen — rahaa ei voi kuluttaa mihinkään:**
- G1. Bottien osto (spawn basesta, nouseva hinta) — ei toteutettu
- G2. Roolinvaihto miner↔hauler — ei toteutettu
- G3. Rakennukset ilmaisia: `BUILDING_COSTS` on olemassa mutta `money -=` puuttuu, ei can_afford-tarkistusta
- G4. Mk1/Mk2/Mk3-upgrade-tierit — ei toteutettu (vain Mk1-vakiot, bot.gd:14 TODO)

**UI (GDD §7):**
- G5. Osta/rakenna-paneeli välilehdillä (Botit/Rakennukset/Logistiikka) puuttuu — nykyinen on vanha materiaalimaalauspalkki + litteä nappirivi
- G6. $/s-mittari ja bottien tilanäyttö puuttuvat
- G7. Designaatiotyökalussa vain pensseli — yksittäissolu ja laatikkoveto puuttuvat
- G8. Materiaalimaalausta ei ole siirretty debug-menuun

**Logistiikka (GDD §4, Vaihe 2–3):**
- G9. Pickup-pointit — ei toteutettu
- G10. Dump-filtterit (base + koneiden intaket) — ei toteutettu; hauler myy aina kaiken baseen → jalostusketju ei koskaan aktivoidu boteilla
- G11. Conveyor `_is_movable` ei liikuta malmeja/soraa/dirtiä/hiiltä/harkkoja — hihnakuljetus jalostukseen mahdotonta
- G12. Furnace ei auto-connectaudu hihnaan (vain crusher; furnacelta puuttuu get_intake/output_center)

**Maailma & sisältö:**
- G13. Fog of war (light_field.gd, speksi lukittu 15.7.) — 0 % toteutettu
- G14. Mineraalisuonet (worm-walk) + COPPER=20/RARE_EARTH=21 — 0 % toteutettu, malmit blobeina
- G15. Trial-tavoite/lopetus puuttuu (ei win-conditionia, ei progression tunnetta)

**Siivous (GDD §8-mäppäys):**
- G16. sand_mine.gd yhä täysin kytketty (GDD: POISTUU — ristiriidassa louhintatalouden kanssa)
- G17. Kuollut koodi: sling.gd, chicken_spawner.gd, player.gd-jäänteet, ase-koodi (Weapon-enum, _fire_rocket/_fire_laser ilman kutsujia)
- G18. debug_overlay.gd MAT_NAMES kattaa vain ID:t 0–10

**Tunnetut bugit/riskit:**
- B1. dig_sites-FIFO (cap 200) pudottaa kasoja joissa on vielä materiaalia → hauler ei löydä niitä
- B2. `_assign_miner` + `_scan_designations` skannaavat koko 6240-solun gridin per botti 2 Hz — skaalautuu huonosti kun botteja on kymmeniä
- B3. Drill vain pyyhkii pikselit tyhjäksi, ei tuota mitään → demote debug-rakennukseksi

---

## 2. Demo-version määritelmä (Definition of Done)

**Ydin = kasvuluuppi toimii ja tuntuu hyvältä:**

1. **Suljettu talousluuppi:** raha kertyy JA kuluu — botit, rakennukset ja upgradet maksavat; nouseva bottihinta; eka bottiosto ~2–3 min (GDD §6.4). Ostohetkellä $/s nousee havaittavasti → dopamiini.
2. **Skaalautuva lauma:** osta botteja paneelista, vaihda rooleja +/- säätimillä, Mk-upgradet per botti. 10+ bottia yhtä aikaa töissä ilman fps-romahdusta tai jumiutumista.
3. **Jalostusketju toimii boteilla:** base-filtteri + koneen input-dump + pickup outputilla → IRON_ORE→IRON-ketju tuottaa ~5× raakaan verrattuna ilman käsityötä. Tuotantolinjasto (kone + hihnat + haulerit) on rakennettavissa ja LAAJENNETTAVISSA.
4. **Tier-tikapuut — "seuraava askel aina näkyvissä":**
   - **Tier 1** (0–3 min): pintadirt/kivi/hiili 2 botilla → varaa 3.–4. bottiin
   - **Tier 2** (3–8 min): rautasyvyys + furnace → jalostettu rauta moninkertaistaa $/s
   - **Tier 3** (8–15 min): kulta + crusher-kierrätys + Mk2-upgradet + useampi tuotantolinja
   - **Tier 4** (15–25 min): syvät suonet (COPPER/RARE_EARTH), Mk3, tehdas täydessä vauhdissa
   Hinnat toimivat portteina; välitavoite-toastit ("Uusi syvyys saavutettu!", "Ensimmäinen harkko!") rytmittävät.
5. **UI 2.0 — täysremontti (MUST HAVE):** pelaajan UI suunnitellaan puhtaalta pöydältä talousluupin ympärille. Vanha materiaalimaalauspalkki ja litteä nappirivi POISTETAAN pelaaja-UI:sta kokonaan (siirto debug-menuun F4). Ks. §UI 2.0 -spesifikaatio alla.
6. **Kasvu näkyy** (GDD: "isompi tehdas, enemmän liikettä ruudulla, syvempi kaivos"): $/s-mittari, bottilaskuri, ruudulla vilisee droneja ja linjastoja.
7. **Demo-kaari:** aloitusopaste → tier-välitavoitteet → "Demo complete" -ruutu (esim. $10 000 tai RARE_EARTH jalostettu) + "jatka vapaasti" -moodi.
8. **Laatu:** 60 fps 1664×960, run_all.sh vihreä, ei kuolleen koodin jäänteitä core-pelissä.

**Stretch (tehdään jos aikataulu sallii, EI blokkaa demoa):** fog of war (G13) — tuo tunnelmaa ja löytämisen iloa, mutta kasvuluuppi ei riipu siitä.

---

## 3. Työn jako — lane-omistajuus (ei tiedostopäällekkäisyyttä)

Konfliktien minimoimiseksi jokainen lane OMISTAA tiedostonsa. `pixel_world.gd` on jaettu hotspot → sitä editoivat lanet ajetaan worktreissä ja merge-junassa määrätyssä järjestyksessä.

| Lane | Omistaa | Tehtävät | Riippuu |
|---|---|---|---|
| **E — Siivous** | pixel_world.gd (poistot), poistettavat tiedostot | G16, G17 (EI ui.gd:tä — B hoitaa), launcher → debug-only, drill demote (B3) | — (AJETAAN ENSIN) |
| **A — Botit & talous** | bot.gd, bot_manager.gd, money_exit.gd, UUSI logistics.gd | G1, G2, G4, G9, G10 (datamalli+bottilogiikka), B1, B2 | E merged |
| **B — UI 2.0 (täysremontti)** | ui.gd (uudelleenkirjoitus), build_preview.gd, debug_overlay.gd | UI 2.0 -speksi (§3.1), G5, G6, G7 (UI-osa), G8, G3 (osto-napit + can_afford), G18 | API-kontrakti (§4) |
| **C — Maailma & materiaalit** | world_gen.gd, simulation.glsl, paletit/render-shader (materiaaliosa), worldgen_test.gd | G14: COPPER/RARE_EARTH + worm-walk-suonet; headless-iteraatio ENNEN pelin käynnistystä | — (voi alkaa heti) |
| **D — Koneet & hihnat** | conveyor_belt.gd, furnace.gd, crusher.gd, drill.gd | G11, G12, koneiden input-dump-rajapinta (A:n logistics-mallia vasten) | API-kontrakti |
| **F — Fog of war (STRETCH)** | UUSI light_field.gd, render-shaderin light-osa | G13 speksin mukaan — vain jos Wave 2 etenee aikataulussa | C merged (sama shader) |
| **G — Demo-kaari & integraatio (YDIN)** | pixel_world.gd (wiring), scenes, game_state.json | G15 (tier-välitavoitteet + demo complete), G3 (money -= sijoituksessa), jalostus-E2E, tier-balanssi, uudet skenaariotestit | A+B+C+D merged |

### 3.1 UI 2.0 -spesifikaatio (lane B — puhtaalta pöydältä, EI vanhan päälle)

Periaate: pelaaja on kaivosyhtiön johtaja. UI:n jokainen elementti palvelee luuppia
*katso tulovirtaa → päätä seuraava ostos → sijoita → katso kasvua*. Materiaalimaalaus,
aseet ja sim-nopeussäädöt kuuluvat debug-menuun, eivät pelaajan eteen.

**Layout:**

```
┌──────────────────────────────────────────────────────────────┐
│ YLÄPALKKI: $12 450  (+$38/s)   🤖 Miner 4/5 | Hauler 3/3     │
│            [välitavoite-toast ilmestyy tähän]        FPS(pieni)│
│                                                              │
│                     ( P E L I N Ä K Y M Ä )                  │
│                                                              │
│ TYÖKALURIVI: [Louhinta V] [pensseli|laatikko|solu] koko ─○─  │
├──────────────────────────────────────────────────────────────┤
│ ALAPANEELI (piilotettavissa, TAB):                           │
│ [ BOTIT ]  [ RAKENNUKSET ]  [ LOGISTIIKKA ]                  │
│  Osta Miner $300   Furnace $150 (kortti)   Pickup-point $80  │
│  Osta Hauler $300  Crusher $120            Dump-point $60    │
│  Miner [-] 4 [+]   Hihna $50               Base-filtteri ☑☐  │
│  Mk-upgradet/botti  → klik = sijoitustila + ghost-preview    │
└──────────────────────────────────────────────────────────────┘
```

**Säännöt:**
- **Yläpalkki:** raha isolla, $/s (liukuva 10 s keskiarvo, vihreä kun kasvaa), bottilaskuri
  rooleittain (aktiiviset/kaikki). FPS pienenä kulmassa.
- **Alapaneeli:** kolme välilehteä (Botit / Rakennukset / Logistiikka). Jokainen ostettava
  on kortti: nimi + hinta + 1 rivin kuvaus. **Ei varaa → kortti harmaana + hinta punaisena**
  (can_afford). Osto EI tapahdu jos raha ei riitä.
- **Sijoitusflow:** kortti → sijoitustila → ghost-preview (build_preview.gd) → vasen hiiri
  sijoittaa ja vähentää rahan, Esc/oikea hiiri peruu. Sama flow kaikille rakennuksille ja
  logistiikkavyöhykkeille.
- **Designaatiotyökalu:** oma työkalurivi (ei haudattuna paneeliin), 3 moodia: pensseli /
  laatikkoveto / yksittäissolu. V togglaa. Oikea hiiri poistaa. Moodi + koko näkyvissä.
- **Botit-välilehti:** osta-napit hintoineen (nouseva hinta näkyy), roolijako [-] N [+]
  -säätimillä, per-botti Mk-upgrade (lista tai valitse botti klikkaamalla maailmasta).
- **Logistiikka-välilehti:** pickup-/dump-pointin sijoitus + valitun vyöhykkeen
  materiaalifiltteri-checkboxit; Base-filtterin asetus.
- **Onboarding:** max 3 peräkkäistä opastetta ("Paina V ja maalaa alue" → "Hauler tuo
  saaliin baseen" → "Osta kolmas botti kun $300 täynnä"), häviävät kun teko on tehty.
- **Toastit:** tier-välitavoitteet yläpalkin alle ("Ensimmäinen harkko! Jalostettu myy 5×").
- **Poistuu pelaaja-UI:sta:** materiaalinapit, pensselimaalaus (materiaalien), nopeusnapit,
  F5/F9-napit, Spawner/Kaivos/Linko-napit, ase-tilatekstit. Kaikki tarvittava näistä
  siirtyy debug-menuun (F4). `sand_mine`/`launcher` poistuvat kokonaan (lane E).
- **Tekninen:** ui.gd kirjoitetaan uusiksi ohjelmallisesti (nykyinen tapa ok), kutsuu VAIN
  §4 API-kontraktin metodeja — ei suoraan bot_managerin/koneiden sisuksia. Skaalautuu
  1664×960-ikkunaan, nearest-filter-fontit.

### 3.2 Työmääräyskortit (ripoteltavissa suoraan Opus-agenteille)

Jokainen kortti on itsenäinen briefi: sisältö + omistetut tiedostot + DoD + testit.
Agentti EI koske muiden lanejen tiedostoihin; pixel_world.gd-kytkennät listataan ja
integraattori (orkestroija/lane G) tekee ne mergessä jos konflikti uhkaa.

**E1 — Siivous** *(Wave 0, yksin, PIENI)*
Poista pelistä: sand_mine (preload, place/update/save/load pixel_world.gd:ssä),
sling.gd, chicken_spawner.gd, player.gd-jäänteet (`var player`), ase-koodi (Weapon-enum,
current_weapon, _fire_rocket_at_cursor, _fire_laser). Launcher + drill: koodi jää mutta
kytketään debug-lipun taakse. EI kosketa ui.gd:tä (B poistaa napit).
*DoD:* peli käynnistyy, run_all.sh vihreä, grep ei löydä viittauksia poistettuihin.

**A1 — Bottien osto & roolinvaihto** *(Wave 1, lane A)*
`buy_bot(role)`: hinta 300×1,5^n, money-vähennys, spawn basen spawn_pos:sta.
`set_role(bot_id, role)`: kesken olevan työn siisti keskeytys (cargo dumpataan / designaatio
vapautetaan CLAIMED→QUEUED). `get_fleet_stats()`: määrät/tilat/roolit UI:lle + $/s-data.
*DoD:* unit-testit osto+roolinvaihto; 10 botin spawn ilman jumia (fleet_scale-skenaario).

**A2 — Mk-tierit** *(Wave 1, lane A)*
bot.gd: tier-kenttä + Mk1/Mk2/Mk3-taulukko (GDD §2.5: capacity 40/90/180, mine 25/50/90,
speed 40/70/110). `upgrade_bot(bot_id)`: hinta 400/900, money-vähennys.
*DoD:* unit-testi; upgraden vaikutus mitattavissa (louhintanopeus kasvaa).

**A3 — Logistics: pickup/dump/filtterit** *(Wave 1, lane A)*
UUSI logistics.gd: pickup-pointit (rect + filter_mask + prio), dump-pointit (rect +
filter_mask), base-filtteri. Hauler: kasan valinta pickup-vyöhykkeiltä, dumpin valinta
"filtteri hyväksyy suurimman osan kuormasta ja lähinnä" (GDD §4.2). Koneiden input-dumpit
rekisteröityvät D-lanen `get_input_dump()`-rajapinnalla.
*DoD:* unit-testi filtterivalinnasta; hauler vie IRON_OREn furnace-dumppiin kun base-filtteri
kieltää raakamalmin.

**A4 — Bugikorjaukset & skaalaus** *(Wave 1, lane A)*
B1: dig_sites — älä pudota kasoja joissa materiaalia (re-scan tai kasvata cap + poista vain
tyhjät). B2: assignment-skannauksen optimointi (frontier-cache tai dirty-lista, ei koko
gridiä per botti).
*DoD:* mvp_core_loop edelleen vihreä; 20 botin assign-tikki < 2 ms.

**B1 — UI 2.0** *(Wave 1, lane B — §3.1 speksin mukaan)*
ui.gd uusiksi: yläpalkki, alapaneeli välilehdillä, työkalurivi, sijoitusflow, onboarding,
toastit. debug_overlay.gd: MAT_NAMES täydennys (G18). Kehitys API-kontraktia vasten —
stub-toteutus kunnes A merged.
*DoD:* kaikki ostot mahdollisia vain UI:n kautta ja vain jos raha riittää; vanha palkki
poissa; materiaalimaalaus löytyy debug-menusta; onboarding vie nollasta ekaan ostoon.

**C1 — Uudet materiaalit + suonet** *(Wave 1, lane C — fog_and_veins_spec Vaihe 1)*
COPPER=20, RARE_EARTH=21 kaikkialle (world_gen, simulation.glsl falls/is_powder, paletit
20→22, clampit). `_place_vein_set()` worm-walk korvaa blobit; syvyystierit: COAL 0.0–0.35,
IRON 0.10–0.55, COPPER 0.35–0.75, GOLD 0.55–0.90, RARE_EARTH 0.75–1.0. PRICES: COPPER ~4,
RARE_EARTH ~8. worldgen_test.gd: värit + suoni-assertit; iteroi headless ENNEN pelin
käynnistystä (feedback_worldgen_testing).
*DoD:* worldgen_test tulostaa suonijakauman ja preview näyttää suonet; malmit putoavat
jauheina; ei magentaa previewissä.

**D1 — Hihnat & koneintegraatio** *(Wave 1, lane D)*
conveyor `_is_movable` += DIRT, GRAVEL, IRON_ORE, GOLD_ORE, COAL, COPPER, RARE_EARTH
(+harkot jos rigid-käytös sallii). Furnace: get_intake_center/get_output_center +
auto-connect (kuten crusher). Furnace+crusher: `get_input_dump()` (rect + reseptimaski)
A3:n logisticsille. Uudet reseptit: COPPER→(harkko), RARE_EARTH→(jalostettu) furnaceen.
*DoD:* conveyor_*-skenaariot vihreitä + uusi belt_ore.json; malmi kulkee hihnalla furnaceen
ja jalostuu.

**G1 — Talouden sulku & tier-kaari** *(Wave 2, YDIN)*
money -= kaikissa sijoituksissa (BUILDING_COSTS käyttöön), can_afford-portit pelilogiikassa
(ei vain UI:ssa). Tier-välitavoitteet + toast-eventit + "Demo complete" ($10 000 tai
RARE_EARTH jalostettu) + jatka vapaasti. Onboarding-tilakone (UI näyttää, G triggaa).
*DoD:* demo pelattavissa alusta loppuun; tavoiteajat §2 kohdan 4 mukaiset ±50 %.

**G2 — Jalostus-E2E & balanssi** *(Wave 2, YDIN)*
Koko ketju boteilla: designaatio → miner → hauler → furnace-dump → pickup output → base.
Balansoi: eka botti 2–3 min, jalostus ≥3× raaka-arvo, jokainen tier-hyppy näkyy $/s:ssä.
Uudet skenaariot: bot_buy.json, refine_loop.json, veins_present.json, fleet_scale.json.
*DoD:* skenaariot vihreinä run_all.sh:ssa; balanssiraportti (min → $/s-käyrä).

**F1 — Fog of war** *(Wave 2, STRETCH — vain jos G etenee)*
fog_and_veins_spec Vaihe 2: light_field.gd (208×120 R8, explored-muisti), render-shaderiin
light_tex, emitterit (kuilut/botit/base/koneet), lamppu-rakennus $40 UI:hin.
*DoD:* tutkimaton maanalainen musta, tutkittu himmeä, valot toimivat, ei fps-pudotusta.

## 4. API-kontrakti (kirjoitetaan ennen Wave 1:tä, jotta lanet voivat edetä sokkona)

Lyhyt `docs/API_CONTRACT_trial.md`:
- `bot_manager.buy_bot(role: int) -> bool` (tarkistaa hinnan, vähentää rahan, spawnaa basesta; hinta 300 × 1.5^n)
- `bot_manager.set_role(bot_id: int, role: int) -> void`, `bot_manager.upgrade_bot(bot_id: int) -> bool`
- `bot_manager.get_fleet_stats() -> Dictionary` (määrät, tilat, $/s UI:lle)
- `logistics.add_pickup_point(rect, filter_mask) / add_dump(rect, filter_mask) / base_filter`
- Koneet: `get_input_dump() -> Dictionary` (rect + reseptin input-maski)
- UI kutsuu vain näitä — ei suoraan bottien sisuksia.

## 5. Aikataulu — aallot (maksimirinnakkaisuus)

```
Wave 0 (esityö, ~15 min, EI rinnakkain):
  0.1 Varmista että repossa työskentelevät agentit ovat valmiita → committaa baseline
  0.2 Kirjoita API-kontrakti (docs/API_CONTRACT_trial.md)
  0.3 Lane E: siivous (pieni, nopea) → merge heti

Wave 1 (4 Opus-agenttia RINNAKKAIN, worktreet):
  A: Botit & talous        (isoin — aloitetaan ensin)
  B: UI-paneeli            (kontraktia vasten, stubit kunnes A merged)
  C: Suonet + materiaalit  (headless-worldgen-iteraatio)
  D: Koneet & hihnat
  Merge-juna: C → D → A → B (integraattori ratkoo konfliktit + ajaa testit per merge)

Wave 2 (2–3 Opus-agenttia RINNAKKAIN):
  G (YDIN): Demo-kaari + jalostus-E2E + tier-balanssi + uudet testit
     (uudet skenaariot: bot_buy.json, refine_loop.json, veins_present.json,
      fleet_scale.json = 10+ bottia ilman jumia/fps-romahdusta)
     Balanssitavoite: jokainen tier-siirtymä = selvä $/s-hyppy; seuraava ostos
     aina ~1-3 min päässä nykyisellä tulovirralla
  F (STRETCH): Fog of war (C:n shaderin päälle) — aloitetaan vain jos G etenee;
     demon julkaisu EI odota F:ää

Wave 3 (QA, rinnakkain):
  - debugger: run_all.sh + perf 60fps + headless-skenaariot
  - reviewer: koko diffin katselmointi
  - Pelin käynnistys + I-dump analyysi (see-game) + balanssipeli
```

**Kriittinen polku:** E → A → G → QA. C, D, B ja F limittyvät sen rinnalle.

## 6. Balanssin lähtöarvot (GDD §6)

- Botti: $300, hinta ×1,5 per seuraava; Mk2 $400, Mk3 $900
- Hihna $50, Furnace $150, Crusher $120, Pickup-point $80, Dump-point $60, Lamppu $40 (uusi, fog)
- Myynti palauttaa 50 %
- Suonitierit: COAL 0.0–0.35, IRON 0.10–0.55, COPPER 0.35–0.75, GOLD 0.55–0.90, RARE_EARTH 0.75–1.0
- Hinnat: COPPER_ORE ~4/px, RARE_EARTH ~8/px raakana (jalostettuna ×2–3) — säädetään pelaamalla

## 7. Riskit

| Riski | Mitigaatio |
|---|---|
| pixel_world.gd merge-konfliktit | Lane-omistajuus + merge-juna; vain E ja G editoivat sitä laajasti |
| Committoimaton työpuu (~1100 riviä) | Wave 0 commit ENNEN worktree-haarautusta |
| Render-shaderin kaksi muokkaajaa (C: paletti, F: light) | F ajetaan vasta C:n mergen jälkeen |
| Balanssi vaatii iterointia | G-lane pelaa headless-skenaarioilla + tuning-vakiot yhteen paikkaan |
| Haulerin filtteripoiminta epädeterminististä | GDD §10.10: pickup-vyöhyke scooppaa säteeltä; testataan refine_loop.json:lla |
