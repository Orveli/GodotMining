# Game Design Document — Chicken Factory Defense

## Konsepti

Falling sand -pohjainen tehdaspeli mustalla huumorilla. Pelaaja pyörittää kanateurastamoa pikselifysiikalla ja puolustautuu alieneilta jotka yrittävät tehdä ihmisistä burgereita.

**Genre**: Factory/Processing + Tower Defense + Falling Sand Physics
**Identiteetti**: Musta huumori, fysiikkapohjainen kaaos, visuaalinen satisfaktio
**Referenssit**: Noita (fysiikka) + Factorio (linjastot) + Half-Life 2 (gravity gun) + Marble Run (fiilis)

---

## Core Loop

```
Kanat spawnaa → heitä gravity gunilla koneisiin → jalostus pikselifysiikalla → myy → osta aseita → puolusta alieneilta
```

### Progression (eksponentiaalinen kasvu)

Kasvu = enemmän pikseleitä liikkeessä ruudulla. Pelaaja *näkee* kasvun — ruutu täyttyy liikkeestä ja kaaoksesta.

```
Taso 1: Muutama kana, manuaalinen käsittely         → vähän $
Taso 2: Kana-spawner + peruslinjasto                 → 10x $
Taso 3: Automaattiketju kana→pihvi→burgeri           → 100x $
Taso 4: Massiivinen tehdas, satoja kanoja yhtä aikaa → 1000x $
```

### Talous

- Jalostetut tuotteet arvokkaampia: kana < pihvi < burgeri
- Raha → uusia spawnereita, työkaluja, aseita, puolustuksia, koneita

---

## Core-mekaniikka #1: Ympäristön tuhoaminen

Tuhoamisen PITÄÄ tuntua hauskalta. Ei pelkkää pikselien poistoa.

### Juice-vaatimukset

- **Screenshake** — kamera tärähtää iskun voimalla
- **Partikkelit** — pikselihiukkaset lentää räjähdysmäisesti
- **Hitlag/freeze frame** — 2-3 framen pysähdys iskun hetkellä → isku tuntuu painavalta
- **Crack-efekti** — halkeamat leviää ennen hajoamista, ei instant-poisto
- **Ketjureaktiot** — isot lohkareet → pienemmät → vielä pienemmät
- **Ääniefektit** — murskaus, romu, tärähdys

### Tuhoamistyökalut (progression)

| Työkalu | Vaikutus | Unlocked |
|---|---|---|
| Hakku | Muutama pikseli tippuu | Alku |
| Pommi | Satoja pikseleitä lentää joka suuntaan | Varhainen |
| Pora | Jatkuva palkki, mursketta sivuille | Keski |
| Laser | Polttaa linjan, sytyttää puun, sulattaa metallin | Keski |
| Räjähdysaine | Massiivinen tuho + debris | Myöhäinen |
| Kaivoskone | Iso rigid body murskaa kaiken | Myöhäinen |
| Maanjäristys | Koko ruutu kaaosta | Loppupeli |

### Generoitu maailma

- Kallioita eri materiaaleista
- Malmijuonia kiven sisässä
- Vesitaskuja (räjäytä → tulva!)
- Öljytaskuja (räjäytä + tuli = inferno)

---

## Core-mekaniikka #2: Gravity Gun

Referenssi: Half-Life 2 gravity gun. Fysiikkapohjainen voimakenttä, EI "pick & place".

### Vaatimukset

- **Imeytys** — pikselit virtaa kohti tähtäintä, ei teleporttaa
- **Pito** — massa heiluu fysiikalla, ei lukitu kursoriin
- **Heitto** — momentum säilyy, heittosuunta kursorista
- **Massan tuntu** — iso kasa liikkuu hitaammin, pieni lentää nopeesti
- **Visuaalinen feedback** — säde/voimakenttä näkyy, tartutut pikselit hohtaa

### Käyttö

- Irtonaisten pikselien siirtely linjastoille
- Kanojen heittely koneisiin
- Romun raivaus
- Luova ongelmanratkaisu

---

## Core-mekaniikka #3: Jalostusketju

Kaikki pikselifysiikalla — ei abstrakteja koneita.

### Kanaketju

```
Kana (rigid body)
  ↓ teurastuskone
Liha-pikselit + Luu-pikselit + Höyhen-pikselit
  ↓                ↓              ↓
Grilli          Mylly          Keräys
  ↓                ↓              ↓
Pihvi          Luujauho       Tyynyt
  ↓
Burgeri → $$$
```

### Periaatteet

- Kourut, rampit, suppilot, seinät = pelaajan rakentamia falling sand -rakenteita
- Materiaalit valuu kouruja pitkin, reagoi toisiinsa
- Grilli = tuli-interaktio
- Kourun kulma väärin → tavara lentää ohi → kaaos → hauskaa

---

## Alienit — Puolustus

### Symmetria-twist

Alienit tekevät pelaajalle täsmälleen samaa:
- Nappaavat ihmis-NPC:itä
- Vetävät ne omaan tehtaaseen
- Yrittävät tehdä "ihmisburgereita"
- Pelaajan pitää puolustaa + tuhota alien-tehdas

Pelaaja tajuaa olevansa yhtä paha kuin alienit.

### Puolustuskeinot (ostetaan kanatulolla)

- Torneja jotka ampuu alieneja (ammukset = pikseleitä!)
- Seiniä ja esteitä
- Ansoja (öljy + tuli = alien paistuu)
- Isompia aseita

---

## Materiaalit

### Nykyiset (toimivat)

EMPTY=0, SAND=1, WATER=2, STONE=3, WOOD=4, FIRE=5, OIL=6, STEAM=7, ASH=8, WOOD_FALLING=9

### Uudet tarvittavat

**Eläinperäiset (jalostusketju):**
- MEAT — tippuu kuin hiekka
- BONE — tippuu, kovempi
- FEATHER — kevyt, leijuu/leijailee
- COOKED_MEAT — liha + tuli -reaktio
- GROUND_MEAT — myllyn tulos
- BONE_MEAL — myllyn tulos luista

**Ympäristö (myöhemmin):**
- Malmit (kupari, rauta, kulta)
- Lasi (hiekka + tuli)
- Sula metalli (malmi + tuli)

### Kana

Kana = rigid body, ei pikselimateriaali. Teurastuskone muuntaa rigid bodyn → pikselimateriaaleiksi.

---

## Prioriteetti

1. **Tuhoaminen + gravity gun** — pelin "feel". Jos nää ei toimi, mikään muu ei pelasta.
2. **Kana rigid body + teurastuskone** — core gameplay loop
3. **Jalostusketju** — syvyys
4. **Talous + progression** — motivaatio
5. **Alienit + puolustus** — loppupelin sisältö
