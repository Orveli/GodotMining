---
description: Lue ja analysoi uusin I-tallennettu pelidata (kuvakaappaus + pelitila)
allowed_tools: Bash, Read, Edit
---

Lue pelaajan viimeisin I-tallennus ja analysoi pelimaailman tila.

## Vaihe 1 — Lue tallennettu data

Lue molemmat tiedostot:
- `C:\Users\mauri\Desktop\Git\GodotMining\game_state.json` (pelitila)
- `C:\Users\mauri\Desktop\Git\GodotMining\game_view.png` (kuvakaappaus)

Jos tiedostoja ei löydy: sano käyttäjälle "Paina I pelissä ensin."

## Vaihe 2 — Analysoi yhdessä

Yhdistä JSON-data ja kuva analyysissä:

**Pelaaja:**
- Sijainti pikselikoordinaateissa (x, y) — missä päin karttaa?
- Nopeus — liikkuuko, putoaako, nouseeko?
- on_ground / in_water — missä tilassa?
- Mihin suuntaan katsoo (facing_right)

**Ase & työkalu:**
- Mikä ase aktiivinen (PICKAXE, MEGA_DRILL, LASER, ROCKET, GRAVITY_GUN)
- Valittu maalausmateriaali ja pensselikoko

**Gravity Gun** (jos mode != "off"):
- Kentän sijainti (pos_x, pos_y)
- Säde (radius)
- Montako pikseliä pidätettynä (held_pixels) — tässä näkyy jumittumisongelmat
- Tila: pull vai vacuum

**Simulaatio:**
- FPS — onko suorituskykyongelma?
- Nopeus (sim_speed)

**Maailma kuvassa:**
Värikartta tunnistamiseen:
- `#141420` taustaväri = EMPTY
- `#DBC773` keltainen = SAND
- `#3366D9` sininen = WATER  
- `#808085` harmaa = STONE
- `#734720` ruskea = WOOD
- `#FF8019` oranssi = FIRE
- `#332619` lähes musta = OIL
- `#CCD9E6` vaalea = STEAM
- `#59544C` tumma harmaa = ASH
- `#A6E0D6` turkoosi = GLASS
- `#735129` tumma ruskea = DIRT
- `#8C6B61` ruosteenpunainen = IRON_ORE
- `#B8A640` kellertava = GOLD_ORE
- `#ADADB8` hopea = IRON
- `#E6C733` kultainen = GOLD
- `#2E2B35` antrasiitti = COAL
- Sininen siluetti = PLAYER

## Vaihe 3 — Jos dataa puuttuu analyysin kannalta

Jos huomaat että tarvitsemasi tieto **puuttuu** `game_state.json`:sta (esim. rakettidata, launcher-tila, uunin lämpötila, konveyorin sisältö — mitä ikinä analysoitava tilanne vaatii):

1. Lue `scripts/pixel_world.gd` funktio `_save_ai_screenshot()` (n. rivi 2625)
2. Lisää puuttuva kenttä `state`-dictionaryyn
3. Kerro käyttäjälle mitä lisäsit: **"Lisäsin [X] dataan — paina I uudelleen saadaksesi tarkemman analyysin"**

Näin työkalu kehittyy jokaisen debuggaussession myötä.

## Vaihe 4 — Raportti

Anna selkeä, lyhyt raportti:

1. **Tilanne** — mitä pelissä tapahtuu juuri nyt
2. **Pelaaja** — sijainti, tila, aktiivinen ase
3. **Maailma** — näkyvät materiaalit, rakenteet, simulaatiot
4. **Huomiot** — poikkeamat, bugit, mielenkiintoiset tilanteet
5. **Puuttuiko dataa?** — kerro jos lisäsit uuden kentän exporttiin
