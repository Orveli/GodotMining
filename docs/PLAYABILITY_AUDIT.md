# Pelattavuusauditti — GodotMining (Bot Mining -demo)

**Päiväys:** 2026-07-17
**Tekijä:** QA/debugger-agentti (T1.1)
**Metodi:** Ikkunallinen pelisessio (Win32/DPI-syöteautomaatio + I-debugdumpit) puhtaalta
cold-bootilta, headless-$/s-aikasarja (ScenarioRunner, cpu_ca, kiinteä 1/60 aika-askel), sekä
kohdennettu kooditason analyysi. Todisteet: `tests/output/audit/` (PNG + JSON), headless-loki
`scratchpad/hl_income.log`, mittausskenaario `tests/scenarios/_audit_income.json`.
**Lähtökohta:** Automaattitestit vihreitä, mutta käyttäjä sanoo "peli ei ole pelattava" — miksi?

> **Havaintojen luokittelu:** jokainen löydös on merkitty **[LIVE]** (todettu ajossa),
> **[KOODI]** (varmennettu koodista, ei live-toistettu) tai **[PLAYTEST]** (käyttäjän oma
> spontaani pelisessio, ks. §5).

---

## 1. Tiivistelmä — tärkeimmät löydökset

1. **P0 [LIVE] — "Kuollut kaivos" ilman palautetta.** Kun miner ei voi sitoutua designaatioon
   (haudattu/saavuttamaton alue, ei paljasta frontier-solua, ei reittiä), botti jää IDLEen basen
   viereen EIKÄ peli kerro mitään. Puhtaalla cold-bootilla ($0, 2 bottia) maalasin designaation
   pensselillä; `first_desig`-toast laukesi ("Ensimmäinen louhinta-alue merkattu!"), mutta 57 s ajan
   money pysyi $0:ssa ja molemmat botit olivat IDLE. **Tämä on juuri se kokemus jota etsimme:**
   uusi pelaaja maalaa, mitään ei tapahdu, ei tiedä miksi → "peli ei toimi". Todennäköisin
   ykkössyy käyttäjän tuntemukseen. *(Todiste: `audit_clean_03..05_*.json`, `audit_clean_04_mining.png`.)*

2. **P0 [KOODI] — Jalostusketju ei reitity boteilla ilman piilotettua käsisäätöä.** Basen
   pudotusvyöhykkeen `filter_mask=0` (hyväksyy kaiken), joten `Logistics.choose_dump` reitittää
   sekakuorman AINA baseen (hyväksyy suurimman osan) ja malmi myydään raakana — furnace ei koskaan
   saa syötettä. Ketju vaatii että pelaaja avaa base-popoverin ja poistaa malmit hyväksytyistä.
   Tälle ei ole opastetta → jalostus on käytännössä löytämätön ilman dokumentaatiota.

3. **P0/P1 [LIVE+KOODI] — Bottien luettavuus puuttuu.** Ainoa tilaindikaattori on IDLE-bottien
   himmennys (alpha 0.35) + kuormapalkki. Ei mitään joka kertoo MIKSI botti seisoo. Ilman
   F3-overlaya pelaaja ei voi diagnosoida seisovaa laumaa. (Käyttäjän session loppu — 11 bottia,
   1 miner / 10 hauleria, income $0 — on tästä oire, joskin voi olla myös vain "pelaaja lopetti".)

4. **P1 [LIVE] — Aggressiivinen fog of war + sokea syvyysdesignaatio.** Fog on päällä oletuksena
   (`pixel_world.gd:414`, ei debug-lipun takana, explored-muistilla). Pinta valaistu, syvyys lähes
   musta ennen tutkimista. Materiaaleja/suonia ei näe ennen kuin botit ovat kaivaneet sinne →
   pelaaja designoi syvyyteen sokkona, mikä ruokkii P0-1:n virhedesignaatiota.

5. **P1 [KOODI] — Osto ilman varaa on hiljainen no-op.** Botti-tray himmentää kortin + värjää
   hinnan punaiseksi (hyvä), mutta napin klikkaus (`_buy_bot`) palaa hiljaa ilman toastia.
   Rakennukset/vyöhykkeet näyttävät "Ei varaa ..."-toastin — epäjohdonmukaista.

