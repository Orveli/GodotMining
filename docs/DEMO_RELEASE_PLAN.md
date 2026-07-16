# Demo-julkaisusuunnitelma — Bot Mining

**Päiväys:** 2026-07-16
**Pohja:** `docs/DEMO_PLAN.md` (historiallinen — Wave 0/1/2 pääosin TOTEUTETTU), `docs/GDD_bot_mining.md`, working tree -verifiointi 16.7.2026
**Tavoite:** Saada peli demoversiona *julkaisukuntoon* — pelattava, bugivapaa, standalone-buildattava.

> **Keskeinen jännite, joka ohjaa koko suunnitelmaa:**
> Automaattitestit ovat vihreitä (9/9 unit-tiedostoa, E2E PASS), mutta käyttäjän KOKEMUS on
> ettei peli ole pelattava. Testit mittaavat mekaniikan *toimivuuden*, eivät *pelituntumaa,
> balanssia tai UX:ää*. Suurin tuntematon ei ole koodi vaan koettu pelattavuus.
> **Siksi suunnitelma ei ala koodauksella vaan oikealla pelattavuusauditilla.** Tunnetut
> aukot (alla) ovat auditin raaka-ainetta, mutta P0-priorisointi lukitaan vasta kun tiedämme
> MIKSI peli tuntuu rikkinäiseltä.

---

## 1. Tilannekuva (16.7.2026)

Vanhan `DEMO_PLAN.md`:n Wave 0–2 on käytännössä toteutettu. Working tree on ~1500 riviä
HEADin edellä, kaikki committoimatta. Verifioitu tila:

**Valmista ja toimii:**
- Suljettu talousluuppi: bottien osto (spawn basesta), roolinvaihto, Mk1/2/3-upgradet,
  rakennusten osto rahavähennyksellä, can_afford-portit.
- Logistiikka: `logistics.gd` (pickup/dump-vyöhykkeet + filtterit). **Base-dropoff toteutettu**
  — haulerit tiputtavat basen yllä olevaan dropoff-vyöhykkeeseen, CA pudottaa intakeen, muuntuu
  rahaksi. Pelaaja voi rakentaa oman dropoffin koneille.
- Koneet: conveyor liikuttaa kaikki malmit + COPPER/RARE_EARTH; furnace auto-connect + input-dump.
- Demo-kaari: 9 virstanpylvästä + demo_complete-ehto, 3-vaiheinen onboarding, toastit.
- UI 2.0: amber-teema, ikoni-actionbar, build/bot-trayt, diegeettiset popoverit, $/s-mittari,
  designaation 3 moodia, nopeuskontrolli (Tauko/1x/2x/3x/4x).
- Fog of war + mineraalisuonet (COPPER=20, RARE_EARTH=21, worm-walk).
- Bottien ruuhkanhallinta 3 kerrosta.
- Siivottu: sankari/sand_mine/aseet poistettu, launcher+drill debug-portin takana.

**Testit:** 9/9 unit vihreänä, E2E `mvp_core_loop` PASS (93,8 % designaatioista kulutettu),
`fleet_scale` 10 botilla PASS, pause-skenaariot PASS, ikkunallinen GPU-boot puhdas (RTX 3060).

Yksityiskohtainen aukkolista on §2 (Vaihe 2) ja §5 (Vaiheet 3–4) alla, työkortteina §7.

---

## 2. Arkkitehdin päätökset (lukitaan ENNEN työn aloitusta)

Nämä ovat tuoteomistajan/arkkitehdin päätöksiä, jotka poistavat epävarmuuden ja pitävät
demon scopen tiukkana. Ohjelmoijan ei tarvitse arvailla.

### D1 — Bottihinnoittelu: `300 × 1.5^n`, EI `50 × 2^n`

