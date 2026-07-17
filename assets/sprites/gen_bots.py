"""
Bottien in-game pikselispritet — "Industrial Gothic Underground".

Botit lentavat seka tumman maanalaisen etta vaalean taivaan yla, ja niita
piirtaa taalla asti pelkka kaksi sisakkaista nelio (ks. bot_manager.gd
draw_bots). Tama generaattori korvaa ne kunnon spriteilla:

    bot_miner_{0,1}.png   12x12, anchor "center"  — amber pod
    bot_hauler_{0,1}.png  12x12, anchor "center"  — sininen pod

Muoto on pelkka mekaaninen, viistetyilla kulmilla oleva kapseli-pod —
kadet ja antenni piirretaan nyt PROSEDURAALISESTI koodissa (liikkuvat
erillaan spritesta), joten tassa jaa vain pod-runko + silmä. Pod EI ole
taydellinen pallo — oktogoni (viistetty nelio) antaa sille tahokkuutta/
paneelituntumaa ilman anti-aliasointia.

Hehkulinssi on pieni ja hillitty (1px ydin dark socketin sisassa), ja
framien valinen ero on tarkoituksella minimaalinen (vain ytimen vari
vaihtuu, ei pod) — ettei se vilku pelissa.

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

# ---------------------------------------------------------------------------
# Pod: viistetty oktogoni (ei ellipsi), keskitetty 12x12-kanvaaselle
# (rivit 2-9, sarakkeet 2-9 — 2px marginaali joka reunalla).
# Viistetyt kulmat -> mekaaninen paneelimainen siluetti, ei pallo.
# Ulompi kehä (aariviiva) + 1px sisaan vedetty runkokehä -> tasainen 1px
# rengas koko pod-siluetin ymparilla ilman anti-aliasointia.
# ---------------------------------------------------------------------------
POD_OUTER = [(4, 2), (7, 2), (9, 4), (9, 7), (7, 9), (4, 9), (2, 7), (2, 4)]
POD_INNER = [(4, 3), (7, 3), (8, 4), (8, 7), (7, 8), (4, 8), (3, 7), (3, 4)]


def _pod_frame(body, body_hi, body_lo):
    """Yhteinen viistetty pod-runko: aariviivarengas + volumetrinen hilta/varjo."""
    img = P.new_img(12, 12)
    d = ImageDraw.Draw(img)
    d.polygon(POD_OUTER, fill=P.OUTLINE)
    d.polygon(POD_INNER, fill=body)
    # Volumetrinen sävytys: vaalea kaari ylavasemmalla (valo yllta),
    # tumma kaari alaoikealla (paino/varjo) — sama tuntuma kuin ennen,
    # nyt viistetyn pod-muodon reunoja pitkin. Staattinen molemmissa frameissa.
    for xy in [(4, 3), (3, 4), (3, 5)]:
        P.px(img, xy, body_hi)
    for xy in [(8, 6), (8, 7), (7, 8)]:
        P.px(img, xy, body_lo)
    return img, d


# Silman pesa on aina samankokoinen ja samalla paikalla molemmissa
# frameissa — vain yhden ydinpikselin vari vaihtuu hieman, ei pesan koko.
EYE_SOCKET = [4, 4, 6, 6]
EYE_CORE = (5, 5)


def _eye(d, img, pulse: bool):
    """Pieni, hillitty hehkulinssi: tumma pesa + 1px amber ydin.

    pulse=True -> ydinpikseli hieman kirkkaampi (AMBER_HI). Pesan koko ja
    sijainti EIVAT muutu framien valilla, joten hengitys jaa aavistuksenomaiseksi.
    """
    d.ellipse(EYE_SOCKET, fill=P.OUTLINE)
    P.px(img, EYE_CORE, P.AMBER_HI if pulse else P.AMBER)


def bot_miner(frame: int):
    """Miner-probe — amber pod. Roolikadet piirretaan koodissa."""
    img, d = _pod_frame(P.MINER, P.MINER_HI, P.MINER_LO)
    _eye(d, img, frame == 1)
    return img


def bot_hauler(frame: int):
    """Hauler-probe — sininen pod. Roolikadet piirretaan koodissa."""
    img, d = _pod_frame(P.BLUE, P.BLUE_HI, P.BLUE_LO)
    _eye(d, img, frame == 1)
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
            "note": "amber pod (kadet proseduraalisia)",
        },
        {
            "name": "bot_hauler",
            "w": 12,
            "h": 12,
            "frames": 2,
            "anchor": "center",
            "files": ["bot_hauler_0.png", "bot_hauler_1.png"],
            "role": "hauler",
            "note": "blue pod (kadet proseduraalisia)",
        },
    ]
    P.write_manifest(OUT, entries)
    P.build_preview_sheet(OUT, list(files.keys()), "Bots preview")


if __name__ == "__main__":
    main()