**Ydinviesti:** Talousydinluuppi TOIMII — sekä headless-mittauksessa (2 bottia tuottavat rahaa
pintalouhinnasta, ks. §3) että käyttäjän spontaanissa playtestissä ($6332, ~8 bottia, hihnoja,
m1000-milestone; §5). Pelattavuuden esteet eivät ole "moottori rikki" vaan **luettavuus ja
palaute**: peli ei kerro mitä tapahtuu, miksi botti seisoo, tai miten jalostus kytketään. Nämä
korjattavissa UI/palaute-tasolla ilman core-simulaation muutoksia.

---

## 2. Löydökset priorisoituna

### P0 — Blokkaa demon

**P0-1 [LIVE]. Saavuttamaton designaatio → miner IDLE ilman palautetta**
- **Havaittu:** Puhtaassa cold-boot-instanssissa ($0, 2 bottia) maalasin designaation maan alle.
  `first_desig` laukesi, mutta 57 s ajan `miners_active=0`, `money=0`, molemmat botit IDLE basella.
  Mekanismi (koodi): `_scan_designations` merkitsee D_QUEUED-solun D_BLOCKEDiksi jos sillä ei ole
  avointa naapuria; täysin haudattu alue jää BLOCKEDiksi ikuisesti (mikään ei avaa viereistä
  solua) → frontier tyhjä → `_assign_miner` palaa heti → botti IDLE. **Vahvistus vastakohdalla:**
  headless-mittauksen PINTAAN kytketty `designate_rect` sai minerin heti töihin ja rahan nousuun
  (§3) — ero on pelkästään saavutettavuus, josta pelaaja ei saa mitään signaalia.
- **Missä:** `bot_manager.gd:_scan_designations`/`_assign_miner`; palautejärjestelmä puuttuu.
- **Todiste:** `audit_clean_03_designated.json`, `audit_clean_04_mining.png`, `audit_clean_05_after.json`.
- **Korjaus (1 rivi):** Idle-minerille diegeettinen syy-merkki ("ei reittiä / kaiva pinnalta") +
  varoitus kun designaatiossa on 0 frontier-solua (kaikki BLOCKED).

**P0-2 [KOODI]. Jalostusketju ei reitity boteilla ilman piilotettua base-filtterisäätöä**
- **Havaittu:** Base-pudotus hyväksyy kaiken (`filter_mask=0`). `choose_dump` valitsee dumpin joka
  "hyväksyy suurimman osan kuormasta" → sekakuorma menee aina baseen, malmi myydään raakana;
  furnacen input-dump (maski = reseptin malmit) häviää aina baselle. Aktivointi vaatii että
  pelaaja klikkaa basea → popover → poistaa malmit "Hyväksytyt materiaalit" -riviltä. Ei opastetta.
- **Missä:** `pixel_world.gd:1537` (`add_base_dropoff(...,0)`), `logistics.gd:choose_dump`,
  `ui.gd:_open_zone_popover`.
- **Korjaus (1 rivi):** Kun furnace/crusher rakennetaan, poista sen reseptin input-malmit
  automaattisesti basen hyväksytyistä (tai onboarding-vihje "Aseta base hylkäämään malmi").

**P0-3 [LIVE]. Botit seisovat kun työ loppuu — ei kehotusta designoida lisää**
- **Havaittu:** Käyttäjän session loppu: 11 bottia, income $0, money jäätynyt — työ oli loppunut
  (designaatiot kulutettu) mutta mikään ei kehota designoimaan lisää. Sama juurisyy kuin P0-1.
  *(Varaus: tila voi johtua myös siitä että pelaaja yksinkertaisesti lopetti — mutta puuttuva
  "designoi lisää" -heräte on joka tapauksessa aito.)*
- **Todiste:** `audit_probeA.json`/`audit_probeB.json` (income 0.0, muuttumaton 18 s, 11 bottia).
- **Korjaus (1 rivi):** Kun kaikki botit IDLE + income≈0 X s, toast "Merkkaa lisää aluetta (V)".

### P1 — Selvä kitka

- **P1-1 [LIVE]. Fog of war peittää missä on kaivamisen arvoista** → sokea syvyysdesignaatio.
  Oletuspäällä. *`pixel_world.gd:414-417`; `audit_clean_04_mining.png`.* *Korjaus:* himmennä
  tutkimaton harmaaksi (ei mustaksi) tai näytä suonten ääriviivat himmeästi.
