# UI-REDESIGN — "Bot Mining" käyttöliittymän täysremontti

**Versio:** 0.1 (suunnitelma, EI toteutusta)
**Kohde:** Godot 4.2, ikkuna 1664×960, kaikki UI ohjelmallista GDScriptiä (`scripts/ui.gd`)
**Lähtökohta (käyttäjä):** *"That's not a game UI. It looks like a UI for the ISS."* → halutaan
**pelimäinen, mahdollisimman minimalistinen** UI. Art-visio: Industrial Gothic Underground
(syvä sinimusta, lämmin harmaa kivi, tuli ainoa kirkas elementti).

---

## 1. PERIAATTEET — mitä hyvä pelin UI tälle genrelle on

Verrokit ja mitä ne tekevät oikein:

| Peli | Ydinoppi tälle pelille |
|---|---|
| **Factorio** | HUD lähes tyhjä. Koneen GUI avautuu **klikkaamalla konetta maailmassa** (kontekstuaalinen, ei aina auki). Alhaalla ikonipohjainen hotbar. |
| **Oxygen Not Included / DF** | Kaivuu = **maalataan maailmaan** (jo meillä designaatiogridinä). Rakentaminen = alapalkin **ikonikategoriat** jotka laajenevat vain tarvittaessa. |
| **Dome Keeper** | Äärimmäinen minimalismi. Upgradet **diegeettisesti** asemalla, ei aina-näkyvässä paneelissa. Ruutu = peli, ei dashboard. |
| **Terraria / Noita** | HUD = vain elintärkeä (raha/HP) + **ikoni-hotbar**. Loput näppäimen takana. Ei tekstiä missä ikoni riittää. |

**Ydinperiaatteet, jotka johdan näistä:**
1. **HUD = vain pisteet.** Aina näkyvissä vain raha (pelin "score"). Kaikki muu on napin/klikkauksen takana.
2. **Diegeettinen tieto.** Botin tila näkyy botissa (väri + kuormapalkki), designaatiot maailman overlayna — EI listoina ja prosentteina paneelissa.
3. **Kontekstuaaliset paneelit.** Klikkaa base → bottipaneeli. Klikkaa uuni → reseptipaneeli. Ei full-width TabContaineria joka on aina auki.
4. **Ikoni ennen tekstiä.** Napit ovat pikseli-ikoneita + tooltip, eivät tekstikortteja kuvauksineen.
5. **Pikselifontti + pikseligrafiikka** joka istuu nearest-filter-pikselirenderöintiin. Lämmin amber-aksentti mustan kiven päällä — EI tech-sininen border.
6. **Hotkeyt.** Jokainen työkalu näppäimellä; ikonipalkki on visuaalinen muistutus, ei ainoa reitti.
7. **Debug pois oletuksesta.** FPS, skanneriprosentit → F3-debugtogglen taakse.

---

## 2. GAP-ANALYYSI — miksi nykyinen tuntuu "ISS-paneelilta"

| Nykyinen elementti (`ui.gd`) | Rikkoo periaatetta | Miksi tuntuu dashboardilta |
|---|---|---|
| Full-width yläpalkki + **sininen border-bottom** (`0.25,0.55,0.85`) | 1, 5 | Web-navbar / tech-HUD väri. |
| Alareunan **270px TabContainer**, 3 välilehteä aina auki | 1, 3 | Sovellusikkunan tab-dashboard. Vie 28 % ruudusta lepotilassa. |
| **Checkbox-ruudukot** materiaalifiltereille (`_build_filter_grid`) | 2, 4 | Lomake/asetusnäkymä, ei peli. |
| **Prosenttilista** ympäristöstä (materiaaliskanneri, oikea-ylä) | 1, 2 | Telemetria-readout, "avaruusaseman mittaristo". |
| **FPS-luku** yläpalkissa aina | 7 | Debug-luonteista, ei kuulu pelinäkymään. |
| **Tekstikortit** hintoineen + kuvauksineen (`_add_afford_card`) | 4 | Verkkokaupan tuotekortti, ei game-toolbar. |
| **Godotin default-fontti** kaikkialla | 5 | Ei mitään pelin visuaalista identiteettiä. |
| Kaikki `StyleBoxFlat` + `add_theme_*_override` hajautettuna | 5 | Ei yhtenäistä teemaa → jokainen paneeli hieman eri → sekava. |

Yhteenveto: näkymä on **täynnä aina-näkyvää tietoa** (tab-paneeli + skanneri + FPS + laskurit)
**tech-sinisellä** ja **järjestelmäfontilla** — juuri se yhdistelmä joka lukee "ohjauspaneeli", ei "peli".

---

## 3. UUSI UI-KONSEPTI

### 3.1 Oletusnäkymä (mahdollisimman vähän — lähes koko ruutu on peliä)

