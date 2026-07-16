"""
Sovellusikonin generaattori — GodotMining demo-build.

Piirtää 32x32 pikseliruudukolle kultaisen, fasetoidun timantin/jalokiven
tummalle kivitaustalle (amber-hehku), ja skaalaa sen NEAREST-menetelmällä
teraviksi tuotoksiksi:

    assets/icon.png   256x256  (Godotin config/icon)
    assets/icon.ico   Windows .exe -ikoni (16..256)

Tyyli mukailee assets/ui/gen_ui_assets.py:tä — Industrial Gothic Underground:
tumma kivi, lammin amber-aksentti, 1px tumma aariviiva, ei anti-aliasointia.

Aja projektin juuresta:

    python assets/gen_app_icon.py
"""

from PIL import Image, ImageDraw
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_PNG = os.path.join(HERE, "icon.png")
OUT_ICO = os.path.join(HERE, "icon.ico")

# ---------------------------------------------------------------------------
# Paletti — sama sielu kuin gen_ui_assets.py:ssa
# ---------------------------------------------------------------------------
OUTLINE   = (26, 20, 16, 255)      # tumma aariviiva
STONE_BG  = (20, 18, 16, 255)      # taustan pohjasavy
STONE_BG2 = (34, 29, 24, 255)      # taustan lampimampi savy
STONE_HI  = (56, 48, 40, 255)      # taustan valopilkku
AMBER     = (217, 138, 58, 255)    # aksentti/reunus
AMBER_HI  = (240, 176, 100, 255)   # amber, vaalea kiilto
AMBER_LO  = (150, 92, 34, 255)     # amber, tumma varjo
GOLD      = (230, 199, 50, 255)    # kulta
GOLD_HI   = (250, 226, 130, 255)   # kullan kiilto
GOLD_LO   = (168, 132, 24, 255)    # kullan varjo
GOLD_DK   = (120, 92, 18, 255)     # kullan syvin varjo (pavilion)
WHITE     = (255, 248, 224, 255)   # kirkkain sadepikseli
TRANSP    = (0, 0, 0, 0)

BASE = 32
SCALE = 8  # 32 * 8 = 256


def draw_background(d: ImageDraw.ImageDraw, img: Image.Image) -> None:
    """Pyoristetty kivitausta amber-kehyksella."""
    # Pohja
    d.rectangle([0, 0, BASE - 1, BASE - 1], fill=STONE_BG2)
    # Kevyt pystysuuntainen valo-gradientti (ylhaalla vaaleampi kivi)
    for y in range(BASE):
        t = y / (BASE - 1)
        r = int(STONE_BG2[0] * (1 - t) + STONE_BG[0] * t)
        g = int(STONE_BG2[1] * (1 - t) + STONE_BG[1] * t)
        b = int(STONE_BG2[2] * (1 - t) + STONE_BG[2] * t)
        d.line([(0, y), (BASE - 1, y)], fill=(r, g, b, 255))
    # Muutama kivipilkku pintaan
    for px in [(5, 6), (26, 8), (7, 25), (24, 24), (14, 4), (18, 27)]:
        img.putpixel(px, STONE_HI)
    # Reunakehys: tumma aariviiva + amber-sisaviiva
    d.rectangle([0, 0, BASE - 1, BASE - 1], outline=OUTLINE, width=1)
    d.rectangle([2, 2, BASE - 3, BASE - 3], outline=AMBER_LO, width=1)
    # Pyoristetyt kulmat: leikkaa lapinakyvat kulmapikselit
    for cx, cy in [(0, 0), (BASE - 1, 0), (0, BASE - 1), (BASE - 1, BASE - 1)]:
        img.putpixel((cx, cy), TRANSP)
    # Toisen kerroksen kulmapehmennys
    for cx, cy in [(0, 0), (BASE - 1, 0), (0, BASE - 1), (BASE - 1, BASE - 1)]:
        pass


def draw_glow(d: ImageDraw.ImageDraw) -> None:
    """Pehmea amber-hehku timantin takana (muutama laajeneva timanttikaari)."""
    cx, cy = 16, 16
    for rad, col in [(13, (60, 40, 20, 255)), (11, (86, 56, 26, 255)),
                     (9, (110, 72, 32, 255))]:
        d.polygon(
            [(cx, cy - rad), (cx + rad, cy), (cx, cy + rad), (cx - rad, cy)],
            fill=col,
        )


