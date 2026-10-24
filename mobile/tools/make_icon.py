"""Draws the Amana mark (ajrak diamond medallion) as the app icon.
Writes assets/icon/icon.png (full square) and assets/icon/icon_fg.png (transparent, for Android adaptive icons).
Run:  python mobile/tools/make_icon.py"""
import os
from PIL import Image, ImageDraw

INDIGO, INDIGO2, MADDER, WHITE = (36, 48, 99), (58, 74, 148), (178, 51, 74), (255, 255, 255)
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "assets", "icon")
os.makedirs(OUT, exist_ok=True)
S, SS = 1024, 3  # final size, supersampling


def diamond(d, cx, cy, r, fill):
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)], fill=fill)


def medallion(d, size, scale=1.0, with_corners=True):
    c = size / 2
    u = size * scale
    diamond(d, c, c, 0.36 * u, WHITE)
    diamond(d, c, c, 0.27 * u, MADDER)
    diamond(d, c, c, 0.17 * u, WHITE)
    diamond(d, c, c, 0.085 * u, INDIGO)
    if with_corners:
        for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0)):
            diamond(d, c + dx * 0.43 * u, c + dy * 0.43 * u, 0.045 * u, WHITE)
        for dx, dy in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            diamond(d, c + dx * 0.31 * u, c + dy * 0.31 * u, 0.03 * u, INDIGO2 if False else (200, 205, 235))


# full icon: indigo square + medallion
big = Image.new("RGB", (S * SS, S * SS), INDIGO)
medallion(ImageDraw.Draw(big), S * SS, 1.0)
big.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, "icon.png"))

# adaptive foreground: transparent, medallion kept inside the 66% safe zone
fg = Image.new("RGBA", (S * SS, S * SS), (0, 0, 0, 0))
medallion(ImageDraw.Draw(fg), S * SS, 0.66)
fg.resize((S, S), Image.LANCZOS).save(os.path.join(OUT, "icon_fg.png"))
print("icons written to", os.path.abspath(OUT))