```
┌──────────────────────────────────────────────────────────────────────┐
│ ◈ $1240        ← raha, iso amber pikselifontti, kolikkoikoni          │
│   +$4/s        ← pieni, himmeä (piilota jos 0)                        │
│                                                                        │
│                                                                        │
│                      [ P E L I M A A I L M A ]                          │
│              designaatiot + botit piirretään tänne                      │
│              (botti = värillinen drone + kuormapalkki)                  │
│                                                                        │
│                                                                        │
│                                                                        │
│              ⛏         🔨        ⬡         ⌫                          │
│           ┌─────┬─────┬─────┬─────┐                                     │
│           │Louhi│Rakn.│Botit│Pyyhi│  ← kompakti ikoni-actionbar,       │
│           └─────┴─────┴─────┴─────┘     ankkuroitu alakeskelle          │
└──────────────────────────────────────────────────────────────────────┘
```

Aina näkyvissä VAIN: (1) raha vasen-ylä, (2) ~4 ikonin action bar alakeskellä. Ei muuta.
Bottilaskuri, FPS, skanneri, filtterit, ostokortit → **poissa** oletusnäkymästä.

### 3.2 Työkalut ja trayt (napin/hotkeyn takana)

- **⛏ Louhi [V]** — aktivoi designaatiomaalaus. Valittuna näkyy inline pikkupainikkeet:
  `[solu] [laatikko] [pensseli]` + pieni kokorulla. (Nykyinen `_desig_tool_mode` uusiokäytetään.)
- **🔨 Rakenna [B]** — avaa **build-trayn**: vaakarivi rakennusikoneja bar:in yläpuolelle
  (Uuni, Crusher, Hihna, Pickup, Dump). Klikkaa ikoni → sijoitustila (nyk. `build_mode`).
  Kuten Factorion/ONI:n rakennuspalkki — auki vain kun rakennat.
- **⬡ Botit [T]** — avaa **kompaktin bottipaneelin** (ei full-width): Osta Miner / Osta Hauler
  (ikoni + hinta), lauman määrä + Miner/Hauler-jakosäädin `[-] 2 [+]`, upgrade-lista ikoneina.
- **⌫ Pyyhi** — poista designaatio/rakennus (= oikea hiiri, mutta myös ikonina löydettävissä).

### 3.3 Diegeettiset interaktiot (klikkaa maailmaa, älä valikkoa)

- **Klikkaa base** → sama bottipaneeli avautuu (base = bottien koti). Paneeli ilmestyy basen viereen.
- **Klikkaa uuni / crusher** → sen oma pikkupaneeli: resepti (ikoni→ikoni) + input-filtteri. Näkyy koneen vieressä.
- **Klikkaa dump/pickup-vyöhyke** → **materiaali-filtteri popoverina ikoneilla**: rivi materiaali-ikoneja,
  klikkaus togglaa (himmeä = ei hyväksytä). Korvaa checkbox-ruudukon kokonaan. Materiaali-ikonit
  voivat käyttää olemassa olevia materiaalivärejä (`MAT_COLORS`) pikselinapin taustana.
- **Botin tila botissa:** Miner vs Hauler eri väri/silhuetti, kuorman täyttöaste pienenä palkkina
  botin alla, idle = himmeä. → poistaa tarpeen "Miner 2/3 aktiivista" -tekstiltä yläpalkista.

### 3.4 Debug (F3-toggle, oletuksena piilossa)

FPS, materiaaliskannerin prosentit, reittiviivat, navigaatiogridi. Nämä ovat kehittäjän
työkaluja — ei pelaajan HUD:ia. GDD §7.3:n skanneri säilyy koodissa, mutta togglen takana.

### 3.5 Visuaalinen kieli

- **Pikselifontti** (bittikartta) joka kohdistuu pikseliruudukkoon — ei anti-aliasoitua järjestelmäfonttia.
- **Paletti:** paneelit ~`#141414`–`#1e1a16` (musta kivi), border/aksentti **lämmin amber** `#d98a3a`
  (tuli = ainoa kirkas). Raha kulta/amber. EI sinistä (`0.25,0.55,0.85`) missään.
- **9-slice-paneelikehys** (pikseloitu kivireunus) StyleBoxFlat-täyttöjen sijaan → tuntuu grafiikalta.
- **Napit = ikonit + hover/press-tila**, tooltip tekstinä. Minimoi tekstin määrä.

---

## 4. TOTEUTUSSUUNNITELMA (vaiheittain, impact/effort-järjestyksessä)

Jokainen vaihe on itsenäisesti pelattava ja testattava. Kaikki backend-kutsut (`bot_manager`,
`logistics`, `build_mode`) säilyvät — remontti koskee **esitystapaa ja layoutia**, ei pelilogiikkaa.

