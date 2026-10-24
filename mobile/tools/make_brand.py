"""Draws the Amana AI logo and every asset made from it (one geometry -> SVG + PNGs).
Concept: 'amana' = something entrusted. A round trust SEAL framed by ajrak diamonds, and inside it an 'A'
whose crossbar is a line of running stitches (the piecework of the women we serve).
Run:  python mobile/tools/make_brand.py [path-to-Bricolage.ttf] [path-to-Figtree.ttf]
Writes: assets/icon/*.png  and  assets/brand/*  (svg, png, wordmark)"""
import math, os, sys
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ICON_DIR = os.path.join(HERE, "..", "assets", "icon")
BRAND_DIR = os.path.join(HERE, "..", "assets", "brand")
os.makedirs(ICON_DIR, exist_ok=True); os.makedirs(BRAND_DIR, exist_ok=True)

INDIGO, INDIGO2, MADDER, WHITE = (36, 48, 99), (58, 74, 148), (178, 51, 74), (255, 255, 255)
HEX = lambda c: "#%02X%02X%02X" % c
C = 500.0  # centre of the 1000 x 1000 design canvas

# ------------------------------------------------------------------ geometry (1000 x 1000)
R_SEAL, R_DISC, R_RING = 392, 326, 300
def diamond(cx, cy, hx, hy=None, rot=0.0):
    hy = hx if hy is None else hy
    pts = [(0, -hy), (hx, 0), (0, hy), (-hx, 0)]
    cr, sr = math.cos(rot), math.sin(rot)
    return [(cx + x * cr - y * sr, cy + x * sr + y * cr) for x, y in pts]

corner_diamonds = [diamond(C + dx * 452, C + dy * 452, 36) for dx, dy in ((0, -1), (1, 0), (0, 1), (-1, 0))]
ring_diamonds = []
for i in range(16):                       # ajrak border on the white seal
    a = i * 2 * math.pi / 16
    ring_diamonds.append(diamond(C + 359 * math.cos(a), C + 359 * math.sin(a), 17, 17, 0.0))
A_TOP, A_BASE, A_HW_TOP, A_HW_BASE, A_T = 262, 728, 32, 186, 68
leg_l = [(C - A_HW_TOP, A_TOP), (C + A_HW_TOP, A_TOP), (C - A_HW_BASE + A_T, A_BASE), (C - A_HW_BASE, A_BASE)]
leg_r = [(C - A_HW_TOP, A_TOP), (C + A_HW_TOP, A_TOP), (C + A_HW_BASE, A_BASE), (C + A_HW_BASE - A_T, A_BASE)]
STITCH_W, STITCH_H, STITCH_GAP, STITCH_Y = 34, 22, 8, 566
_tot = 3 * STITCH_W + 2 * STITCH_GAP
stitches = [(C - _tot / 2 + i * (STITCH_W + STITCH_GAP), STITCH_Y, STITCH_W, STITCH_H) for i in range(3)]   # running stitches = the crossbar
STITCH_R = 10

# ------------------------------------------------------------------ PNG renderer
def render(size, scale=1.0, bg=None, rounded=0, ss=4):
    """scale shrinks the emblem inside the canvas (for safe zones). bg=None -> transparent."""
    W = size * ss
    img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if bg is not None:
        if rounded:
            d.rounded_rectangle([0, 0, W - 1, W - 1], radius=int(rounded * W / 1000), fill=bg + (255,))
        else:
            d.rectangle([0, 0, W, W], fill=bg + (255,))
    k = W / 1000.0
    T = lambda p: ((C + (p[0] - C) * scale) * k, (C + (p[1] - C) * scale) * k)
    poly = lambda pts, col: d.polygon([T(p) for p in pts], fill=col)
    cx, cy = T((C, C))
    circ = lambda r, **kw: d.ellipse([cx - r * scale * k, cy - r * scale * k, cx + r * scale * k, cy + r * scale * k], **kw)
    for q in corner_diamonds: poly(q, WHITE)
    circ(R_SEAL, fill=WHITE)
    for q in ring_diamonds: poly(q, INDIGO)
    circ(R_DISC, fill=MADDER)
    circ(R_RING, outline=(255, 255, 255, 120), width=max(1, int(5 * scale * k)))
    poly(leg_l, WHITE); poly(leg_r, WHITE)
    for x, y, w, h in stitches:
        (x0, y0), (x1, y1) = T((x, y)), T((x + w, y + h))
        d.rounded_rectangle([x0, y0, x1, y1], radius=STITCH_R * scale * k, fill=WHITE)
    return img.resize((size, size), Image.LANCZOS)

