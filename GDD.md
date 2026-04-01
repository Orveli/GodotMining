# Game Design Document — Mining Factory

## Konsepti

Sivultapäin kuvattu kaivos- ja tehdaspeli falling sand -fysiikalla. Pelaaja kaivaa maata, kuljettaa materiaalit hissillä ja liukuhihnoilla pintatehtaaseen, jalostaa ne, ja tiputtaa lopputuotteet "money exit" -aukkoon — josta saa rahaa ja unlockeja uusiin työkaluihin ja materiaaleihin.

**Genre**: Mining + Factory / Processing + Falling Sand (2D side-view)
**Referenssit**: Noita (fysiikka + kaivaus), Factorio (linjastot + jalostus), Terraria (maailman rakenne)

---

## Core Loop

```
Kaiva materiaalia
  → laita liukuhihnalle
  → hissi ylös pintaan
  → pintatehdas jalostaa
  → money exit
  → raha + unlockit
  → paremmat työkalut
  → kaivaa syvemmälle / laajenna tehdasta
```

---

## Maailman rakenne

```
[ Pintatehdas — liukuhihnat, koneet, money exit ]
─────────────────────────────────────────────────
[ Pintakerros — multa, hiekka, puut, järviä      ]
─────────────────────────────────────────────────
[ Kivisyvyys — kivi, rautajuonia                 ]
─────────────────────────────────────────────────
[ Luolastot — isompia onkaloita, harvinaisempia  ]
[ materiaaleja (kulta, erikoismalmi)             ]
```

- Pinta: tasainen alue, pari järveä — tehdas rakennetaan tänne
- Syvemmällä: luolastoja, eri materiaalien esiintymiä
- Syvyys = vaikeampi kaivaa, arvokkaammat materiaalit

---

## Kaivaus

Pelaaja rikkoo maata eri työkaluilla. Rikottu materiaali muuttuu irrallisiksi pikselimateriaaleiksi (falling sand).

### Työkalut

| Työkalu | Koko | Nopeus | Kuvaus |
|---|---|---|---|
| Hakku | Pieni | Hidas | Perustyökalu, tarkka, kaivaa kiveä hitaasti |
| Lapio | Pieni | Nopea | Helpot materiaalit (multa, hiekka) nopeasti |
| Dynamiitti | Iso | Välitön | Räjähtää, iso alue, kaaos, yksi käyttö |
| Pora | Keski | Nopea | Automaattinen kaivaus suoraan, ei räjähdystä |
| Jättipora | Iso | Nopea | Iso alue, kuluttaa energiaa/polttoainetta |
| Laser | Iso | Erittäin nopea | Sulattaa kiven, voi luoda nestettä (lava?) |
| Likiheitin | Iso | Välitön | Ampuu nestettä (vesi, öljy) onkaloon, pyyhkii pieniä materiaaleja |

### Progression

```
Lapio/Hakku → Dynamiitti → Pora → Jättipora → Laser
```

Alussa naputellaan, myöhemmin räjäytellään vuoria.

---

## Kuljetus

Materiaalit kulkevat kaivoksesta pintatehtaaseen rakennettua reittiä pitkin.

| Osa | Toiminta |
|---|---|
| Hissi | Siirtää materiaalit pystysuoraan ylös |
| Liukuhihna | Siirtää materiaalit vaakasuoraan |
| Kouru / ramppi | Vinossa oleva pinta, materiaalit valuvat |
| Suppilo | Kerää hajallaan olevat pikselit yhteen |

Pelaaja rakentaa reitin itse. Falling sand -fysiikka: väärä kulma → materiaali valuu lattialle.

---

## Jalostus

Koneet muuntavat raaka-aineet arvokkaiksi tuotteiksi. Kaikki pikselifysiikalla — ei abstrakteja lukuja.

| Raaka-aine | Kone | Tuote | Arvo |
|---|---|---|---|
| Hiekka | Uuni | Lasi | + |
| Kivi | Murskain | Sora / hienoaines | + |
| Multa | TBD | TBD | + |
| Rauta | Sulatto | Rautaharkko | ++ |
| Kulta | Sulatto | Kultaharkko | +++ |

Jalostusketjut voivat olla monivaiheisia:
```
Rauta → [Sulatto] → Rautaharkko → [Taonta?] → Työkalu → $$$
```

---

## Money Exit

- Lopputuote tiputetaan "money exit" -aukkoon pintatehtaalla
- Raakana = vähän rahaa, jalostettu = enemmän
- Bonareita: unlockit (uudet koneet, uudet materiaalit, syvemmät alueet)

---

## Talous & Progression

| Toimenpide | Tulos |
|---|---|
| Raha | Paremmat kaivaustyökalut, nopeammat hihnat, uudet koneet |
| Unlockit | Uudet materiaalit, syvemmät alueet, monimutkaisemmat ketjut |
| Syvyys | Arvokkaammat materiaalit, enemmän rahaa |

Kasvu näkyy **visuaalisesti**: isompi tehdas, enemmän liikettä ruudulla, syvempi kaivos.

---

## Materiaalit

### Olemassa olevat (toimivat)
EMPTY, SAND, WATER, STONE, WOOD, FIRE, OIL, STEAM, ASH, WOOD_FALLING

### Tarvittavat uudet
| Materiaali | Käytös |
|---|---|
| DIRT (multa) | Pintakerros, pehmeä, kaivuu helppo |
| IRON_ORE (rauta) | Kova, syvemmällä, sulatto |
| GOLD_ORE (kulta) | Harvinainen, syvällä, sulatto |
| GLASS (lasi) | Hiekka + uuni — jo suunniteltu |
| IRON (rautaharkko) | Jalostustuote |
| GOLD (kultaharkko) | Jalostustuote, arvokas |

---

## Kehitysprioriteetti

1. Uudet materiaalit: multa, rauta, kulta (maailmangeneraatio + shader)
2. Jalostuskoneet: sulatto, murskain
3. Kuljetusjärjestelmä: hissi, liukuhihnat
4. Money exit + rahajärjestelmä
5. Ostaminen / unlock-järjestelmä
6. Maailmangeneraatio: luolastot, malmiesiintymät
