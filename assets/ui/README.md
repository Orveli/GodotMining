# UI-assetit — Bot Mining -remontti

Kaikki tässä hakemistossa olevat PNG:t on generoitu ohjelmallisesti Python + Pillow -skriptillä
`gen_ui_assets.py`. Uusinta-ajo projektin juuresta:

```
python assets/ui/gen_ui_assets.py
```

Tyyli: **Industrial Gothic Underground** — tumma kivi/metalli, lämmin amber-aksentti
(`#d98a3a`, EI sinistä), 1px tumma ääriviiva (`#1a1410`), ei anti-aliasointia.
Katso `docs/UI_REDESIGN_PLAN.md` §3.5.

## Ikonit (`icons/`) — 24×24 px RGBA, läpinäkyvä tausta (ellei toisin mainita)

| Tiedosto | Käyttötarkoitus | Kuvaus |
|---|---|---|
| `tool_mine.png` | Työkalupalkki: Louhi [V] | Kaksiteräinen hakunpää (batwing-siluetti) + vino varsi, amber-kahvanpide |
| `tool_build.png` | Työkalupalkki: Rakenna [B] | Vasara, suorakaidepää + vino varsi, amber-kahvanpide |
| `tool_bots.png` | Työkalupalkki: Botit [T] | Pyöristetty drone-runko, hehkuva amber-silmä, antenni, skidit |
| `tool_erase.png` | Työkalupalkki: Pyyhi | Bold amber X, tumma ääriviiva |
| `desig_brush.png` | Designaatiotila: pensseli | Varsi + metalliferrule + tumma harjaspää + amber-maalitippa kärjessä |
| `desig_box.png` | Designaatiotila: laatikko | Neljä amber-kulmasulkua (marquee-valintakehys) |
| `desig_cell.png` | Designaatiotila: yksi solu | 3×3-ruudukko, keskiruutu korostettu amberilla |
| `build_furnace.png` | Rakennustray: Sulatusuuni | Kivirunko + piippu + hehkuva (fire-oranssi) aukko + kipinät |
| `build_crusher.png` | Rakennustray: Murskain | Kaksi vastakkaista hammastettua leukalevyä, näkyvä murskausrako jossa amber-malmimurunen |
| `build_conveyor.png` | Rakennustray: Kuljetushihna | Kaksi rullaa + vinoraidoitettu hihnapohja + amber-suuntanuoli |
| `zone_pickup.png` | Vyöhyke-popover: Nouto | Laatikko/kontti + amber-nuoli ylös |
| `zone_dump.png` | Vyöhyke-popover: Pudotus | Avoin kaukalo/kuoppa + amber-nuoli alas |
| `bot_miner.png` | Bottipaneeli / botin yllä: Miner-rooli | Drone-runko + kapeneva poravarsi/piikki kyljessä (amber-kärki) |
| `bot_hauler.png` | Bottipaneeli / botin yllä: Hauler-rooli | Drone-runko + kontti/rahtilaatikko selässä (amber-raita) |
| `coin.png` | HUD: raha (`◈ $1240`) | 16×16 px. Kultakolikko, kaksoisreunus, kiiltopikselit, keskitimantti-symboli |

## 9-slice-paneelikehykset (`panels/`)

| Tiedosto | Koko | 9-slice-marginaalit | Käyttötarkoitus |
|---|---|---|---|
| `panel_frame.png` | 48×48 px | 12px joka reunalla | Isot kontekstuaaliset paneelit (bottipaneeli, konereseptit, vyöhyke-popoverit). Tumma kivitausta (`#141414`), kaksinkertainen amber+teräs-reunus, kulmissa teräsniitit (pysyvät paikallaan 9-slice-venytyksessä, koska sijaitsevat 12px-marginaalikulmien sisällä). |
| `button_frame.png` | 24×24 px | 8px joka reunalla | Kevyt kehys yksittäisille napeille (toolbar-ikoninapit, tray-napit). Tumma tausta (`#1e1a16`), yksinkertainen amber-reunus + kevyt ylälaidan kiiltoviiva. |

9-slice-käyttö Godotissa: aseta `NinePatchRect`/`StyleBoxTexture` marginaalit yllä mainittuihin
arvoihin — kulmat pysyvät sellaisenaan, reunat venyvät 1D-suunnassa, keskusta venyy 2D-suunnassa.

## Preview

`preview_sheet.png` — kontaktivedos kaikista ikoneista 3× skaalattuna nimilapuilla tummalla
taustalla. **Vain katselmointia varten, ei peliasset.**

## Huomioita jatkokehitykselle

- Ikonit on suunniteltu toimimaan `button_frame.png`-taustan päällä (ei omaa taustalaattaa) —
  siksi läpinäkyvä tausta kaikissa.
- `bot_miner.png` / `bot_hauler.png` -runko on jaettu (`_bot_base`-apufunktio skriptissä) — jos
  lisää rooleja tulee, uusinnat samaa pohjaa ja vaihda vain lisädetalji + väri.
- Materiaali-ikonit (GDD §3.3 popover-filtterit) **eivät** sisälly tähän erään — ne on tarkoitus
  johtaa `MAT_COLORS`-taulukosta koodissa (`ui.gd`), ei erillisinä PNG-assetteina.
