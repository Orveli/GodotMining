"""
UI-assetit "Bot Mining" -remonttiin — Industrial Gothic Underground -tyyli.

Generoi kaikki ikonit (24x24, coin 16x16) ja 9-slice-paneelikehykset
assets/ui/-hakemistoon. Aja projektin juuresta:

    python assets/ui/gen_ui_assets.py

Tyyli: tumma kivi/metalli, lämmin amber-aksentti (EI sinistä), 1px tumma
ääriviiva, ei anti-aliasointia, luettava pieninä ikoneina.
"""

from PIL import Image, ImageDraw, ImageFont
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_ICONS = os.path.join(HERE, "icons")
OUT_PANELS = os.path.join(HERE, "panels")
os.makedirs(OUT_ICONS, exist_ok=True)
os.makedirs(OUT_PANELS, exist_ok=True)

# ---------------------------------------------------------------------------
# Paletti — Industrial Gothic Underground
# ---------------------------------------------------------------------------
OUTLINE    = (26, 20, 16, 255)     # #1a1410 — tumma ääriviiva
STONE_BG   = (20, 20, 20, 255)     # #141414 — paneelitausta
STONE_BG2  = (30, 26, 22, 255)     # #1e1a16 — paneelitausta (lämpimämpi)
STEEL_HI   = (140, 140, 133, 255)  # #8c8c85 — metalli, vaalea
STEEL_MID  = (107, 96, 85, 255)    # #6b6055 — metalli/kivi, keskisävy
STEEL_LO   = (66, 58, 50, 255)     # tumma metalli/varjo
AMBER      = (217, 138, 58, 255)   # #d98a3a — aksentti/reunus
AMBER_HI   = (240, 176, 100, 255)  # amber, vaalea kiilto
AMBER_LO   = (150, 92, 34, 255)    # amber, tumma varjo
FIRE       = (255, 128, 32, 255)   # #ff8020 — hehku/tuli
FIRE_HI    = (255, 196, 120, 255)  # tulen kirkkain kohta
GOLD       = (230, 199, 50, 255)   # #e6c732 — raha/kulta
GOLD_HI    = (250, 226, 130, 255)
GOLD_LO    = (168, 132, 24, 255)
TRANSP     = (0, 0, 0, 0)


def new_icon(size=24):
    return Image.new("RGBA", (size, size), TRANSP)


def oline(draw, xy, fill, width=1, outline=OUTLINE, ow=None):
    """Piirtää viivan tumman ääriviivan päällä (kaksinkertainen line)."""
    if ow is None:
        ow = width + 2
    draw.line(xy, fill=outline, width=ow)
    draw.line(xy, fill=fill, width=width)


def punch(draw, box):
    """'Leikkaa' läpinäkyvän reiän ellipsillä (RGBA-piirto ei alpha-blendaa)."""
    draw.ellipse(box, fill=TRANSP)


def save(img, path):
    img.save(path)
    print(f"  {os.path.relpath(path, HERE)}  {img.size[0]}x{img.size[1]}")


# ---------------------------------------------------------------------------
# Työkalu-ikonit
# ---------------------------------------------------------------------------