def draw_gem(d: ImageDraw.ImageDraw, img: Image.Image) -> None:
    """Fasetoitu kultatimantti: kruunu (ylaosa) + pavilion (karki alas)."""
    # Avainpisteet (x, y) — keskitetty x=16
    tbl_l = (12, 9)    # poydan (table) vasen ylakulma
    tbl_r = (20, 9)    # poydan oikea ylakulma
    gir_l = (6, 15)    # girdle vasen (levein kohta)
    gir_r = (26, 15)   # girdle oikea
    gir_ml = (11, 15)  # girdle vasen sisapiste
    gir_mr = (21, 15)  # girdle oikea sisapiste
    tip = (16, 27)     # pavilionin karki

    # --- Koko timantin pohjatayttely ---
    gem = [tbl_l, tbl_r, gir_r, tip, gir_l]
    d.polygon(gem, fill=GOLD)

    # --- Kruunun fasetit ---
    # Poyta (table) — kirkkain
    d.polygon([tbl_l, tbl_r, gir_mr, gir_ml], fill=GOLD_HI)
    # Vasen kruunufasetti
    d.polygon([tbl_l, gir_ml, gir_l], fill=GOLD)
    # Oikea kruunufasetti — varjo
    d.polygon([tbl_r, gir_r, gir_mr], fill=GOLD_LO)

    # --- Pavilionin fasetit (karkeen supistuvat kolmiot) ---
    # Vasen pavilion
    d.polygon([gir_l, gir_ml, tip], fill=GOLD)
    # Keskivasen
    d.polygon([gir_ml, (16, 15), tip], fill=GOLD_HI)
    # Keskioikea
    d.polygon([(16, 15), gir_mr, tip], fill=GOLD_LO)
    # Oikea pavilion — syvin varjo
    d.polygon([gir_mr, gir_r, tip], fill=GOLD_DK)

    # --- Fasettiviivat (tummat rajat) ---
    d.line([tbl_l, gir_l], fill=OUTLINE)
    d.line([tbl_r, gir_r], fill=OUTLINE)
    d.line([gir_l, gir_r], fill=OUTLINE)      # girdle-viiva
    d.line([gir_ml, tip], fill=OUTLINE)
    d.line([gir_mr, tip], fill=OUTLINE)
    d.line([(16, 15), tip], fill=OUTLINE)     # keskiharja
    d.line([tbl_l, gir_ml], fill=OUTLINE)
    d.line([tbl_r, gir_mr], fill=OUTLINE)

    # --- Ulkoaariviiva ---
    d.polygon(gem, outline=OUTLINE)

    # --- Kiilto & sadepikselit ---
    img.putpixel((14, 10), WHITE)
    img.putpixel((15, 10), GOLD_HI)
    img.putpixel((13, 12), GOLD_HI)
    # Pieni tahtisade poydan vasemmalla puolella
    d.line([(9, 6), (9, 8)], fill=AMBER_HI)
    d.line([(8, 7), (10, 7)], fill=AMBER_HI)
    img.putpixel((9, 7), WHITE)


def build_base() -> Image.Image:
    img = Image.new("RGBA", (BASE, BASE), TRANSP)
    d = ImageDraw.Draw(img)
    draw_background(d, img)
    draw_glow(d)
    draw_gem(d, img)
    return img


def main() -> None:
    base = build_base()

    # 256x256 terava pikselipng
    big = base.resize((BASE * SCALE, BASE * SCALE), Image.NEAREST)
    big.save(OUT_PNG)
    print(f"  {os.path.relpath(OUT_PNG, HERE)}  {big.size[0]}x{big.size[1]}")

    # Windows .ico — useita kokoja. Divisiblet NEAREST (terava), muut LANCZOS.
    ico_sizes = [256, 128, 64, 48, 32, 16]
    frames = []
    for s in ico_sizes:
        if s % BASE == 0:
            frames.append(base.resize((s, s), Image.NEAREST))
        else:
            # 48px: skaalaa 256-masterista pehmeasti
            frames.append(big.resize((s, s), Image.LANCZOS))
    frames[0].save(OUT_ICO, format="ICO",
                   sizes=[(f.size[0], f.size[1]) for f in frames])
    print(f"  {os.path.relpath(OUT_ICO, HERE)}  sizes={ico_sizes}")


if __name__ == "__main__":
    main()
