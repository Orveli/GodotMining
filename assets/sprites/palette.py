"""
Jaettu paletti + piirtoapurit pelimaailman spriteille — "Industrial Gothic Underground".

Kaikki gen_*.py-spritegeneraattorit (gen_bots.py, gen_processing.py, gen_base.py)
importtaavat TAMAN moduulin, jotta paletti, aariviiva ja apurit ovat identtiset ->
yhtenainen tyyli riippumatta siita mika agentti sprite-erän teki.

Tyyli (sama kuin assets/ui/gen_ui_assets.py):
  - tumma kivi/metalli, lampin amber-aksentti
  - 1px tumma aariviiva (#1a1410), EI anti-aliasointia
  - luettava natiiviresoluutiossa (sprite = footprintin kokoinen, 1 sim-px = 1 px)

Hauler-botit kayttavat teraksensinista perhetta (pelin roolivari), minerit amberia.
"""

from PIL import Image, ImageDraw
import os
import json

# ---------------------------------------------------------------------------
# Paletti — Industrial Gothic Underground (identtinen UI-ikonien kanssa)
# ---------------------------------------------------------------------------
OUTLINE    = (26, 20, 16, 255)     # #1a1410 — tumma aariviiva
STONE_BG   = (20, 20, 20, 255)     # #141414
STONE_BG2  = (30, 26, 22, 255)     # #1e1a16 (lampimampi)
STEEL_HI   = (140, 140, 133, 255)  # #8c8c85 — metalli, vaalea
STEEL_MID  = (107, 96, 85, 255)    # #6b6055 — metalli/kivi, keskisavy
STEEL_LO   = (66, 58, 50, 255)     # tumma metalli/varjo
AMBER      = (217, 138, 58, 255)   # #d98a3a — aksentti/reunus
AMBER_HI   = (240, 176, 100, 255)  # amber, vaalea kiilto
AMBER_LO   = (150, 92, 34, 255)    # amber, tumma varjo
FIRE       = (255, 128, 32, 255)   # #ff8020 — hehku/tuli
FIRE_HI    = (255, 196, 120, 255)  # tulen kirkkain kohta
FIRE_LO    = (196, 72, 16, 255)    # tulen tumma reuna
GOLD       = (230, 199, 50, 255)   # #e6c732 — raha/kulta
GOLD_HI    = (250, 226, 130, 255)
GOLD_LO    = (168, 132, 24, 255)

# Hauler-roolivari — teraksensininen (pelin bot_manager.gd sininen: 0.35,0.62,0.95)
BLUE       = (89, 158, 242, 255)   # rungon perusvari
BLUE_HI    = (150, 200, 255, 255)  # kiilto
BLUE_LO    = (44, 96, 168, 255)    # varjo

# Miner-roolivari — lampin amber (bot_manager.gd: 0.88,0.66,0.25)
MINER      = (224, 168, 64, 255)
MINER_HI   = (250, 206, 120, 255)
MINER_LO   = (150, 100, 34, 255)

TRANSP     = (0, 0, 0, 0)


# ---------------------------------------------------------------------------
# Piirtoapurit
# ---------------------------------------------------------------------------
def new_img(w, h):
    """Laapinakyva RGBA-kangas footprintin kokoisena."""
    return Image.new("RGBA", (w, h), TRANSP)


def oline(draw, xy, fill, width=1, outline=OUTLINE, ow=None):
    """Viiva tumman aariviivan paalla (kaksinkertainen line)."""
    if ow is None:
        ow = width + 2
    draw.line(xy, fill=outline, width=ow)
    draw.line(xy, fill=fill, width=width)


def punch(draw, box):
    """'Leikkaa' laapinakyvan reian (RGBA-piirto ei alpha-blendaa)."""
    draw.rectangle(box, fill=TRANSP)


def px(img, xy, col):
    """Turvallinen putpixel (ei kaadu jos ulkona rajoista)."""
    if 0 <= xy[0] < img.size[0] and 0 <= xy[1] < img.size[1]:
        img.putpixel(xy, col)


def save(img, out_dir, name):
    path = os.path.join(out_dir, name)
    img.save(path)
    print(f"  {name}  {img.size[0]}x{img.size[1]}")
    return path


def write_manifest(out_dir, entries):
    """
    entries: lista dicteja { "name","w","h","frames","anchor","note" }.
    Kirjoittaa manifest.json:n jonka programmer lukee kytkennan sopimukseksi.
    anchor: "topleft" (rakennus, piirretaan grid_pos:iin) tai "center" (botti).
    """
    path = os.path.join(out_dir, "manifest.json")
    # Yhdista olemassa olevaan (usea generaattori taydentaa samaa manifestia)
    existing = []
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                existing = json.load(f).get("sprites", [])
        except Exception:
            existing = []
    by_name = {e["name"]: e for e in existing}
    for e in entries:
        by_name[e["name"]] = e
    merged = sorted(by_name.values(), key=lambda e: e["name"])
    with open(path, "w", encoding="utf-8") as f:
        json.dump({"sprites": merged}, f, indent=2, ensure_ascii=True)
    print(f"  manifest.json  ({len(merged)} sprites)")


def build_preview_sheet(out_dir, png_names, title, scale=6, cols=6):
    """Kontaktivedos: kaikki annetut PNG:t skaalattuna nimilapuilla. Vain katselmointi."""
    from PIL import ImageFont
    cell_w, cell_h = 20 * scale + 16, 20 * scale + 26
    rows = -(-len(png_names) // cols)
    sheet = Image.new("RGBA", (cols * cell_w + 20, rows * cell_h + 40), STONE_BG)
    d = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.load_default()
    except Exception:
        font = None
    d.text((10, 10), title, fill=AMBER_HI, font=font)
    for i, name in enumerate(png_names):
        col, row = i % cols, i // cols
        x, y = 10 + col * cell_w, 30 + row * cell_h
        icon = Image.open(os.path.join(out_dir, name)).convert("RGBA")
        big = icon.resize((icon.width * scale, icon.height * scale), Image.NEAREST)
        d.rectangle([x, y, x + cell_w - 10, y + cell_h - 12], outline=STEEL_LO)
        sheet.alpha_composite(big, (x + (cell_w - 10 - big.width) // 2, y + 6))
        d.text((x + 4, y + cell_h - 22), name, fill=STEEL_HI, font=font)
    path = os.path.join(out_dir, "preview_" + title.split()[0].lower() + ".png")
    sheet.save(path)
    print(f"  {os.path.basename(path)}")
    return path
