"""
Bunny idle-animaatio — 4 framea, 64x64, RGBA
Hienovarainen: hengitysliike + korvan liike

Kerroksittainen hybridi:
  Vaihe 1: Paletti
  Vaihe 2: Muodot (ImageDraw)
  Vaihe 3: Yksityiskohdat (putpixel)
"""

from PIL import Image, ImageDraw

# ─── Vaihe 1: Paletti ─────────────────────────────────────────────────────────
outline      = (30, 18, 28, 255)     # tumma ääriviiva
body_hi      = (252, 250, 252, 255)  # vaalea pääväri
body_mid     = (235, 230, 238, 255)  # vartalon perusväri
body_shd     = (210, 200, 218, 255)  # varjo
body_dark    = (185, 175, 196, 255)  # syvä varjo
ear_out      = (255, 158, 180, 255)  # korvan sisäosa kirkas pinkki
ear_mid      = (240, 130, 160, 255)  # korvan sisäosa mid
ear_in       = (220, 100, 135, 255)  # korvan sisäosa tumma
eye_col      = (25, 18, 30, 255)     # silmä
eye_hi       = (120, 110, 160, 255)  # silmän heijastus
nose_col     = (200, 80, 120, 255)   # nenä pinkki
tail_col     = (245, 242, 248, 255)  # häntä vaalea
CLEAR        = (0, 0, 0, 0)


def draw_frame(ear_r_drop: int, ear_l_drop: int, body_y: int, label: str) -> Image.Image:
    """
    Piirrä yksi idle-frame.

    ear_r_drop — oikean korvan kärki laskee n pikseliä (0 = pystyssä)
    ear_l_drop — vasemman korvan kärki laskee n pikseliä
    body_y     — vartalon y-offset (0 tai 1, hengitysliike)
    label      — debug-nimi

    Hahmo on 3/4-sivuprofiili, katsoo oikealle.
    Koordinaatistosta: vasen=0, oikea=63, ylös=0, alas=63
    """
    img = Image.new("RGBA", (64, 64), CLEAR)
    d = ImageDraw.Draw(img)

    # ── Häntä (vasemmalla takana, piirretään ensin) ───────────────────────────
    tail_cx, tail_cy = 13, 42 + body_y
    d.ellipse([tail_cx - 6, tail_cy - 5, tail_cx + 6, tail_cy + 5],
              fill=tail_col, outline=outline)
    # häntä highlight
    img.putpixel((13, 39 + body_y), body_hi)
    img.putpixel((14, 40 + body_y), body_hi)

    # ── Takajalan kontuur (piirretään vartalon alle) ──────────────────────────
    rfoot_y = 52 + body_y
    d.ellipse([14, rfoot_y, 26, rfoot_y + 7], fill=body_shd, outline=outline)

    # ── Vartalo ───────────────────────────────────────────────────────────────
    # Muoto: vaakasuunnassa pitkähkö ellipsi, hivenen oikealle painottunut
    bx1, by1, bx2, by2 = 16, 34 + body_y, 50, 54 + body_y
    # Syvä varjo (oikea reunapuoli)
    d.ellipse([bx1 + 4, by1 + 4, bx2 + 1, by2 + 1], fill=body_dark)
    # Perusellipsi
    d.ellipse([bx1, by1, bx2, by2], fill=body_mid, outline=outline)
    # Yläosa highlight (vaaleampi alue vasemmassa yläkulmassa)
    d.ellipse([bx1 + 2, by1 + 2, bx1 + 18, by1 + 10], fill=body_hi)
    # Alavarijokaari
    d.arc([bx1 + 1, by2 - 8, bx2 - 1, by2 + 2], 10, 170, fill=body_dark, width=2)

    # ── Etujalat ──────────────────────────────────────────────────────────────
    ffoot_y = 52 + body_y
    # Etummainen jalka (oikealla)
    d.ellipse([36, ffoot_y, 52, ffoot_y + 7], fill=body_mid, outline=outline)
    # Toinen etujalka (hieman vasemmalla)
    d.ellipse([28, ffoot_y - 1, 43, ffoot_y + 6], fill=body_shd, outline=outline)

    # ── Kaularakenteen yhdistävä ellipsi ─────────────────────────────────────
    neck_y = 30 + body_y
    d.ellipse([30, neck_y, 46, neck_y + 14], fill=body_mid)

    # ── Pää ───────────────────────────────────────────────────────────────────
    # Pyöreähkö pää, hivenen oikealle (kuono suuntautuu oikealle)
    hx1, hy1, hx2, hy2 = 26, 16 + body_y, 54, 40 + body_y
    # Pään varjopuoli (vasen)
    d.ellipse([hx1 + 2, hy1 + 2, hx2, hy2 + 1], fill=body_shd)
    # Pää pääellipsi
    d.ellipse([hx1, hy1, hx2, hy2], fill=body_mid, outline=outline)
    # Pään highlight (vasen yläkulma)
    d.ellipse([hx1 + 3, hy1 + 3, hx1 + 15, hy1 + 12], fill=body_hi)
    # Posken pyöristys kuonon kohdalla (oikea reuna)
    d.ellipse([hx2 - 8, hy1 + 8, hx2 + 4, hy2 - 6], fill=body_mid)

    # ── Korvat ────────────────────────────────────────────────────────────────
    # Piirretään korvat ennen pääellipsiä jotta ne jäävät taustalle — EI,
    # piirretään ensin, sitten pää päälle -> korvat kasvavat pään päältä.
    # Täytyy piirtää korvat uudelleen pään päälle. Ennen piirtoa lisätään
    # korvat uudestaan (ne ovat pään taustalla vain tyvestä).

    # Oikea korva (kauempana — taaempi)
    rx_c = 34  # korvan x-keskikohta pään päällä
    ry_base = hy1 + 3 + body_y
    ry_tip  = hy1 - 14 + ear_r_drop + body_y
    d.polygon([
        (rx_c - 4, ry_base + 4),
        (rx_c + 4, ry_base + 4),
        (rx_c + 3, ry_tip + 1),
        (rx_c - 2, ry_tip),
    ], fill=body_shd, outline=outline)
    # Korvan sisäpinkki (pienempi)
    d.polygon([
        (rx_c - 2, ry_base + 2),
        (rx_c + 2, ry_base + 2),
        (rx_c + 1, ry_tip + 4),
        (rx_c - 1, ry_tip + 4),
    ], fill=ear_in)

    # Vasen korva (lähempänä — etummainen)
    lx_c = 42  # oikeammalla kuin taaempi korva
    ly_base = hy1 + 3 + body_y
    ly_tip  = hy1 - 16 + ear_l_drop + body_y
    d.polygon([
        (lx_c - 4, ly_base + 4),
        (lx_c + 4, ly_base + 4),
        (lx_c + 2, ly_tip + 1),
        (lx_c - 3, ly_tip),
    ], fill=body_mid, outline=outline)
    # Korvan sisäpinkki
    d.polygon([
        (lx_c - 2, ly_base + 2),
        (lx_c + 2, ly_base + 2),
        (lx_c + 1, ly_tip + 4),
        (lx_c - 1, ly_tip + 4),
    ], fill=ear_mid)

    # ─── Vaihe 3: Yksityiskohdat (putpixel) ───────────────────────────────────
    # Silmä — pään etupuolella, 3/4-profiilin mukaisesti
    ey = 24 + body_y
    ex = 46  # siirretty vasemmalle jotta näkyy selkeästi
    # 2x2 tumma silmäpiste
    img.putpixel((ex,     ey),     eye_col)
    img.putpixel((ex + 1, ey),     eye_col)
    img.putpixel((ex,     ey + 1), eye_col)
    img.putpixel((ex + 1, ey + 1), eye_col)
    # Silmän vaalea heijastus (oikeassa yläkulmassa)
    img.putpixel((ex + 2, ey),     eye_hi)
    # Silmän ympärys — tumma reunapiste ylä+ala
    img.putpixel((ex,     ey - 1), outline)
    img.putpixel((ex + 1, ey - 1), outline)

    # Nenä — kuonon kärki (oikealla)
    img.putpixel((52, ey + 8),  nose_col)
    img.putpixel((53, ey + 8),  nose_col)
    img.putpixel((52, ey + 9),  nose_col)
    img.putpixel((53, ey + 9),  nose_col)

    # Suu — pieni V-muoto nenän alla
    img.putpixel((51, ey + 10), outline)
    img.putpixel((52, ey + 11), outline)
    img.putpixel((53, ey + 10), outline)

    # Korvien juuressa varjopikseleita pään päällä
    img.putpixel((rx_c, hy1 + body_y + 1), body_shd)
    img.putpixel((lx_c, hy1 + body_y + 1), body_shd)

    # Vatsan varjokaari — pohja tummempi
    for px in range(bx1 + 4, bx2 - 3):
        img.putpixel((px, by2 - 1), body_dark)
    # Vatsaan pieni vaaleus (yläreunan highlight)
    for px in range(bx1 + 3, bx1 + 12):
        img.putpixel((px, by1 + 2), body_hi)

    # Häntä highlight päällä
    img.putpixel((13, 39 + body_y), body_hi)

    # Pienen selkäviivan vihjaus (erottaa pää/vartalo)
    img.putpixel((30, 33 + body_y), body_shd)
    img.putpixel((31, 34 + body_y), body_shd)

    return img


