# Spec: Fog of war + syvyyspohjaiset mineraalisuonet

Suunniteltu 2026-07-15. Käyttäjän lukitut päätökset:
- **Fog-malli:** pysyvä "tutkittu jää muistiin + valo". Tutkitut alueet himmeästi näkyvissä, aktiivinen valonlähde kirkas, tutkimaton maanalainen TÄYSIN musta.
- **Valonlähteet:** avoimet kuilut + botit + base/koneet + aseteltavat lamput (kaikki).

Toteutus kahdessa vaiheessa. **Vaihe 1 ensin** (self-contained, testattavissa headless), sitten Vaihe 2.

---

## Vaihe 1 — Uudet materiaalit + mineraalisuonet

### 1.1 Uudet materiaalit
- `COPPER = 20`, `RARE_EARTH = 21`.
- `scripts/pixel_world.gd`: uudet `MAT_COPPER`/`MAT_RARE_EARTH` vakiot. Laajenna `PALETTE_DEFAULT`, `PALETTE_DEEP`, `PALETTE_VAR_DEFAULT` 20 → 22 alkioon.
  - Kuparin väri: patinoitunut/oranssiruskea esim. `Vector3(0.72, 0.45, 0.28)` (deep: himmeämpi). Var ~0.04.
  - Rare earth: hohtava sinivihreä/violetti esim. `Vector3(0.35, 0.75, 0.65)` (erottuva, "arvokas"). Var ~0.05.
- `shaders/pixel_render.gdshader`: `uniform vec3 mat_colors[22]`, `uniform float mat_var[22]`. Vaihda KAIKKI `clamp(..., 0, 19)` → `clamp(..., 0, 21)` (pääluku + CA-alinäytteet `r_id`/`b_id`).
- `shaders/simulation.glsl`: `const uint COPPER = 20u; const uint RARE_EARTH = 21u;`. Lisää molemmat `falls()`- JA `is_powder()`-listoihin (käyttäytyvät kuten IRON_ORE/GOLD_ORE — putoava jauhe, pysyy kivessä paikallaan).
- Tarkista `pixel_world.gd`:n GRAVEL-muunnokset (kaivaus/räjähdys `MAT_GRAVEL`-haaroissa n. rivit 1119–1287): uudet malmit menevät samaan "kiinteä → sora" -logiikkaan kuin muut malmit, EI erikoiskäsittelyä (economy myöhemmin).

### 1.2 Suonet — `_place_vein_set()` (world_gen.gd)
Korvaa malmien blobit (`_place_deposit_set`-kutsut MAT_OIL/GOLD/IRON/COAL riveillä 122–135) suonilla. Vesi/öljy/hiekka voivat jäädä blobeiksi.

Worm-walk per suoni:
1. Aloitus: x tasavälein sektioihin (kuten nykyinen `section_w`), y = `surface_y[x] + randf_range(depth_min, depth_max) * max_dp`.
2. Suunta `heading` = alaspäin painottunut satunnaiskulma.
3. Askel (yht. `vein_len` askelta): carvaa ellipsi säteellä `thickness` VAIN `grid[idx] == MAT_STONE` -soluihin (ei ylikirjoita muita malmeja/bedrockia). Etene `heading`-suuntaan; per askel `heading += randf_range(-0.35, 0.35)` (mutkittelu). Reunaperturbaatio kuten nyt.
4. Haaroitus: pienellä todennäköisyydellä (esim. 0.06/askel) rekursiivinen ali-suoni (lyhyempi `vein_len`, ohuempi `thickness`, syvyys 1).
5. Clamp reunoihin, lopeta bedrockissa/reunalla.

### 1.3 Syvyys-arvotaulukko (data-driven)
Normalisoitu maanalainen syvyys 0=pinta → 1=pohja (`max_dp` -perustan mukaan). Arvokkaimmat harvimpia + syvimmällä.