def icon_tool_mine():
    """Hakku — kaksiteräinen kärkipää (batwing) + amber-vartaalla varustettu vino varsi."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Varsi ensin (taakse), vino alhaalta oikealta ylös keskelle (sokettiin)
    oline(d, [(19, 21), (12, 13)], fill=STEEL_MID, width=3)
    # Amber-kahvanpide varren alapäässä
    d.rectangle([17, 18, 21, 21], fill=AMBER, outline=OUTLINE)
    # Pää: kaksiteräinen kärkipää, terävät ulkokärjet + soketti keskellä alhaalla
    head = [
        (2, 8),    # vasen kärki
        (8, 2),    # vasen yläsiipi
        (12, 7),   # keskilovi
        (16, 2),   # oikea yläsiipi
        (22, 8),   # oikea kärki
        (16, 11),  # oikea alareuna
        (12, 13),  # soketti (varren liitos)
        (8, 11),   # vasen alareuna
    ]
    d.polygon(head, fill=STEEL_MID, outline=OUTLINE)
    # Kiiltoreuna yläsiivissä
    d.line([(2, 8), (8, 2)], fill=STEEL_HI)
    d.line([(22, 8), (16, 2)], fill=STEEL_HI)
    # Tummat terävät kärkipisteet
    img.putpixel((2, 8), OUTLINE)
    img.putpixel((22, 8), OUTLINE)
    # Amber niitti soketissa
    img.putpixel((12, 12), AMBER)
    return img


def icon_tool_build():
    """Vasara — suorakaidepää + vino varsi, amber-kahva."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    oline(d, [(18, 21), (11, 12)], fill=STEEL_MID, width=3)
    d.rectangle([16, 18, 20, 21], fill=AMBER, outline=OUTLINE)
    # Vasaran pää
    d.rectangle([2, 3, 16, 10], fill=STEEL_MID, outline=OUTLINE)
    d.rectangle([2, 3, 16, 5], fill=STEEL_HI)
    d.line([(2, 3), (16, 3)], fill=STEEL_HI)
    # Varjo alareunaan
    d.line([(2, 10), (16, 10)], fill=STEEL_LO)
    # Pieni amber-korostus keskellä (leimasin/logo)
    img.putpixel((9, 6), AMBER)
    img.putpixel((9, 7), AMBER)
    return img


def icon_tool_bots():
    """Botti/drone-siluetti — pyöreähkö runko, yksi hehkuva amber-silmä."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Runko: pyöristetty laatikko (kulmat leikataan pois)
    d.rectangle([5, 6, 18, 17], fill=STEEL_MID, outline=OUTLINE)
    for corner in [(5, 6), (17, 6), (5, 16), (17, 16)]:
        punch(d, [corner[0], corner[1], corner[0] + 1, corner[1] + 1])
    d.rectangle([5, 6, 18, 17], outline=OUTLINE)  # ääriviiva takaisin siisteytenä
    # Ylempi kevyempi paneeli (kiilto)
    d.rectangle([7, 8, 16, 10], fill=STEEL_HI)
    # Silmä/lens
    d.ellipse([9, 10, 14, 15], fill=OUTLINE)
    d.ellipse([10, 11, 13, 14], fill=AMBER)
    img.putpixel((11, 12), AMBER_HI)
    # Antenni
    d.line([(11, 6), (11, 3)], fill=STEEL_MID, width=1)
    img.putpixel((11, 2), AMBER)
    # Jalat/skidit
    d.line([(7, 17), (6, 20)], fill=STEEL_LO, width=2)
    d.line([(16, 17), (17, 20)], fill=STEEL_LO, width=2)
    return img


def icon_tool_erase():
    """Pyyhi — bold X, amber täytöllä, tumma ääriviiva."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    oline(d, [(4, 4), (19, 19)], fill=AMBER, width=4)
    oline(d, [(19, 4), (4, 19)], fill=AMBER, width=4)
    # Kiiltopikselit
    img.putpixel((6, 6), AMBER_HI)
    img.putpixel((17, 6), AMBER_HI)
    return img


def icon_desig_brush():
    """Pensseli — varsi + amber-ferrule + tumma harjaspää."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    oline(d, [(19, 4), (11, 12)], fill=STEEL_MID, width=3)
    # Ferrule (metallipanta)
    d.rectangle([9, 12, 13, 15], fill=STEEL_HI, outline=OUTLINE)
    # Harjaspää
    d.polygon([(9, 14), (13, 14), (11, 21), (7, 21)], fill=STEEL_LO, outline=OUTLINE)
    # Amber-maalitippa kärjessä (designaatioväri)
    d.ellipse([7, 19, 11, 23], fill=AMBER, outline=OUTLINE)
    img.putpixel((8, 20), AMBER_HI)
    return img


def icon_desig_box():
    """Katkoviivalaatikko — valintakehyksen kulmasulut (marquee)."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    L = 4
    # Piirretään neljä L-kulmaa
    def corner(x, y, dx, dy):
        d.line([(x, y), (x + dx * L, y)], fill=AMBER, width=2)
        d.line([(x, y), (x, y + dy * L)], fill=AMBER, width=2)

    corner(3, 3, 1, 1)
    corner(20, 3, -1, 1)
    corner(3, 20, 1, -1)
    corner(20, 20, -1, -1)
    return img