### Vaihe 1 — Yhteinen Theme-resurssi + paletti + pikselifontti  ⟶ suurin loikka, pieni vaiva
**Tyyppi:** pääosin KOODI + yksi fonttiasset (artist tai valmis .ttf).
- Luo `theme/ui_theme.tres` (yksi Theme): fontti, fonttikoot, StyleBox `Panel`/`Button`/`Label`.
- Vaihda `ui.gd`:n hajautetut `add_theme_*_override`-kutsut viittaamaan teemaan (juuri-`theme`).
- Sininen border → lämmin amber; default-fontti → pikselifontti.
- **Artist:** pikselifontti (bittikartta-fontti .ttf/.fnt) + palettivahvistus. Voi aloittaa ilmaisella
  pikselifontilla, artist hienosäätää.
- **Testattava:** peli näyttää heti "peliltä" ilman layout-muutoksia.

### Vaihe 2 — Minimalisoi HUD + piilota debug  ⟶ toteuttaa "simplest possible" suoraan
**Tyyppi:** puhdas KOODI (näkyvyys + layout).
- Poista aina-näkyvä 270px TabContainer oletuksesta (siirtyy Vaiheen 3 trayksi).
- Poista skanneripaneeli + FPS + bottilaskuri oletusnäkymästä → F3-debugtoggle.
- Jäljelle HUD: raha vasen-ylä + kompakti ikoni-actionbar alakeskelle (aluksi vielä tekstinapit).
- **Testattava:** näkymä on lähes tyhjä; vain raha + toolbar. "ISS-tuntu" katoaa.

### Vaihe 3 — Ikoni-actionbar + build/bot-trayt  ⟶ tekee toolbarista pelimäisen
**Tyyppi:** KOODI + ikoniassetit (artist).
- Korvaa tekstinapit pikseli-ikoneilla + tooltipeilla.
- 🔨 → build-tray (rakennusikonirivi), ⬡ → kompakti bottipaneeli (ei full-width).
- **Artist:** työkalu- ja rakennusikonit (⛏🔨⬡⌫ + uuni/crusher/hihna/pickup/dump), 24×24 tai 16×16 px.
- **Testattava:** kaikki ostot/rakennukset toimivat ikonipalkin kautta, backend ennallaan.

### Vaihe 4 — Diegeettiset paneelit (klikkaa maailmaa) + botti-status  ⟶ poistaa loput dashboardista
**Tyyppi:** KOODI + pieni määrä ikoneita.
- Klikkaa base/kone/vyöhyke → kontekstuaalinen paneeli sen viereen.
- Vaihda checkbox-filtterit **materiaali-ikoni-toggleiksi** (popover).
- Botti-status botin päälle (rooliväri + kuormapalkki + idle-himmennys) → poistaa tekstilaskurit.
- **Artist:** botti-ikonit/silhuetit (Miner vs Hauler), materiaali-ikonit (voi johtaa `MAT_COLORS`:sta).
- **Testattava:** mikään paneeli ei ole auki ellei pelaaja klikkaa; tieto on maailmassa.

### Vaihe 5 — Diegeettinen onboarding + hionta (9-slice, game feel)  ⟶ viimeistely
**Tyyppi:** KOODI + hienot assetit (artist).
- Restyle onboarding pieneksi diegeettiseksi vihjeeksi (ei iso keskuslaatikko); toastit samaan tyyliin.
- 9-slice-pikselikehykset paneeleille, ikonien hover/press-variantit, kevyt animaatio (tray slide, toast fade).
- Valinnainen: radiaalivalikko työkaluille vaihtoehtona ikonipalkille (arvioidaan pelituntumalla).
- **Artist:** 9-slice-paneelikehys, ikonien hover-tilat.
- **Testattava:** UI tuntuu viimeistellyltä; game feel (hover, slide, fade) paikallaan.

---

## 5. RISKIT & HUOMIOT

- **Yksi Theme-resurssi on iso voitto** vs. nykyinen per-widget StyleBox-viritys: yhtenäisyys +
  ylläpidettävyys. Tee tämä ensin (Vaihe 1) — se yksin poistaa suurimman osan "dashboard"-tunnusta.
- **Backend säilyy:** `bot_manager`/`logistics`/`build_mode`-rajapinnat eivät muutu; kaikki nykyiset
  guardit (`has_method`) pysyvät. Remontti on turvallinen — ei kosketa pelilogiikkaa eikä GPU-koodia.
- **Ikkuna 1664×960:** kontekstipaneelit maailmassa pitää clampata ruudun sisään (koneet voivat olla reunalla).
- **Assettiriippuvuus:** Vaiheet 1, 3, 4, 5 tarvitsevat artist-agentin; Vaihe 2 on puhdasta koodia ja
  voidaan tehdä heti rinnakkain fonttiassetin odotellessa.
- **Skanneri ei katoa:** GDD §7.3:n materiaaliskanneri säilyy koodissa, mutta siirtyy debug-togglen taakse.
