"""
Base-, myyntipiste-, moduuli- ja latauspaikka-spritet — "Industrial Gothic Underground".

Korvaa pelkat STONE-varilliset kivilaatikot kunnon teollisilla spriteilla, tyyli
identtinen UI-ikonien ja muiden gen_*.py-generaattoreiden kanssa (ks. palette.py).

Aja projektin juuresta:

    python assets/sprites/gen_base.py
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import palette as P
from PIL import ImageDraw

OUT = HERE


# ---------------------------------------------------------------------------
# base — seed ship -tukikohta (emalaivan hub), 12x10, anchor topleft
# ---------------------------------------------------------------------------
def base_frame(bright: bool) -> "P.Image.Image":
    """Teollinen teraspaneeli-bunkkeri, ylareunan keski intake-kita, amber-ydin."""
    img = P.new_img(12, 10)
    d = ImageDraw.Draw(img)

    # Runko: teraspaneeli taysine aariviivoineen
    d.rectangle([0, 0, 11, 9], fill=P.STEEL_MID, outline=P.OUTLINE)
    # Kiiltoreuna ylhaalla
    d.rectangle([1, 1, 10, 2], fill=P.STEEL_HI)
    # Varjoreuna alhaalla
    d.line([(1, 8), (10, 8)], fill=P.STEEL_LO)

    # Intake-aukko ylareunan keskella — tumma kita
    d.rectangle([4, 0, 7, 3], fill=P.OUTLINE)

    # Ydinreaktori keskella, intaken alla
    if bright:
        d.ellipse([4, 4, 7, 7], fill=P.AMBER, outline=P.OUTLINE)
        d.ellipse([5, 5, 6, 6], fill=P.AMBER_HI)
        # Hehkun vuoto viereisiin paneeleihin
        P.px(img, (3, 5), P.AMBER_LO)
        P.px(img, (8, 5), P.AMBER_LO)
    else:
        d.ellipse([4, 4, 7, 7], fill=P.AMBER_LO, outline=P.OUTLINE)
        d.ellipse([5, 5, 6, 6], fill=P.AMBER)

    # Paneelisaumat sivuilla
    P.px(img, (1, 5), P.STEEL_LO)
    P.px(img, (10, 5), P.STEEL_LO)

    return img


# ---------------------------------------------------------------------------
# money_exit — myyntipiste, 12x10, anchor topleft (kulta-teema)
# ---------------------------------------------------------------------------
def money_exit_frame(bright: bool) -> "P.Image.Image":
    """Sama bunkkerirunko kuin base, mutta kulta-teemainen myyntiluukku + kolikkoydin."""
    img = P.new_img(12, 10)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, 11, 9], fill=P.STEEL_MID, outline=P.OUTLINE)
    d.rectangle([1, 1, 10, 2], fill=P.STEEL_HI)
    d.line([(1, 8), (10, 8)], fill=P.STEEL_LO)

    # Myyntiluukku ylareunan keskella — hehkuva kultarako (erottaa basesta)
    d.rectangle([4, 0, 7, 3], fill=P.OUTLINE)
    d.rectangle([5, 1, 6, 2], fill=P.GOLD if bright else P.GOLD_LO)

    # Kolikkoydin keskella
    if bright:
        d.ellipse([4, 4, 7, 7], fill=P.GOLD, outline=P.OUTLINE)
        d.ellipse([5, 5, 6, 6], fill=P.GOLD_HI)
        P.px(img, (4, 4), P.GOLD_HI)  # kimallepiste (kolikkomotiivi)
        P.px(img, (8, 5), P.GOLD_LO)
    else:
        d.ellipse([4, 4, 7, 7], fill=P.GOLD_LO, outline=P.OUTLINE)
        d.ellipse([5, 5, 6, 6], fill=P.GOLD)

    P.px(img, (1, 5), P.STEEL_LO)
    P.px(img, (10, 5), P.STEEL_LO)

    return img


# ---------------------------------------------------------------------------
# base_module — laajennusmoduuli, 8x8, anchor topleft, 1 frame
# ---------------------------------------------------------------------------
def base_module_frame() -> "P.Image.Image":
    """Kompakti teraspaneeli + amber-liitantanoodi keskella."""
    img = P.new_img(8, 8)
    d = ImageDraw.Draw(img)

    d.rectangle([0, 0, 7, 7], fill=P.STEEL_MID, outline=P.OUTLINE)
    d.rectangle([1, 1, 6, 2], fill=P.STEEL_HI)
    d.line([(1, 6), (6, 6)], fill=P.STEEL_LO)

    d.ellipse([2, 3, 5, 6], fill=P.AMBER, outline=P.OUTLINE)
    P.px(img, (3, 4), P.AMBER_HI)

    return img


# ---------------------------------------------------------------------------
# charger_pad — botin latauspaikka, 7x7, anchor center, 3 frames (latauspulssi)
# ---------------------------------------------------------------------------
def charger_pad_frame(level: int) -> "P.Image.Image":
    """Teraslaituri + pylvas + hehkuva amber-latausnoodi. level 0..2 = hehkun kirkkaus.

    7x7 on liian pieni PIL:n rectangle(fill+outline)/ellipse-avustimille (aariviiva
    syo koko taytteen alle 3px laatikoissa, pieni ellipsi jaa harvaksi pistekuvioksi)
    -> koko sprite pikseli kerrallaan taman kokoluokan tarkkuuden takaamiseksi.
    """
    img = P.new_img(7, 7)

    # Laituri (pohja): kiiltorivi + varjorivi, aariviiva vain paatypaissa
    for x in range(1, 6):
        P.px(img, (x, 5), P.STEEL_HI)
        P.px(img, (x, 6), P.STEEL_LO)
    for x in (0, 6):
        P.px(img, (x, 5), P.OUTLINE)
        P.px(img, (x, 6), P.OUTLINE)

    # Pylvas laiturin ja noodin valissa
    for y in (3, 4):
        P.px(img, (2, y), P.OUTLINE)
        P.px(img, (3, y), P.STEEL_LO)
        P.px(img, (4, y), P.OUTLINE)

    # Noodin kaula
    P.px(img, (2, 2), P.OUTLINE)
    P.px(img, (4, 2), P.OUTLINE)

    # Latausnoodi (orbi) ylhaalla — kirkastuu ja levenee levelin mukaan
    if level == 0:
        P.px(img, (3, 2), P.AMBER_LO)
        P.px(img, (3, 1), P.AMBER_LO)
        P.px(img, (2, 1), P.OUTLINE)
        P.px(img, (4, 1), P.OUTLINE)
    elif level == 1:
        P.px(img, (3, 2), P.AMBER)
        P.px(img, (2, 1), P.OUTLINE)
        P.px(img, (3, 1), P.AMBER_HI)
        P.px(img, (4, 1), P.OUTLINE)
        P.px(img, (3, 0), P.AMBER)
    else:
        P.px(img, (3, 2), P.AMBER)
        P.px(img, (1, 1), P.AMBER_LO)
        P.px(img, (2, 1), P.OUTLINE)
        P.px(img, (3, 1), P.AMBER_HI)
        P.px(img, (4, 1), P.OUTLINE)
        P.px(img, (5, 1), P.AMBER_LO)
        P.px(img, (2, 0), P.AMBER_LO)
        P.px(img, (3, 0), P.AMBER_HI)
        P.px(img, (4, 0), P.AMBER_LO)

    return img


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Base / money_exit / base_module / charger_pad:")

    P.save(base_frame(False), OUT, "base_0.png")
    P.save(base_frame(True), OUT, "base_1.png")

    P.save(money_exit_frame(False), OUT, "money_exit_0.png")
    P.save(money_exit_frame(True), OUT, "money_exit_1.png")

    P.save(base_module_frame(), OUT, "base_module.png")

    P.save(charger_pad_frame(0), OUT, "charger_pad_0.png")
    P.save(charger_pad_frame(1), OUT, "charger_pad_1.png")
    P.save(charger_pad_frame(2), OUT, "charger_pad_2.png")

    entries = [
        {
            "name": "base", "w": 12, "h": 10, "frames": 2, "anchor": "topleft",
            "files": ["base_0.png", "base_1.png"],
            "role": "anim_pulse", "note": "ship hub, amber core",
        },
        {
            "name": "money_exit", "w": 12, "h": 10, "frames": 2, "anchor": "topleft",
            "files": ["money_exit_0.png", "money_exit_1.png"],
            "role": "anim_pulse", "note": "sell point, gold core",
        },
        {
            "name": "base_module", "w": 8, "h": 8, "frames": 1, "anchor": "topleft",
            "files": ["base_module.png"],
            "role": "static", "note": "expansion module, amber connector node",
        },
        {
            "name": "charger_pad", "w": 7, "h": 7, "frames": 3, "anchor": "center",
            "files": ["charger_pad_0.png", "charger_pad_1.png", "charger_pad_2.png"],
            "role": "anim_pulse", "note": "bot charging dock, brightens per frame",
        },
    ]
    P.write_manifest(OUT, entries)

    P.build_preview_sheet(
        OUT,
        [
            "base_0.png", "base_1.png",
            "money_exit_0.png", "money_exit_1.png",
            "base_module.png",
            "charger_pad_0.png", "charger_pad_1.png", "charger_pad_2.png",
        ],
        "Base preview",
    )


if __name__ == "__main__":
    main()