def icon_desig_cell():
    """Yksi korostettu ruutu — 3x3-ruudukko, keskisolu amber."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    d.rectangle([2, 2, 21, 21], outline=STEEL_MID)
    d.line([(2, 9), (21, 9)], fill=STEEL_MID)
    d.line([(2, 15), (21, 15)], fill=STEEL_MID)
    d.line([(9, 2), (9, 21)], fill=STEEL_MID)
    d.line([(15, 2), (15, 21)], fill=STEEL_MID)
    d.rectangle([10, 10, 14, 14], fill=AMBER, outline=OUTLINE)
    img.putpixel((11, 11), AMBER_HI)
    return img


# ---------------------------------------------------------------------------
# Rakennus-ikonit
# ---------------------------------------------------------------------------

def icon_build_furnace():
    """Sulatusuuni — kivirunko, hehkuva aukko, piippu."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Piippu
    d.rectangle([14, 1, 18, 7], fill=STEEL_MID, outline=OUTLINE)
    # Runko
    d.rectangle([3, 6, 20, 21], fill=STEEL_MID, outline=OUTLINE)
    d.rectangle([3, 6, 20, 8], fill=STEEL_HI)
    # Hehkuva aukko
    d.rectangle([7, 12, 16, 18], fill=OUTLINE)
    d.rectangle([8, 13, 15, 17], fill=FIRE)
    d.rectangle([10, 14, 13, 16], fill=FIRE_HI)
    # Kivitiili-viivat rungossa
    d.line([(3, 15), (7, 15)], fill=STEEL_LO)
    d.line([(16, 15), (20, 15)], fill=STEEL_LO)
    d.line([(3, 19), (20, 19)], fill=STEEL_LO)
    # Kipinät
    img.putpixel((9, 10), FIRE)
    img.putpixel((14, 9), FIRE)
    return img


def icon_build_crusher():
    """Murskain — vastakkaiset hammastetut leukalevyt + näkyvä murskausrako."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Kotelo
    d.rectangle([2, 2, 21, 21], fill=STEEL_LO, outline=OUTLINE)
    # Yläleuka: tanko + kolme hammasta osoittaen alas rakoon
    d.rectangle([3, 3, 20, 8], fill=STEEL_MID, outline=OUTLINE)
    for tx in (4, 10, 16):
        d.polygon([(tx, 8), (tx + 4, 8), (tx + 2, 11)], fill=STEEL_MID, outline=OUTLINE)
    d.line([(3, 3), (20, 3)], fill=STEEL_HI)
    # Alaleuka: tanko + kolme hammasta osoittaen ylös rakoon
    d.rectangle([3, 16, 20, 20], fill=STEEL_HI, outline=OUTLINE)
    for tx in (4, 10, 16):
        d.polygon([(tx, 16), (tx + 4, 16), (tx + 2, 13)], fill=STEEL_HI, outline=OUTLINE)
    # Murskausrako keskellä — pieni amber malmimurunen näkyy raossa
    img.putpixel((11, 12), AMBER)
    img.putpixel((12, 12), AMBER_HI)
    return img


def icon_build_conveyor():
    """Kuljetushihna — vinoraidoitettu hihna + suuntanuoli."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Rullat
    d.ellipse([1, 10, 7, 16], fill=STEEL_HI, outline=OUTLINE)
    d.ellipse([17, 10, 23, 16], fill=STEEL_HI, outline=OUTLINE)
    # Hihnapohja
    d.rectangle([4, 11, 20, 15], fill=STEEL_LO, outline=OUTLINE)
    # Vinoraidat hihnan pinnalla
    for x in range(4, 20, 4):
        d.line([(x, 15), (x + 3, 11)], fill=STEEL_MID, width=1)
    # Suuntanuoli yllä
    d.line([(6, 6), (17, 6)], fill=AMBER, width=2)
    d.polygon([(17, 3), (22, 6), (17, 9)], fill=AMBER, outline=OUTLINE)
    return img


# ---------------------------------------------------------------------------
# Vyöhyke-ikonit
# ---------------------------------------------------------------------------