# ─── Luo 4 framea ─────────────────────────────────────────────────────────────
# idle-sykli: pieni hengitysliike (body_y 0→1→0) + korvan liike (vasen korva vaihtelee)
frame_params = [
    # (ear_r_drop, ear_l_drop, body_y, nimi)
    (0,  0, 0, "normaali"),           # Perusasento
    (0,  4, 1, "hengitys + korva"),   # Hengitys ylös, vasen korva kallistuu
    (0,  0, 1, "hengitys_huippu"),    # Hengityksen huippu, korvat normaalina
    (3,  0, 0, "oikea_korva_alas"),   # Oikea korva rentoutuu hieman
]

frames = []
for i, (er, el, by, label) in enumerate(frame_params):
    frame = draw_frame(er, el, by, label)
    path = f"C:/Users/mauri/Desktop/Git/GodotMining/assets/bunny_idle_frame{i}.png"
    frame.save(path)
    frames.append(frame)
    print(f"Tallennettu: bunny_idle_frame{i}.png  ({label})")

# ─── Sprite sheet ─────────────────────────────────────────────────────────────
n = len(frames)
sheet = Image.new("RGBA", (64 * n, 64), CLEAR)
for i, f in enumerate(frames):
    sheet.paste(f, (i * 64, 0))

sheet_path = "C:/Users/mauri/Desktop/Git/GodotMining/assets/bunny_idle_sheet.png"
sheet.save(sheet_path)
print(f"Sprite sheet tallennettu: bunny_idle_sheet.png  ({64*n}x64)")
