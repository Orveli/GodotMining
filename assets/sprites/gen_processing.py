"""
Prosessointikoneiden spritet (sulatusuuni, murskain, pora) — "Industrial Gothic Underground".

Korvaa STONE-varilliset placeholder-laatikot kunnon teollisilla spriteilla, tyyli
identtinen UI-ikonien ja muiden gen_*.py-generaattoreiden kanssa (ks. palette.py,
gen_base.py). Kaikki koot ovat tasmalleen footprintin kokoisia (1 sim-px = 1 px).

Aja projektin juuresta:

    python assets/sprites/gen_processing.py

HUOM pienimmille muodoille (esim. drill 4x6): jos suorakaiteen jompikumpi
sivu on <=2px, ImageDraw:n outline=-parametri syo koko muodon ääriviivaksi
(ei jää tilaa tayttovarille). Nailla kohdin kaytetaan pelkkaa fill=-tayttoa
+ kasin asetettuja P.px()-aariviivapikseleita.
"""

import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import palette as P
from PIL import ImageDraw

OUT = HERE


# ---------------------------------------------------------------------------
# furnace — sulatusuuni, 12x10, anchor topleft, 3 framea (hehkun kirkkaus)
# ---------------------------------------------------------------------------
def furnace_frame(level: int) -> "P.Image.Image":
    """Kivi/teras-runko, piippu oik. ylakulmassa, keski-intake, hehkuva suuaukko,
    output-chute alhaalla keskella. Runko identtinen joka framessa, level 0..2
    saatelee vain suuaukon hehkua ja kipinoita."""
    img = P.new_img(12, 10)
    d = ImageDraw.Draw(img)

    # Runko
    d.rectangle([0, 0, 11, 9], fill=P.STEEL_MID, outline=P.OUTLINE)

    # Piippu oikeassa ylakulmassa, kiinni runkoon
    d.rectangle([9, 0, 11, 2], fill=P.STEEL_MID, outline=P.OUTLINE)
    P.px(img, (10, 0), P.STEEL_HI)

    # Intake-aukko ylareunan keskella (6px) — tumma kita jonne hiekka putoaa
    d.rectangle([3, 0, 8, 3], fill=P.OUTLINE)

    # Kiiltopiste + tiiliviiva-aksentit sivuilla (ainoat vapaat kohdat intaken/piipun valissa)
    P.px(img, (1, 1), P.STEEL_HI)
    P.px(img, (2, 1), P.STEEL_HI)
    P.px(img, (1, 4), P.STEEL_LO)
    P.px(img, (10, 4), P.STEEL_LO)

    # Hehkuva suuaukko keskella alhaalla — tummareunainen bezeli + sisus levelin mukaan
    d.rectangle([3, 5, 8, 7], fill=P.OUTLINE)
    if level == 0:
        # Idle — himmea hiillos vain alarivilla
        d.rectangle([4, 7, 7, 7], fill=P.FIRE_LO)
    elif level == 1:
        d.rectangle([4, 6, 7, 7], fill=P.FIRE)
        P.px(img, (5, 6), P.FIRE_HI)
        P.px(img, (6, 6), P.FIRE_HI)
    else:
        d.rectangle([4, 6, 7, 7], fill=P.FIRE)
        P.px(img, (5, 6), P.FIRE_HI)
        P.px(img, (6, 6), P.FIRE_HI)
        P.px(img, (5, 7), P.FIRE_HI)
        P.px(img, (6, 7), P.FIRE_HI)
        # Kipinat karkaavat suuaukosta sivuille
        P.px(img, (2, 4), P.FIRE)
        P.px(img, (9, 4), P.FIRE_HI)

    # Varjoreuna alhaalla
    d.line([(1, 8), (10, 8)], fill=P.STEEL_LO)

    # Output-chute alareunan keskella (2px) — tumma aukko katkaisee varjoreunan
    d.rectangle([5, 8, 6, 9], fill=P.OUTLINE)

    return img


# ---------------------------------------------------------------------------
# crusher — murskain, 16x10, anchor topleft, 2 framea (leuat auki/kiinni)
# ---------------------------------------------------------------------------
def crusher_frame(bite: bool) -> "P.Image.Image":
    """Kotelo + vastakkaiset hammastetut leukalevyt, lomittuvat murskausraossa.
    Ylareunan keski-8px on intake-kita. bite=True -> hampaat lahella toisiaan (puraisu)."""
    img = P.new_img(16, 10)
    d = ImageDraw.Draw(img)

    # Kotelo
    d.rectangle([0, 0, 15, 9], fill=P.STEEL_LO, outline=P.OUTLINE)

    # Leukatangot — pelkka fill (2 riviä korkea, outline=-parametri soisi koko tangon)
    d.rectangle([1, 1, 14, 2], fill=P.STEEL_MID)   # ylaleuka
    d.rectangle([1, 7, 14, 8], fill=P.STEEL_HI)    # alaleuka

    if bite:
        # Kiinni — hampaat ojentuvat pidemmalle ja lomittuvat lahes koskettaen
        for tx in (3, 7, 11):
            d.rectangle([tx, 3, tx + 1, 4], fill=P.STEEL_MID)
        for tx in (5, 9, 13):
            d.rectangle([tx, 5, tx + 1, 6], fill=P.STEEL_HI)
        # Murskattu malmi raossa — pieni puristunut sirpale
        P.px(img, (8, 4), P.AMBER)
        P.px(img, (9, 5), P.AMBER_LO)
    else:
        # Auki — hampaat lyhyet, rako selvasti nakyvissa
        for tx in (3, 7, 11):
            d.rectangle([tx, 3, tx + 1, 3], fill=P.STEEL_MID)
        for tx in (5, 9, 13):
            d.rectangle([tx, 6, tx + 1, 6], fill=P.STEEL_HI)
        # Ehja malmimurunen roikkuu avoimessa raossa
        d.rectangle([7, 4, 9, 5], fill=P.AMBER)
        P.px(img, (8, 4), P.AMBER_HI)

    # Intake ylareunan keskella (8px) — tumma kita, piirretaan viimeiseksi jotta
    # katkaisee seka kotelon ylareunan etta ylaleuan siististi
    d.rectangle([4, 0, 11, 1], fill=P.OUTLINE)

    return img