def icon_zone_pickup():
    """Nouto — laatikko + nuoli ylös (materiaali pois alueelta)."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Laatikko alaosassa
    d.rectangle([3, 13, 20, 21], fill=STEEL_MID, outline=OUTLINE)
    d.line([(3, 13), (20, 13)], fill=STEEL_HI)
    d.line([(11, 13), (11, 21)], fill=STEEL_LO)
    d.line([(3, 17), (20, 17)], fill=STEEL_LO)
    # Nuoli ylös
    d.line([(11, 10), (11, 2)], fill=AMBER, width=2)
    d.polygon([(7, 6), (11, 0), (15, 6)], fill=AMBER, outline=OUTLINE)
    return img


def icon_zone_dump():
    """Pudotus — kaukalo/kuoppa + nuoli alas (materiaali alueelle)."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    # Kaukalo (leveämpi ylhäällä, kapeampi alhaalla)
    d.polygon(
        [(2, 12), (21, 12), (17, 21), (6, 21)],
        fill=STEEL_LO, outline=OUTLINE,
    )
    d.line([(2, 12), (21, 12)], fill=STEEL_HI)
    # Nuoli alas
    d.line([(11, 1), (11, 9)], fill=AMBER, width=2)
    d.polygon([(7, 6), (11, 12), (15, 6)], fill=AMBER, outline=OUTLINE)
    return img


# ---------------------------------------------------------------------------
# Botti-ikonit
# ---------------------------------------------------------------------------

def _bot_base(d, img):
    """Yhteinen bottirunko molemmille bot_*-ikoneille."""
    d.rectangle([4, 7, 17, 18], fill=STEEL_MID, outline=OUTLINE)
    for corner in [(4, 7), (16, 7), (4, 17), (16, 17)]:
        punch(d, [corner[0], corner[1], corner[0] + 1, corner[1] + 1])
    d.rectangle([4, 7, 17, 18], outline=OUTLINE)
    d.rectangle([6, 9, 15, 11], fill=STEEL_HI)
    d.ellipse([8, 11, 13, 16], fill=OUTLINE)
    d.ellipse([9, 12, 12, 15], fill=AMBER)
    img.putpixel((10, 13), AMBER_HI)
    d.line([(6, 18), (5, 21)], fill=STEEL_LO, width=2)
    d.line([(15, 18), (16, 21)], fill=STEEL_LO, width=2)