| Aine | ID | depth_min | depth_max | vein_count | vein_len | thickness |
|---|---|---|---|---|---|---|
| Hiili COAL | 16 | 0.00 | 0.35 | 12 | 40–70 | 2–3 |
| Rauta IRON_ORE | 12 | 0.10 | 0.55 | 10 | 35–60 | 2–3 |
| Kupari COPPER | 20 | 0.35 | 0.75 | 7 | 30–50 | 2 |
| Kulta GOLD_ORE | 13 | 0.55 | 0.90 | 5 | 25–40 | 1–2 |
| Rare earth RARE_EARTH | 21 | 0.75 | 1.00 | 3 | 20–35 | 1–2 |

Sijoita arvokkain ensin (ei ylikirjoita). Määrät static-muuttujiksi (kuten nykyiset `*_count`) debug_menu-tuen vuoksi.

### 1.4 Vaiheen 1 testaus
Aja `worldgen_test.gd` headless (Godot 4.6 polku: Desktop/Godot/, katso muisti). Varmista: ei kaatumista, uudet materiaalit generoituvat, tyhjä% järkevä, suonet syvyysvyöhykkeillään. Iteroi tuning autonomisesti.

---

## Vaihe 2 — Fog of war

### 2.1 `scripts/light_field.gd` (uusi)
Alaskaalattu valopuskuri, DS = 8 → LW = 208, LH = 120.
- `PackedByteArray light` (LW*LH), `PackedFloat32Array explored` (LW*LH, pysyvä muisti).
- `Image` R8 + `ImageTexture`, päivitetään joka frame (tai joka 2. frame jos tarpeen).
- `func update(grid, W, H, emitters) -> void`:
  1. Nollaa `light` → `explored`-lattia (explored-solu → 0.12, muu → 0.0).
  2. **Taivasvalo:** jokaiselle DS-sarakkeelle kävele ylhäältä; laske EMPTY-solut → valo `1.0` kunnes osuu kiinteään, sitten vaimenee syvyyden mukaan muutaman solun matkalla. Näin avoimet kuilut valaistuvat.
  3. **Emitterit:** lista `{pos: Vector2i (sim-koord), radius, intensity}`. Leimaa additiivinen säteittäinen falloff DS-tilaan.
  4. (valinnainen) 3×3 sumennus.
  5. `explored[i] = max(explored[i], light[i] > 0.35 ? 1.0 : explored[i])`.
  6. Kirjoita `light` → Image → `texture.update()`.

### 2.2 Render
`shaders/pixel_render.gdshader`:
```glsl
uniform sampler2D light_tex : filter_linear;
...
// juuri ennen vignettiä:
float lv = texture(light_tex, UV).r;
color *= clamp(lv, 0.0, 1.0);
```
`pixel_world.gd`: luo LightField `_ready()`:ssä, aseta `light_tex`-uniform, kutsu `update()` sim-loopissa.

### 2.3 Emitterien keräys (pixel_world.gd)
Kokoa emitters-lista per frame:
- **Botit:** `bot_manager` botit → pieni radius (~40px), keski intensity.
- **Base + koneet:** rakennukset (`building_layer`/koneet furnace/crusher/drill) → keski radius (~60px).
- **Lamput:** ks. 2.4.
Taivasvalo hoituu light_field:in sisällä (ei emitteri).

### 2.4 Aseteltava lamppu
Minimitoteutus: uusi kevyt "lamppu"-entiteetti (Array<Vector2i> pixel_world:ssa) jonka voi asettaa (debug-näppäin tai build-preview). Jokainen lamppu = emitteri (radius ~70px, kirkas). Bottien automaattinen lampunlasku = jatkotyö (dokumentoi, älä toteuta nyt jos venyy).

### 2.5 Vaiheen 2 testaus
Käynnistä peli (muisti: käynnistä AINA). Varmista: pinta kirkas, maanalainen tutkimaton musta, kaivettu kuilu valaistuu ylhäältä, botit/base valaisevat, kaivettu jää himmeästi muistiin. FPS pysyy.

---

## Ei tässä (jatkotyö)
Uusien orejen economy: jalostus (`furnace.gd`/`crusher.gd`), myyntiarvo (`money_exit.gd`), bottien kaivauskohteet/prioriteetit (`designation_grid.gd`, `bot.gd`). Erillinen tiketti.