def save(img, folder, name):
    p = os.path.join(folder, name); img.save(p); print("wrote", os.path.relpath(p, os.path.join(HERE, "..")))

# ------------------------------------------------------------------ SVG
def svg(rounded_bg=True):
    f = lambda pts: " ".join("%.1f,%.1f" % p for p in pts)
    o = ['<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000" width="1000" height="1000">',
         '<title>Amana AI</title>']
    if rounded_bg: o.append('<rect width="1000" height="1000" rx="224" fill="%s"/>' % HEX(INDIGO))
    o += ['<polygon points="%s" fill="#FFFFFF"/>' % f(q) for q in corner_diamonds]
    o.append('<circle cx="500" cy="500" r="%d" fill="#FFFFFF"/>' % R_SEAL)
    o += ['<polygon points="%s" fill="%s"/>' % (f(q), HEX(INDIGO)) for q in ring_diamonds]
    o.append('<circle cx="500" cy="500" r="%d" fill="%s"/>' % (R_DISC, HEX(MADDER)))
    o.append('<circle cx="500" cy="500" r="%d" fill="none" stroke="#FFFFFF" stroke-opacity="0.47" stroke-width="5"/>' % R_RING)
    o += ['<polygon points="%s" fill="#FFFFFF"/>' % f(leg_l), '<polygon points="%s" fill="#FFFFFF"/>' % f(leg_r)]
    o += ['<rect x="%.1f" y="%.1f" width="%d" height="%d" rx="%d" fill="#FFFFFF"/>' % (x, y, w, h, STITCH_R) for x, y, w, h in stitches]
    o.append("</svg>")
    return "\n".join(o)

# ------------------------------------------------------------------ outputs
# app icon (full-bleed square; Android masks it) and adaptive-icon foreground (kept inside the 66% safe zone)
save(render(1024, 0.90, bg=INDIGO).convert("RGB"), ICON_DIR, "icon.png")
save(render(1024, 0.62), ICON_DIR, "icon_fg.png")
save(render(1152, 0.60), ICON_DIR, "splash_logo.png")           # native Android splash (Android 12 safe circle)
save(render(1024, 0.90, bg=INDIGO, rounded=224), BRAND_DIR, "amana_logo_rounded.png")
save(render(2048, 1.0), BRAND_DIR, "amana_logo_transparent.png")
save(render(1024, 0.90, bg=WHITE, rounded=224), BRAND_DIR, "amana_logo_on_white.png")
open(os.path.join(BRAND_DIR, "amana_logo.svg"), "w").write(svg(True))
open(os.path.join(BRAND_DIR, "amana_emblem.svg"), "w").write(svg(False)); print("wrote assets/brand/*.svg")

# wordmark (horizontal lockup) if fonts were given
brico = sys.argv[1] if len(sys.argv) > 1 else None
figt = sys.argv[2] if len(sys.argv) > 2 else None
if brico and figt and os.path.exists(brico) and os.path.exists(figt):
    W, H = 2400, 900
    sheet = Image.new("RGB", (W, H), WHITE)
    mark = render(640, 0.90, bg=INDIGO, rounded=224)
    sheet.paste(mark, (150, (H - 640) // 2), mark)
    d = ImageDraw.Draw(sheet)
    fb = ImageFont.truetype(brico, 330); fb.set_variation_by_axes([60, 100, 800][::-1] if False else [96, 800, 100])
    d.text((860, 175), "Amana", font=fb, fill=INDIGO)
    tw = d.textlength("Amana", font=fb)
    fa = ImageFont.truetype(brico, 150); fa.set_variation_by_axes([96, 800, 100])
    ax, ay = 860 + tw + 40, 270
    aw = d.textlength("AI", font=fa)
    d.rounded_rectangle([ax, ay, ax + aw + 80, ay + 170], radius=46, fill=MADDER)
    d.text((ax + (aw + 80) / 2, ay + 85), "AI", font=fa, fill=WHITE, anchor="mm")
    ft = ImageFont.truetype(figt, 82); ft.set_variation_by_axes([600])
    d.text((866, 590), "Trusted records & fair pay for", font=ft, fill=INDIGO2)
    d.text((866, 690), "women who work from home", font=ft, fill=INDIGO2)
    save(sheet, BRAND_DIR, "amana_wordmark.png")