- **P1-2 [KOODI]. Bottioston "ei varaa" = hiljainen no-op.** Rakennukset toastaavat, botit eivät.
  *`ui.gd:_buy_bot`.* *Korjaus:* sama "Ei varaa ($%d)"-toast bottiostoon.
- **P1-3 [KOODI]. Onboarding ei kerro MISTÄ ostetaan eikä erotu.** 3 vaihetta, teksti pieni ja
  himmeä (COL_BORDER_DIM), vaihe 3 ("Osta kolmas botti kun $300") ei kerro mikä ikoni avaa
  bottikaupan. *`ui.gd:ONBOARDING_TEXTS`.* *Korjaus:* korosta ostoikoni vaiheessa 3 + nosta kontrastia.
- **P1-4 [PLAYTEST]. Fleet-kokoonpanolle ei ohjausta.** Käyttäjä päätyi 10 haul / 1 miner -jakoon
  (income 0). Peli sallii minkä tahansa roolijaon ilman vihjettä että minereitä tarvitaan
  haulereita ruokkimaan. *Korjaus:* vihje kun haulereita ≫ minereitä ja income laskee.

### P2 — Nice-to-have / hygienia

- **P2-1 [KOODI]. `income_per_s` (liukuva 10 s ka.) putoaa 0:aan heti kun työ hiljenee** → näyttää
  "peli pysähtyi" vaikka rahaa on. Harkitse hitaampaa vaimennusta / "viimeksi ansaittu".
- **P2-2 [KOODI, ei verifioitu]. Game-logic-piikit (`gl`) ~133 ms boot-lokissa** — attribuointia ei
  voitu tehdä puhtaasti (käyttäjän rakennus/CCL-kuorma sekaisin). Profiloi puhtaassa ympäristössä.
- **P2-3 [LIVE]. Designaatiotyökalun moodit** (pensseli/laatikko/solu) ovat pieni ikonirivi;
  toimivat + tooltipit ok, mutta moodien ero + "Koko"-liuku eivät selitä itseään.

---

## 3. $/s-mittaus (headless, deterministinen)

**Menetelmä:** `tests/scenarios/_audit_income.json` — 2 aloitusbottia (1 miner/1 hauler),
`designate_rect` iso pintadesignaatio basen vasemmalla (238 aktiivista solua), money-näyte 15 s
välein 5 min. Headless cpu_ca, kiinteä 1/60 aika-askel → deterministinen, ei riipu fps:stä eikä
törmää käyttäjän ikkunaan. **Varaus:** headless käyttää CPU-CA:ta (ei GPU-Margolusta); bottilogiikka
on identtinen mutta irtomateriaalin valuminen voi erota hieman GPU-pelistä → luvut ovat suuntaa
antava alaraja, eivät tarkka GPU-arvo.

**Tulos (täysi 5 min ajo, 22 näytettä, virheitä=0):**

| Aika | money | | Aika | money |
|---|---|---|---|---|
| 0:30 | $0 | | 3:00 | $560 |
| 1:00 | $80 | | 3:30 | $640 |
| 1:30 | $200 | | 4:00 | $760 |
| **1:57** | **~$300** ← eka lisäbotti | | 4:30 | $840 |
| 2:00 | $320 | | 5:00 | $960 |
| 2:30 | $440 | | | |

**Johtopäätökset:**
- Ensimmäinen tulo t≈45 s (ensimmäinen hauler-purku baseen).
- **$300 (ensimmäinen lisäbotti) ylittyy ~1 min 57 s kohdalla → GDD-tavoite "eka lisäbotti 2–3 min"
  TÄYTTYY** (hieman etuajassa, hyväksyttävää).
- **Vakaa tulovirta ~3,6 $/s kahdella botilla** (t=45 s→300 s: $920 / 255 s). Designaatio ei
  ehtynyt (238→195 solua 5 min) → mittaus on steady-state, ei "työ loppui".
- **Balanssihavainto:** `dig_sites` kasvoi 33:een = 33 keräämätöntä kasaa. Yksi hauler EI ehdi
  kantaa minerin tuotosta — miner tuottaa nopeammin kuin 1 hauler kuljettaa → **hauler on
  pullonkaula**, ja toinen hauler (ei toinen miner) nostaisi $/s:ää eniten early-gamessa. Peli ei
  ohjaa tähän (liittyy P1-4:ään). *(Todiste: `hl_income.log`, `hl_income_end.png`.)*