def icon_bot_miner():
    """Miner-botti — runko + poravarsi/piikki edessä (kaivuudetalji)."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    _bot_base(d, img)
    # Poravarsi botin kyljessä (kapeneva piikki, osoittaa alaviistoon)
    d.polygon([(17, 10), (23, 8), (19, 19), (16, 15)], fill=STEEL_HI, outline=OUTLINE)
    img.putpixel((21, 9), AMBER)
    img.putpixel((18, 16), STEEL_LO)
    return img


def icon_bot_hauler():
    """Hauler-botti — runko + kontti selässä."""
    img = new_icon()
    d = ImageDraw.Draw(img)
    _bot_base(d, img)
    # Kontti botin päällä/takana
    d.rectangle([6, 1, 15, 7], fill=STEEL_LO, outline=OUTLINE)
    d.line([(6, 4), (15, 4)], fill=AMBER)
    img.putpixel((7, 2), STEEL_HI)
    img.putpixel((14, 2), STEEL_HI)
    return img


# ---------------------------------------------------------------------------
# Kolikko (16x16)
# ---------------------------------------------------------------------------

def icon_coin():
    img = new_icon(16)
    d = ImageDraw.Draw(img)
    d.ellipse([1, 1, 14, 14], fill=GOLD_LO, outline=OUTLINE)
    d.ellipse([2, 2, 13, 13], fill=GOLD, outline=OUTLINE)
    d.ellipse([4, 4, 11, 11], outline=GOLD_LO)
    # Kiilto ylävasemmalla
    for px in [(4, 3), (5, 3), (3, 4), (3, 5)]:
        img.putpixel(px, GOLD_HI)
    # Keskisymboli (pieni timantti)
    d.polygon([(7, 5), (10, 7), (7, 10), (4, 7)], fill=GOLD_LO, outline=OUTLINE)
    img.putpixel((7, 7), GOLD_HI)
    return img


# ---------------------------------------------------------------------------
# 9-slice-paneelikehykset
# ---------------------------------------------------------------------------

def panel_frame():
    """48x48, marginaalit 12px. Kivikehys ohuella amber-reunuksella."""
    S = 48
    img = Image.new("RGBA", (S, S), STONE_BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, S - 1, S - 1], outline=OUTLINE, width=1)
    d.rectangle([2, 2, S - 3, S - 3], outline=AMBER, width=2)
    d.rectangle([5, 5, S - 6, S - 6], outline=STEEL_MID, width=1)
    # Kulmaniitit (pysyvät 12px-marginaalikulmissa, eivät venydy 9-slicessä)
    # 5x5 niitti: outline-rengas + STEEL_HI-täyttö + tumma ruuvinlovi keskellä
    for cx, cy in [(8, 8), (S - 9, 8), (8, S - 9), (S - 9, S - 9)]:
        d.rectangle([cx - 2, cy - 2, cx + 2, cy + 2], fill=STEEL_HI, outline=OUTLINE)
        img.putpixel((cx, cy), OUTLINE)
    return img


def button_frame():
    """24x24, marginaalit 8px. Kevyt kehys napeille."""
    S = 24
    img = Image.new("RGBA", (S, S), STONE_BG2)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, S - 1, S - 1], outline=OUTLINE, width=1)
    d.rectangle([1, 1, S - 2, S - 2], outline=AMBER, width=1)
    # Kevyt sisäkiilto ylälaidassa
    d.line([(2, 2), (S - 3, 2)], fill=AMBER_HI)
    return img


# ---------------------------------------------------------------------------
# Preview sheet
# ---------------------------------------------------------------------------

def build_preview_sheet(icon_paths):
    scale = 3
    cell_w, cell_h = 24 * scale + 16, 24 * scale + 26
    cols = 6
    rows = -(-len(icon_paths) // cols)
    sheet = Image.new("RGBA", (cols * cell_w + 20, rows * cell_h + 40), STONE_BG)
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    d.text((10, 10), "GodotMining UI Icons — preview (ei peliasset, vain katselmointi)",
            fill=AMBER_HI, font=font)
    for i, (name, path) in enumerate(icon_paths):
        col = i % cols
        row = i // cols
        x = 10 + col * cell_w
        y = 30 + row * cell_h
        icon = Image.open(path).convert("RGBA")
        iw, ih = icon.size
        big = icon.resize((iw * scale, ih * scale), Image.NEAREST)
        d.rectangle([x, y, x + cell_w - 10, y + cell_h - 12], outline=STEEL_LO)
        px = x + (cell_w - 10 - big.width) // 2
        sheet.alpha_composite(big, (px, y + 6))
        d.text((x + 4, y + cell_h - 22), name, fill=STEEL_HI, font=font)
    return sheet


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    print("Icons:")
    icons = {
        "tool_mine.png": icon_tool_mine(),
        "tool_build.png": icon_tool_build(),
        "tool_bots.png": icon_tool_bots(),
        "tool_erase.png": icon_tool_erase(),
        "desig_brush.png": icon_desig_brush(),
        "desig_box.png": icon_desig_box(),
        "desig_cell.png": icon_desig_cell(),
        "build_furnace.png": icon_build_furnace(),
        "build_crusher.png": icon_build_crusher(),
        "build_conveyor.png": icon_build_conveyor(),
        "zone_pickup.png": icon_zone_pickup(),
        "zone_dump.png": icon_zone_dump(),
        "bot_miner.png": icon_bot_miner(),
        "bot_hauler.png": icon_bot_hauler(),
        "coin.png": icon_coin(),
    }
    icon_paths = []
    for name, img in icons.items():
        path = os.path.join(OUT_ICONS, name)
        save(img, path)
        icon_paths.append((name, path))

    print("Panels:")
    save(panel_frame(), os.path.join(OUT_PANELS, "panel_frame.png"))
    save(button_frame(), os.path.join(OUT_PANELS, "button_frame.png"))

    print("Preview sheet:")
    sheet = build_preview_sheet(icon_paths)
    save(sheet, os.path.join(HERE, "preview_sheet.png"))


if __name__ == "__main__":
    main()