# ---------------------------------------------------------------------------
# drill — pora, 4x6, anchor topleft, 3 framea (teran varina/pyorinta)
# ---------------------------------------------------------------------------
def drill_frame(idx: int) -> "P.Image.Image":
    """Teraskotelo ylhaalla + kapeneva amber-teraa alaspain, karki edella. Vain
    24px kaytettavissa -> kasin pikseli kerrallaan. idx 0..2 vaihtaa teran
    kierreraidoituksen puolta + karkipikselin sivua (varina/pyorinta-illuusio)."""
    img = P.new_img(4, 6)
    d = ImageDraw.Draw(img)

    # Kotelo ylhaalla (2 riviä) — pelkka fill + kasin aariviiva (korkeus liian
    # pieni outline=-parametrille)
    d.rectangle([0, 0, 3, 1], fill=P.STEEL_MID)
    for x in range(4):
        P.px(img, (x, 0), P.OUTLINE)
    P.px(img, (0, 1), P.OUTLINE)
    P.px(img, (3, 1), P.OUTLINE)
    P.px(img, (1, 0), P.STEEL_HI)  # kiiltopiste

    # Amber teraa, kapenee alaspain. Vuorotteleva outline/amber-raidoitus
    # kierteen kahden riviin mahtuen, karkipikseli vaihtaa puolta framen mukaan.
    if idx == 0:
        P.px(img, (1, 2), P.OUTLINE); P.px(img, (2, 2), P.AMBER)
        P.px(img, (1, 3), P.AMBER);   P.px(img, (2, 3), P.OUTLINE)
        P.px(img, (1, 4), P.AMBER);   P.px(img, (2, 4), P.AMBER)
        P.px(img, (1, 5), P.AMBER_HI)
    elif idx == 1:
        P.px(img, (1, 2), P.AMBER);   P.px(img, (2, 2), P.OUTLINE)
        P.px(img, (1, 3), P.OUTLINE); P.px(img, (2, 3), P.AMBER)
        P.px(img, (1, 4), P.AMBER);   P.px(img, (2, 4), P.AMBER)
        P.px(img, (2, 5), P.AMBER_HI)
    else:
        P.px(img, (1, 2), P.AMBER);   P.px(img, (2, 2), P.AMBER)
        P.px(img, (1, 3), P.AMBER);   P.px(img, (2, 3), P.AMBER)
        P.px(img, (1, 4), P.AMBER_HI); P.px(img, (2, 4), P.AMBER_HI)
        P.px(img, (1, 5), P.AMBER_HI)

    return img


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    print("Furnace / crusher / drill:")

    P.save(furnace_frame(0), OUT, "furnace_0.png")
    P.save(furnace_frame(1), OUT, "furnace_1.png")
    P.save(furnace_frame(2), OUT, "furnace_2.png")

    P.save(crusher_frame(False), OUT, "crusher_0.png")
    P.save(crusher_frame(True), OUT, "crusher_1.png")

    P.save(drill_frame(0), OUT, "drill_0.png")
    P.save(drill_frame(1), OUT, "drill_1.png")
    P.save(drill_frame(2), OUT, "drill_2.png")

    entries = [
        {
            "name": "furnace", "w": 12, "h": 10, "frames": 3, "anchor": "topleft",
            "files": ["furnace_0.png", "furnace_1.png", "furnace_2.png"],
            "role": "anim_glow", "note": "idle=frame0, smelting cycles 0..2",
        },
        {
            "name": "crusher", "w": 16, "h": 10, "frames": 2, "anchor": "topleft",
            "files": ["crusher_0.png", "crusher_1.png"],
            "role": "anim_jaws", "note": "0=jaws open, 1=jaws closed/bite",
        },
        {
            "name": "drill", "w": 4, "h": 6, "frames": 3, "anchor": "topleft",
            "files": ["drill_0.png", "drill_1.png", "drill_2.png"],
            "role": "anim_spin", "note": "bit shimmer/rotation cycle 0..2",
        },
    ]
    P.write_manifest(OUT, entries)

    P.build_preview_sheet(
        OUT,
        [
            "furnace_0.png", "furnace_1.png", "furnace_2.png",
            "crusher_0.png", "crusher_1.png",
            "drill_0.png", "drill_1.png", "drill_2.png",
        ],
        "Processing preview",
    )


if __name__ == "__main__":
    main()
