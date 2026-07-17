"""
Bottien in-game pikselispritet — "Industrial Gothic Underground".

Botit lentavat seka tumman maanalaisen etta vaalean taivaan yla, ja niita
piirtaa taalla asti pelkka kaksi sisakkaista nelio (ks. bot_manager.gd
draw_bots). Tama generaattori korvaa ne kunnon spriteilla:

    bot_miner_{0,1}.png   12x12, anchor "center"  — amber-runko + poranterä
    bot_hauler_{0,1}.png  12x12, anchor "center"  — sininen runko + rahtikontti

Aja repo-juuresta:

    python assets/sprites/gen_bots.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import palette as P  # noqa: E402
from PIL import ImageDraw  # noqa: E402

OUT = HERE

# Runko: pyoristetty 10x10 laatikko keskella 12x12-kanvaasia (1px lapinakyva
# marginaali joka reunalla -> anchor "center", offset -6,-6 sopii botin
# render-rectiin bot_manager.gd:ssa).
BODY = [1, 1, 10, 10]
CORNERS = [(1, 1), (9, 1), (1, 9), (9, 9)]


def _bot_frame(body, body_hi, body_lo):
    """Yhteinen bottirunko: pyoristetty runko + ylapaneelin kiilto + skidit."""
    img = P.new_img(12, 12)
    d = ImageDraw.Draw(img)
    d.rectangle(BODY, fill=body, outline=P.OUTLINE)
    for cx, cy in CORNERS:
        P.punch(d, [cx, cy, cx + 1, cy + 1])
    d.rectangle(BODY, outline=P.OUTLINE)  # aariviiva takaisin siisteytenä
    # Ylapaneelin kiiltoraita
    d.line([(2, 2), (9, 2)], fill=body_hi)
    # Lyhyet laskuteline-skidit, pistavat marginaaliin
    d.line([(3, 10), (2, 11)], fill=body_lo, width=1)
    d.line([(8, 10), (9, 11)], fill=body_lo, width=1)
    return img, d


def _eye(d, img, pulse: bool):
    """Hehkuva silmä/linssi: tumma soketti + amber-ydin. pulse=True -> kirkkaampi/isompi."""
    d.ellipse([4, 5, 7, 8], fill=P.OUTLINE)
    if pulse:
        d.ellipse([4, 5, 7, 8], fill=P.AMBER_HI)
        img.putpixel((5, 6), P.AMBER_HI)
    else:
        d.ellipse([5, 6, 6, 7], fill=P.AMBER)
        img.putpixel((5, 6), P.AMBER_HI)


def bot_miner(frame: int):
    """Miner-botti — amber runko + poranterä kyljessä (osoittaa alaviistoon)."""
    img, d = _bot_frame(P.MINER, P.MINER_HI, P.MINER_LO)
    pulse = frame == 1
    _eye(d, img, pulse)
    # Poranterä: ohut diagonaaliviiva botin oikeasta kyljesta alaviistoon kulmaan,
    # steel-sävy + hehkuva amber-karki. Frame 1: karkipikseli AMBER_HI (värinä).
    tip_col = P.AMBER_HI if pulse else P.AMBER
    P.px(img, (9, 7), P.OUTLINE)
    P.px(img, (10, 7), P.STEEL_HI)
    P.px(img, (10, 8), P.STEEL_HI)
    P.px(img, (11, 8), P.OUTLINE)
    P.px(img, (11, 9), tip_col)
    return img


def bot_hauler(frame: int):
    """Hauler-botti — sininen runko + rahtikontti selassa (steel-laatikko, amber-raita)."""
    img, d = _bot_frame(P.BLUE, P.BLUE_HI, P.BLUE_LO)
    pulse = frame == 1
    _eye(d, img, pulse)
    # Rahtikontti: steel-laatikko kontin paalla/takana, amber-raita keskella.
    d.rectangle([3, 0, 8, 3], fill=P.STEEL_LO, outline=P.OUTLINE)
    d.line([(3, 2), (8, 2)], fill=P.AMBER_HI if pulse else P.AMBER)
    img.putpixel((4, 1), P.STEEL_HI)
    img.putpixel((7, 1), P.STEEL_HI)
    return img


def main():
    print("Bots:")
    files = {
        "bot_miner_0.png": bot_miner(0),
        "bot_miner_1.png": bot_miner(1),
        "bot_hauler_0.png": bot_hauler(0),
        "bot_hauler_1.png": bot_hauler(1),
    }
    for name, img in files.items():
        P.save(img, OUT, name)

    entries = [
        {
            "name": "bot_miner",
            "w": 12,
            "h": 12,
            "frames": 2,
            "anchor": "center",
            "files": ["bot_miner_0.png", "bot_miner_1.png"],
            "role": "miner",
            "note": "amber drone + drill",
        },
        {
            "name": "bot_hauler",
            "w": 12,
            "h": 12,
            "frames": 2,
            "anchor": "center",
            "files": ["bot_hauler_0.png", "bot_hauler_1.png"],
            "role": "hauler",
            "note": "blue drone + cargo container",
        },
    ]
    P.write_manifest(OUT, entries)
    P.build_preview_sheet(OUT, list(files.keys()), "Bots preview")


if __name__ == "__main__":
    main()