Koodi käyttää nyt `next_bot_price() = 50 * (1 << n)` (bot_manager.gd:199-200): 50, 100, 200,
400, 800… GDD §6.4 määrittelee `300 × 1.5^n` ja tavoitteen "eka lisäbotti ~2–3 min".
`bot_buy.json`-skenaario odottaa vanhaa GDD-hinnoittelua → FAILAA nykykoodia vasten.

**Päätös:** Palautetaan GDD-linja `300 × 1.5^n` (450, 675, 1012, 1518…). Perustelu:
- `50 × 2^n` on väärä kahdesti: 3. botti $50 on triviaalin halpa (~17 s → ei "säästä ostoon"
  -jännitettä), mutta tuplaantuva käyrä tekee laumasta liian kalliin liian nopeasti (6. botti
  $800, 7. $1600) → skaalautuva lauma tyssää.
- `1.5×` antaa loivan kasvun joka tukee "kasvata laumaa" -fantasiaa JA osuu GDD:n balanssitavoitteeseen.

**Invariantti ei ole vakio vaan tavoite:** *eka lisäbotti saavutettavissa ~2–3 min aktiivista
peliä.* Aloitushinta $300 on hypoteesi, joka VAHVISTETAAN auditin mittaaman $/s:n mukaan (§Vaihe 1).
Jos todellinen alkutulovirta on paljon oletettua pienempi (todennäköistä, ks. I-dump "miner
idlaa, $65"), oikea korjaus voi olla tulovirran juurisyyssä, ei hinnassa. Päivitä koodi JA
`bot_buy.json` samaan hintaan.

### D2 — Save/load: LEIKATAAN demosta

F5/F9 → `save_world`/`load_world` (pixel_world.gd:2089-2090) tallentaa vain grid+rakennukset+rahat,
EI botteja, logistiikkavyöhykkeitä, designaatioita eikä demo-edistymää → lataus rikkoo pelitilan.

**Päätös:** Irrota F5/F9 pelaajalta (debug-lipun taakse jos hyödyllinen testaukselle). EI koko
pelitilan serialisointia demoon. Perustelu: demo on yhden istunnon kokemus (15–25 min); bottien,
vyöhykkeiden, designaatioiden ja edistymän serialisointi on iso, bugialtis urakka joka ei palvele
kasvuluuppia. Rikkinäinen save on huonompi kuin ei saania. Merkitään demon jälkeiseksi työksi.

### D3 — COPPER/RARE_EARTH: MYYDÄÄN RAAKANA, ei uusia jaloste-ID:itä

Raakahinnat ovat jo koodissa (money_exit.gd:36-37: COPPER 4/px, RARE_EARTH 8/px), materiaalit
putoavat jauheina, paletit ja conveyor tukevat niitä. Ainoa "puuttuva" on jalostusreseptit.

**Päätös:** COPPER ja RARE_EARTH myydään RAAKANA premium-hinnalla. EI uusia jaloste-materiaali-ID:itä
demoon. Perustelu:
- Uusi jaloste-ID koskee `simulation.glsl`:ää (falls/is_powder), render-shaderin palettia, clampeja,
  PRICES-taulua JA vaatii headless-worldgen-verifioinnin → merkittävä GPU-riski pienelle hyödylle.
- Rauta- (IRON_ORE→IRON) ja kultaketju (GOLD_ORE→GOLD) OPETTAVAT jo "jalostus moninkertaistaa arvon"
  -opin. COPPER/RARE_EARTH-jalostus ei opeta mitään mekaanisesti uutta — se on lisää samaa.
- "Syvemmältä arvokkaampaa" -fantasia toteutuu raakamyynnillä (fog + suonet + premium-hinta).
- **Tämä poistaa gap 3:n kokonaan: raakamyynti toimii jo, tehtävä kutistuu "verifioi että base-dropoff
  hyväksyy ne + hienosäädä premium-hinta niin tier-hyppy näkyy $/s:ssä".**
- Jos auditti näyttää endgamen litteäksi → yksi jalostetumpi tier on ENSIMMÄINEN stretch demon jälkeen.

### D4 — gpu_passes-adaptiivinen throttle: korjaa tai poista

`restore` (pixel_world.gd:766-769) pyyhkii adaptiivisen säädön (2272-2275) joka framella → jumissa
8:ssa, kuollut koodi. **Päätös:** ohjelmoija joko (a) korjaa järjestyksen niin adaptiivinen arvo
säilyy restore yli, tai (b) poistaa adaptiivisen throttlen ja kiinnittää passimäärän. Kumpi tahansa
vaatii **ikkunallisen FPS-verifioinnin** (ei mitattavissa headlessissä).

### D5 — Fleet-laskuri näkyviin

Miner X/Y, Hauler X/Y -laskuri on F3-debug-portin takana; DEMO_PLANin DoD halusi sen näkyviin.
**Päätös:** nosta yläpalkkiin pysyvästi (data on jo `get_fleet_stats()`:ssa).

### D6 — Auditti ennen koodia (menetelmä, ei vain vaihe)

Vaihe 1 EI ole koodausta vaan oikea pelisessio joka tuottaa konkreettisen vika/kitkalistan.
Se UUDELLEENPRIORISOI Vaiheen 2 P0:t koetun kokemuksen mukaan. Emme lukitse "audit-löydös"-korjauksia
etukäteen — tunnetut gapit ovat lähtökohta, mutta oikea P0 voi olla jokin auditissa paljastuva
UX-kitka (vahva hypoteesi: **pelaaja ei näe MIKSI botti idlaa**, ks. §Vaihe 1).

---

## 3. Demo-julkaisun Definition of Done

Demo on julkaisukunnossa kun KAIKKI täyttyy:

1. **Pelattavuus:** ulkopuolinen voi käynnistää buildin, ymmärtää mitä tehdä (onboarding vie
   nollasta ekaan ostoon), ja pelaa demo-kaaren läpi 15–25 min ilman jumia tai "en tajua mitä
   tapahtuu" -hetkiä. Auditin kitkalista on nollattu P0-osalta.
2. **Talous tuntuu:** eka lisäbotti ~2–3 min, jokainen tier-hyppy näkyy $/s:ssä, seuraava ostos
   aina ~1–3 min päässä. Demo läpäistävissä (money ≥ 10000 tai RARE_EARTH myyty).
3. **Julkaisukehys:** päävalikko (Aloita/Lopeta), demo complete → "pelaa uudestaan / vapaa peli",
   pause/quit-flow. Peli ei boottaa suoraan simulaatioon eikä ole umpikujaa.
4. **Ääni:** minimi-SFX-setti (louhinta, kassa, milestone, UI-klik, ambient-humina). Demo ei
   tunnu rikkinäiseltä hiljaisuudelta.
5. **Standalone-build:** `export_presets.cfg` Windowsille, versionumero project.godotissa, ikoni.
   Buildattu .exe boottaa puhtaalla koneella ilman editoria.
6. **Laatu:** 60 fps 1664×960, `run_all.sh` vihreä (ml. korjattu `bot_buy.json`), ei debug-vuotoja
   pelaaja-UI:hin, ei kuolleen koodin viittauksia poistettuihin järjestelmiin.

**Nimenomaisesti scopen ULKOPUOLELLA (ei demoon):** koko pelitilan save/load (D2), uudet
jaloste-materiaalit (D3), uudet featuret jotka eivät palvele kasvuluuppia tai julkaisukelpoisuutta.

---

## 4. Vaihe 0 — Baseline (esityö, ~20 min, EI rinnakkain)

Pakollinen ennen mitään muuta. Työpuu on ~1500 riviä committoimatta.

- **0.1 Baseline-commit.** Committaa koko working tree (kaikki verifioitu toimivaksi). PAKKO ennen
  worktree-haarautusta — muuten Vaiheen 2 rinnakkaiset lanet eivät voi eristyä.
- **0.2 Korjaa `bot_buy.json`.** Päivitä testi vastaamaan päätöstä D1 (`300 × 1.5^n`) ja päivitä
  `next_bot_price()` samaan. Aja `run_all.sh` → kaikki vihreä. (Tämä on ainoa koodimuutos ennen
  auditia, koska se on triviaali balanssi-desisio joka ei riipu auditista.)
- **0.3 Sulje handoff.** `restardted_session_delete_this_file_after_completion.md` on jo poistettu
  työpuusta — varmista ettei se palaa committiin.

**DoD:** `git status` puhdas, `run_all.sh` 100 % vihreä, HEAD sisältää koko aiemman työn.

---

## 5. Vaiheet 1–4

### Vaihe 1 — Pelattavuusauditti (KRIITTINEN, ei koodausta)

**Tavoite:** tuottaa konkreettinen, priorisoitu vika/kitkalista dokumenttiin
`docs/PLAYABILITY_AUDIT.md`. Tämä on koko suunnitelman tärkein vaihe — se kertoo MIKSI peli
tuntuu rikkinäiseltä vaikka testit ovat vihreät.

**Menetelmä (kaksi täydentävää polkua):**
1. **Käyttäjä pelaa oikean session** (arvokkain — hän on se joka sanoo "ei pelattava") ja
   raportoi kitkakohdat, TAI:
2. **Automatisoitu ikkunallinen sessio:** Start-Process pysyvä ikkuna → skriptattu klikkiautomaatio
   (Win32, `SetProcessDPIAware()` + topmost, ks. testing-gotchas) → I-dumpit avainhetkillä →
   screenshot-analyysi. Reprodusoituvat kitkakohdat.

Headless-skenaariot EIVÄT riitä tähän: pelituntuma, luettavuus ja UI-ergonomia näkyvät vain
oikeassa ikkunallisessa sessiossa (feedback: UI-verifiointi vaatii oikean hiiriklikkauksen +
tulos-screenshotin, ei lokia/koodikatselmointia).

**Auditin checklist (jokaiseen: toimiiko? kuinka paljon kitkaa? blokkaako ymmärryksen?):**
- **Onboarding-flow:** ymmärtääkö ensipelaaja mitä tehdä? Viekö 3-vaiheinen opaste nollasta ekaan
  louhintaan ja ekaan ostoon ilman ulkopuolista selitystä?
- **Designaatio-UX:** saako pelaaja helposti maalattua järkevän kaivuualueen? Vai syntyykö kapeita
  1-solun kuiluja (I-dump-havainto)? Onko pensseli/laatikko/solu-moodit löydettävissä ja järkevät?
- **Bottien luettavuus (vahva hypoteesi P0:ksi):** näkeekö pelaaja MIKSI botti idlaa? "Miner idlaa"
  ilman syytä on todennäköisesti suurin "tuntuu rikkinäiseltä" -tekijä. Testaa: onko botilla
  näkyvä tila/idle-syy (ei saavutettavaa designaatiota / ei kuormaa / dump täynnä)?
- **Ostoflow:** onko selvää mitä voi ostaa, paljonko maksaa, miksi kortti on harmaana (can_afford)?
  Nouseeko $/s havaittavasti oston jälkeen?
- **Jalostusketjun rakennettavuus:** saako pelaaja pystyyn furnace + dropoff + pickup -linjan niin
  että IRON_ORE→IRON tuottaa näkyvästi enemmän? Vai onko flow liian piilotettu?
- **Milestone-rytmi:** tulevatko toastit oikeaan tahtiin? Tuntuuko seuraava tavoite saavutettavalta?
- **FPS:** pysyykö 60 fps kun botteja ja louhintaa on paljon? (linkittyy D4:ään)
- **Tulovirran nopeus:** mitattu $/s ekan 3 min aikana → syöttää D1:n hintasäädön.

**DoD:** `docs/PLAYABILITY_AUDIT.md` olemassa, jokainen löydös priorisoitu (P0 = blokkaa demon /
P1 = selvä kitka / P2 = nice-to-have) ja liitetty tiedostoon/järjestelmään. Mitattu alkutulovirta
kirjattu D1:tä varten.

---

### Vaihe 2 — P0-korjaukset (auditin löydökset + tunnetut aukot)

Priorisointi = auditin P0-lista ENSIN, sitten alla olevat tunnetut aukot. Useimmat rinnakkaistettavissa
worktreissä; `pixel_world.gd` on jaettu hotspot → merge-juna.

Tunnetut aukot Vaiheeseen 2 (työkortit §7):
1. **Hinnoittelu D1** — jo Vaiheessa 0, mutta balanssin hienosäätö auditin datalla tässä.
2. **gpu_passes-throttle D4** — korjaa/poista, ikkunallinen FPS-verifiointi.
3. **COPPER/RARE_EARTH raakamyynti D3** — verifioi base-dropoff hyväksyy + premium-hinnan säätö
   niin tier 4 -hyppy näkyy $/s:ssä. (EI uusia ID:itä.)
4. **Save/load leikkaus D2** — F5/F9 irti pelaajalta.
5. **Fleet-laskuri D5** — yläpalkkiin.
6. **Auditin P0-löydökset** — todennäköisesti bottien idle-luettavuus ja/tai designaatio-ergonomia.
   Nämä lukitaan Vaiheen 1 jälkeen.

**DoD:** auditin P0-lista nollattu; `run_all.sh` vihreä; ikkunallinen sessio vahvistaa että "ei
pelattava" -tunne on poissa; 60 fps.

---

### Vaihe 3 — Julkaisukehys (rinnakkaistettava)

Kolme pääosin itsenäistä työtä, rinnakkain worktreissä.

- **R1 — Päävalikko + demo-silmukka + pause/quit.** Uusi title-scene (Aloita peli / Lopeta),
  demo_complete-ruutu → "Pelaa uudestaan (restart)" / "Jatka vapaasti" / "Lopeta", ESC → pause-valikko
  (Jatka / Alusta / Lopeta). Peli ei enää boottaa suoraan simulaatioon eikä demo_complete ole umpikuja.
- **R2 — Ääni (minimi-setti).** Uusi `audio_manager.gd` (autoload-tyylinen singleton) + proseduraalinen
  SFX-generointiskripti (Python + numpy/wave, sama proseduraali-eetos kuin `gen_ui_assets.py`): louhinta-"chunk",
  kassa-kilahdus, milestone-fanfaari, UI-klik, matala ambient-humina (looppi). Kytke olemassa oleviin
  eventteihin (mine tick, base accept_cargo, milestone-toast, nappiklik). Master-volume debug-valikkoon.
- **R3 — Export-pipeline.** `export_presets.cfg` Windows Desktopille, versionumero (`config/version`)
  project.godotiin, sovellusikoni. Buildaa .exe, testaa boottaus ikkunallisena.

**DoD:** buildattu .exe boottaa → title → peli → demo complete → pelaa uudestaan, äänet soivat,
versionumero näkyy.

---

### Vaihe 4 — Balanssi & polish

- **B1 — Balanssi-läpipeluu.** Ikkunallinen läpipeluu 15–25 min: eka botti 2–3 min, tier-hypyt
  näkyvät $/s:ssä, seuraava ostos aina ~1–3 min päässä, demo läpäistävissä. Säädä tuning-vakioita
  (hinnat, mine_rate, PRICES premiumit) kunnes käyrä tuntuu oikealta. Kirjaa balanssiraportti
  (min → $/s-käyrä) auditin viereen.
- **B2 — Siivousnitit.** debug_menu.gd:79,688 poista viittaukset poistettuihin sand_mines/launchers;
  stale kommentti bot_manager.gd:402-404 (`_crowd_factor` on käytössä); RID-vuoto exitissä
  (transfer-shaderin puskurit, pixel_world.gd:5031-alue) — vapauta.

**DoD:** balanssiraportti valmis, tavoiteajat ±%; grep ei löydä poistettuja viittauksia; ei RID-vuotoa
exitissä (Godot-vapautuslogit puhtaat).

---

## 6. Julkaisuchecklist (Vaiheen 4 lopuksi, ennen "valmis")

- [ ] `run_all.sh` 100 % vihreä (ml. korjattu `bot_buy.json` + uudet balanssi/skenaariotestit)
- [ ] Buildattu Windows .exe boottaa puhtaalla profiililla (ei editoria, ei projektikansiota)
- [ ] Title → peli → demo complete → pelaa uudestaan -silmukka toimii, ei umpikujaa
- [ ] Äänet soivat (louhinta, kassa, milestone, klik, ambient)
- [ ] Onboarding vie ensipelaajan nollasta ekaan ostoon ilman ulkopuolista ohjetta
- [ ] Ei debug-vuotoja pelaaja-UI:hin (materiaalimaalaus, aseet, launcher/drill, F5/F9 poissa/gated)
- [ ] 60 fps 1664×960 tyypillisellä lauma- ja louhintakuormalla (ikkunallinen mittaus)
- [ ] Versionumero project.godotissa + näkyvissä title-scenessä
- [ ] Auditin P0-kitkalista nollattu; balanssiraportti tallessa
- [ ] README/ohjaus-teksti: mitä pelata, näppäimet (V-designaatio, TAB-paneeli, ESC-valikko)

---

## 7. Työkortit (delegoitavissa agenteille)

Jokainen kortti on itsenäinen briefi: omistetut tiedostot + DoD + testit + verifiointi (headless
vs ikkunallinen) + riippuvuudet. `pixel_world.gd` on jaettu hotspot → sitä editoivat kortit ajetaan
worktreissä ja integraattori mergeää järjestyksessä.

### Vaihe 0

**T0.1 — Baseline-commit** *(serial, ENSIN)*
Committaa koko working tree. *Omistaa:* koko repo. *DoD:* `git status` puhdas, `run_all.sh` vihreä.
*Verifiointi:* headless (`run_all.sh`). *Riippuu:* — .

**T0.2 — bot_buy-hinnoittelu D1** *(serial, T0.1 jälkeen)*
`next_bot_price()` → `300 × 1.5^n` (bot_manager.gd:199-200); `bot_buy.json` odotusarvot samaan.
*Omistaa:* bot_manager.gd, tests/scenarios/bot_buy.json, tests/unit/test_bot_manager.gd.
*DoD:* `bot_buy.json` PASS, unit vihreä. *Verifiointi:* headless. *Riippuu:* T0.1.

### Vaihe 1

**T1.1 — Pelattavuusauditti** *(serial, ei koodia)*
Ikkunallinen sessio (käyttäjä TAI klikkiautomaatio) → `docs/PLAYABILITY_AUDIT.md` §Vaihe 1 checklistillä.
*Omistaa:* docs/PLAYABILITY_AUDIT.md (uusi). *DoD:* priorisoitu kitkalista + mitattu alkutulovirta.
*Verifiointi:* IKKUNALLINEN (pakko). *Riippuu:* T0.2.

### Vaihe 2 (rinnakkaistettavissa; pixel_world.gd-kortit merge-junassa)

**T2.1 — Auditin P0-korjaukset** *(riippuu T1.1 löydöksistä)*
Lukitaan Vaiheen 1 jälkeen. Vahva hypoteesi: bottien idle-syyn näkyvyys (ui.gd + bottirender) ja/tai
designaatio-ergonomia. *Omistaa:* auditin osoittamat tiedostot. *DoD:* P0-kitka poissa, vahvistettu
ikkunallisesti. *Verifiointi:* ikkunallinen. *Riippuu:* T1.1.

**T2.2 — gpu_passes-throttle D4** *(rinnakkain, pixel_world.gd)*
Korjaa restore-järjestys tai poista adaptiivinen throttle (pixel_world.gd:766-769 vs 2272-2275).
*Omistaa:* pixel_world.gd (throttle-osa). *DoD:* passimäärä toimii suunnitellusti, 60 fps.
*Verifiointi:* IKKUNALLINEN FPS (ei headlessissä). *Riippuu:* T0.1. *Merge-juna:* pixel_world.gd.

**T2.3 — COPPER/RARE_EARTH raakamyynti D3** *(rinnakkain)*
Verifioi base-dropoff hyväksyy COPPER/RARE_EARTH; säädä premium-hinnat (money_exit.gd:36-37) niin
tier 4 -hyppy näkyy $/s:ssä. EI uusia ID:itä. *Omistaa:* money_exit.gd. *DoD:* skenaario jossa
RARE_EARTH-suoni louhitaan → myydään → $/s hyppää; `tests/unit/test_money_exit.gd` kattaa hinnat.
*Verifiointi:* headless-skenaario + balanssitarkistus. *Riippuu:* T0.1.

**T2.4 — Save/load leikkaus D2** *(rinnakkain, pieni)*
Irrota F5/F9 pelaajalta (pixel_world.gd:2089-2090) — debug-lipun taakse tai pois. *Omistaa:*
pixel_world.gd (input-osa). *DoD:* F5/F9 ei riko pelitilaa pelaajakäytössä; ei viittausta save-nappeihin
pelaaja-UI:ssa. *Verifiointi:* ikkunallinen (paina F5/F9, tila ei rikkoudu). *Riippuu:* T0.1.
*Merge-juna:* pixel_world.gd.

**T2.5 — Fleet-laskuri yläpalkkiin D5** *(rinnakkain)*
Nosta Miner X/Y, Hauler X/Y F3-debugista yläpalkkiin (`get_fleet_stats()`). *Omistaa:* ui.gd.
*DoD:* laskuri näkyy pelaaja-UI:ssa ilman F3:a. *Verifiointi:* ikkunallinen screenshot. *Riippuu:* T0.1.

### Vaihe 3 (rinnakkaistettavissa)

**T3.1 — Päävalikko + demo-silmukka + pause D2/R1** *(pixel_world.gd wiring)*
Title-scene (Aloita/Lopeta), demo_complete → Pelaa uudestaan/Vapaa peli/Lopeta, ESC → pause.
*Omistaa:* uusi scene(t) + pixel_world.gd (scene-flow wiring), ui.gd (valikko-overlayt). *DoD:*
title → peli → demo complete → restart -silmukka toimii, ei umpikujaa. *Verifiointi:* ikkunallinen
flow-testi. *Riippuu:* T0.1. *Merge-juna:* pixel_world.gd.

**T3.2 — Ääni R2** *(rinnakkain)*
`audio_manager.gd` + proseduraali-SFX-skripti (Python numpy/wave): louhinta, kassa, milestone, klik,
ambient. Kytke eventteihin. *Omistaa:* uusi audio_manager.gd, assets/audio/ (uusi), gen-skripti.
Kytkentäpisteet: bot_manager (mine tick), money_exit (accept_cargo), ui.gd (toast, nappiklik).
*DoD:* äänet soivat oikeissa hetkissä, master-volume debug-valikossa. *Verifiointi:* ikkunallinen
(kuuntelu). *Riippuu:* T0.1. Voi delegoida: artist ei tee ääntä → programmer + gen-skripti.

**T3.3 — Export-pipeline R3** *(rinnakkain)*
`export_presets.cfg` Windows, `config/version` project.godotiin, ikoni. *Omistaa:* export_presets.cfg
(uusi), project.godot, ikoni-asset. *DoD:* .exe buildaa ja boottaa ikkunallisena puhtaalla profiililla.
*Verifiointi:* IKKUNALLINEN build-boot. *Riippuu:* T0.1.

### Vaihe 4

**T4.1 — Balanssi-läpipeluu B1** *(riippuu Vaihe 2+3)*
Ikkunallinen 15–25 min läpipeluu, säädä tuning-vakiot, kirjaa $/s-käyrä. *Omistaa:* tuning-vakiot
(bot_manager.gd yläosa, money_exit.gd PRICES), balanssiraportti. *DoD:* tavoiteajat §3 kohta 2 ±%.
*Verifiointi:* IKKUNALLINEN läpipeluu. *Riippuu:* T2.*, T3.1.

**T4.2 — Siivousnitit B2** *(rinnakkain, pieni)*
debug_menu.gd:79,688 poista sand_mines/launchers-viittaukset; bot_manager.gd:402-404 stale kommentti;
RID-vuoto exitissä (pixel_world.gd:5031-alue). *Omistaa:* debug_menu.gd, bot_manager.gd (kommentti),
pixel_world.gd (exit). *DoD:* grep puhdas, ei RID-vuotoa. *Verifiointi:* grep + Godot-vapautuslogit.
*Riippuu:* T0.1.

**Merge-junan järjestys pixel_world.gd:lle:** T2.2 → T2.4 → T3.1 → T4.2 (integraattori ajaa testit
per merge). Muut kortit koskettavat eri tiedostoja → vapaasti rinnakkain.

---

## 8. Riippuvuudet ja rinnakkaisuus (yhteenveto)

```
Vaihe 0:  T0.1 ──► T0.2                          (serial, pakko ensin)
Vaihe 1:  T1.1                                    (serial, ikkunallinen, tuottaa P0-listan)
Vaihe 2:  T2.1(audit) T2.2 T2.3 T2.4 T2.5         (rinnakkain; pixel_world-kortit merge-junassa)
Vaihe 3:  T3.1 T3.2 T3.3                          (rinnakkain)
Vaihe 4:  T4.1(riippuu 2+3) T4.2                  (T4.2 rinnakkain, T4.1 lopuksi)
```

**Kriittinen polku:** T0.1 → T0.2 → T1.1(auditti) → T2.1(P0) → T4.1(balanssi) → julkaisuchecklist.
T2.2–2.5, T3.* ja T4.2 limittyvät sen rinnalle.

---

## 9. Riskit

| Riski | Mitigaatio |
|---|---|
| **Auditti paljastaa ison UX-juurisyyn** (esim. designaatio tuottaa vain kapeita kuiluja, botit idlaa rakenteellisesti) | Siksi auditti on ENNEN koodia. Varaa Vaihe 2:een tilaa: P0-lista voi olla isompi kuin tunnetut gapit. Älä lukitse aikataulua ennen T1.1:tä. |
| **Balanssi-iteraatio on aikasyöppö** (D1 hinta + tulovirta + tier-hypyt) | Invariantti on tavoite (2–3 min eka botti), ei vakio. Mittaa auditissa → säädä dataan, älä arvaa. Tuning-vakiot yhteen paikkaan. |
| **GPU/FPS-verifiointi on manuaalista** (D4, ei headlessissä) | Merkitty ikkunalliseksi työkorteissa. Varaa ikkunallinen mittaussessio T2.2:lle erikseen. |
| **pixel_world.gd merge-konfliktit** (T2.2, T2.4, T3.1, T4.2) | Merge-juna §7; vain nämä kortit editoivat sitä; integraattori ajaa testit per merge. |
| **Ääni-assetit puuttuvat** (artist ei tee ääntä) | Proseduraalinen gen-skripti (numpy/wave) — sama eetos kuin UI-assetit; ei lisenssikysymyksiä, reprodusoituva repossa. |
| **Export-templatet puuttuvat koneelta** | Tarkista T3.3:n alussa; Godot 4.6.1 (Desktop/Godot/) export-templatet asennettava ennen buildia. |
| **Scope-ryömintä** (uudet materiaalit, save/load, uudet featuret) | D2/D3 leikkaavat suurimmat houkutukset. DoD §3 listaa scopen ULKOPUOLISET. Auditin P2-löydökset → demon jälkeen. |