---

## 4. Metodihuomio — "kontaminaatio" oli käyttäjän oma pelisessio

Auditin alkuvaiheessa I-dumppini näyttivät mahdottomia tilahyppyjä ($113 → $6332 → $8214, botteja
ja hihnoja ilmestyi). Alkuperäinen tulkintani (rinnakkainen agentti-injektio) oli **väärä**:
**käyttäjä pelasi peliä samalla koneella samaan aikaan.** Instrumentointi ei ollut rikki eikä
kukaan injektoinut — ikkunassa oli oikea ihminen, jonka näppäilyt valuivat peliin kun toin ikkunan
etualalle. Rakenteellinen ristiriita (et voi lähettää syötettä olematta etualalla) tekee
ikkunallisesta mittauksesta epäluotettavan niin kauan kuin ihminen käyttää konetta → siirryin
headless-mittaukseen (§3), joka ei tarvitse ikkunaa. Ikkunalliset puhtaat havainnot (cold boot,
P0-1) tehtiin hetkinä jolloin käyttäjä ei koskenut testi-instanssiini.

---

## 5. Spontaani käyttäjäplaytest (bonusdata)

Auditin aikana käyttäjä pelasi nykybuildia spontaanisti ja eteni: **~$6332, ~8 bottia, rakensi
liukuhihnoja, m1000-milestone laukesi** (dumpit `audit_02_noinput_a.json`, `audit_probeA/B.json`).
Tämä todistaa nykybuildista:
- **Ostoflow toimii oikealla pelaajalla** — botteja ostettiin useita, hinta nousi.
- **Hihnarakennus löytyy UI:sta** ilman ohjeita — käyttäjä rakensi hihnoja itse.
- **Talous kasvaa** selvästi ($6000+) ja milestone-kaari etenee ($1000-toast laukesi.)

**Varaus (ei ylitulkita positiiviseksi):** emme tiedä kohtasiko käyttäjä kitkaa matkalla, kuinka
kauan eteneminen kesti, tai ymmärsikö hän jalostusketjua. Session loppu (11 bottia, 1 miner/10
hauleria, income 0) on epäoptimaalinen fleet, mutta voi johtua myös pelin lopettamisesta. Havainto
osoittaa että **ydinmekaniikat ovat pelattavissa**, mutta ei kumoa §2:n luettavuus/palaute-P0:ita.

---

## 6. Mitä EI live-verifioitu ja miksi

- **Täysi ohjattu läpipeluu** (onboarding → eka osto → jalostus → milestone-kaari → demo complete):
  ikkunallinen ajo epäluotettava käyttäjän samanaikaisen pelaamisen takia (§4). Cold boot ($0 /
  2 bottia / IDLE / onboarding step 0) + P0-1 ehdittiin todeta puhtaina.
- **Jalostusketjun live-reititys (P0-2):** varmennettu vain koodista.
- **Onboarding-flow loppuun (3 vaihetta → eka osto):** vaiheet ja logiikka varmennettu koodista;
  live-eteneminen ei toistettu.
- **Osto-"dopamiini" ($/s-hyppy oston hetkellä):** käyttäjä osti botteja, mutta ei kontrolloidusti.

**Instrumentointi valmis jatkoon:** `scratchpad/winput.ps1` (DPI-aware Win32), `dump.ps1`,
`playthrough.ps1`, headless `tests/scenarios/_audit_income.json`. Win32/DPI-resepti + PID-kohdistus
toimivat; ainoa este oli ihmiskäyttäjä samalla koneella.

---

## 7. Toimenpide-ehdotus (prioriteetti)

1. **P0-1 + P0-3 (sama korjausperhe):** idle-botin syy-indikaattori + "designoi lisää" -heräte.
   Suurin pelattavuusvaikutus pienimmällä työllä — pelkkä UI/palaute.
2. **P0-2:** auto-poista malmi base-filtteristä kun jalostuskone rakennetaan (tai vihje).
3. **P1-2, P1-3:** bottioston "Ei varaa"-toast + onboardingin ostoikonin korostus.
4. **P1-1:** pehmennä fog tutkimattomalle (harmaa ei musta) tai suonivihjeet.
5. **Balanssi:** §3 vahvistaa alustavasti "$300 bottiin 2–3 min" — lukitse kun täysi käyrä valmis.
