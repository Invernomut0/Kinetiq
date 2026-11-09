"""Promotional stills built from the same real Kinetiq renders as the film."""
import os, sys, math
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, os.path.dirname(__file__))
import kinetiq_lib as K

OUTDIR = sys.argv[1]
os.makedirs(OUTDIR, exist_ok=True)

def mid_frame(name, ratio):
    """Index where the window's remaining opacity is closest to `ratio` of the first frame."""
    s = K.seq(name)
    masses = []
    for i in range(0, len(s), 2):
        a = np.asarray(Image.open(os.path.join(s.dir, s.files[i])).getchannel("A"), np.float32)
        masses.append((i, a.sum()))
    first = masses[0][1]
    return min(masses, key=lambda m: abs(m[1] / first - ratio))[0]

def place(canvas, name, index, cx, cy, width, alpha=1.0):
    s = K.seq(name)
    bx0, by0, bx1, by1 = s.box
    sc = width / (bx1 - bx0)
    im = s.frame(index, sc)
    K.paste(canvas, im, cx - (bx0 + (bx1 - bx0) / 2) * sc, cy - (by0 + (by1 - by0) / 2) * sc, alpha)

def bg(size, t=6.0, boost=1.1):
    b = K.background(t, boost)
    w, h = size
    if (w, h) == (K.W, K.H): return b
    scale = max(w / K.W, h / K.H)
    b = b.resize((int(K.W * scale + 1), int(K.H * scale + 1)), Image.BICUBIC)
    x, y = (b.width - w) // 2, (b.height - h) // 2
    return b.crop((x, y, x + w, y + h))

# 1. Hero 2560x1440: three windows, three moments.
c = bg((2560, 1440), 8.0)
K.glow(c, 1900, 760, 1000, 640, K.ACCENT, 0.6)
place(c, "snap", mid_frame("snap", 0.55), 2270, 430, 600, 0.95)
place(c, "incinerate", mid_frame("incinerate", 0.6), 2080, 1060, 720)
place(c, "wobbly", 42, 1720, 720, 900)
K.wave_mark(c, 290, 470, 1.0, 1.0, 1.3)
K.text(c, "Kinetiq", K.font(K.NY, 210, "Bold"), 200, 640, K.INK, 1, "lm", tracking=6)
K.text(c, "Your Mac, in motion.", K.font(K.SF, 58, "Light"), 206, 790, K.SOFT, 1, "lm")
K.text(c, "WOBBLY WINDOWS  ·  30+ CLOSE EFFECTS", K.font(K.SF, 26, "Semibold"), 210, 885, K.ACCENT, 1, "lm", tracking=4)
K.text(c, "ANIMATION STUDIO  ·  3D LAYOUTS", K.font(K.SF, 26, "Semibold"), 210, 930, K.ACCENT, 1, "lm", tracking=4)
K.chip(c, "Free & open source for macOS", 210, 1030, 1, size=28, anchor="l")
c.convert("RGB").save(os.path.join(OUTDIR, "Kinetiq-hero-2560x1440.png"))

# 2. Square 1080x1080: thirty ways to say goodbye.
c = bg((1080, 1080), 13.0)
K.text(c, "THIRTY GPU CLOSE EFFECTS", K.font(K.SF, 22, "Semibold"), 540, 92, K.ACCENT, 1, "mm", tracking=5)
K.text(c, "Thirty ways", K.font(K.NY, 76, "Bold"), 540, 172, K.INK, 1, "mm")
K.text(c, "to say goodbye.", K.font(K.NY, 76, "Bold"), 540, 252, K.INK, 1, "mm")
cells = [("fire", "Fire", 290, 470, 0.7), ("glass", "Broken Glass", 790, 470, 0.75), ("matrix", "Matrix", 290, 790, 0.65), ("wisps", "Wisps", 790, 790, 0.6)]
for name, label, cx, cy, r in cells:
    place(c, name, mid_frame(name, r), cx, cy, 400)
    K.chip(c, label, cx, cy + 155, 1)
K.text(c, "Kinetiq  ·  for macOS", K.font(K.SF, 24, "Medium"), 540, 1035, K.SOFT, 1, "mm", tracking=2)
c.convert("RGB").save(os.path.join(OUTDIR, "Kinetiq-close-effects-1080.png"))

# 3. Animation Studio 1920x1080.
c = bg((1920, 1080), 34.0)
K.text(c, "ANIMATION STUDIO", K.font(K.SF, 22, "Semibold"), 960, 92, K.ACCENT, 1, "mm", tracking=5)
K.text(c, "Make it yours.", K.font(K.NY, 72, "Bold"), 960, 162, K.INK, 1, "mm")
K.text(c, "Stack 60+ Studio and built-in effects on a timeline, reverse them, and use them on close.",
       K.font(K.SF, 28, "Light"), 960, 232, K.SOFT, 1, "mm")
K.glow(c, 960, 650, 1320, 700, K.ACCENT, 0.3)
K.ui_panel(c, 2.15, 1.0)
c.convert("RGB").save(os.path.join(OUTDIR, "Kinetiq-animation-studio-1920x1080.png"))

# 4. Layouts 1920x1080.
c = bg((1920, 1080), 29.0)
K.feature(c, 10, "LAYOUTS  ·  ⌃⌥↑", ["Every window,", "in 3D."], "Exposé, Orbit and Cube.", y=330)
K.text(c, "Hover to lift. Click to focus.", K.font(K.SF, 30, "Light"), 150, 330 + 66 + 2 * 96 + 40, K.SOFT)
K.glow(c, 1290, 560, 940, 590, K.ACCENT, 0.35)
K.DISPLAY_SEQ = "expose"
K.display(c, 2.2, 1290, 560, 940, 1.0)
c.convert("RGB").save(os.path.join(OUTDIR, "Kinetiq-layouts-1920x1080.png"))

# 5. Support card 1200x630 (Open Graph size).
c = bg((1200, 630), 3.0, 0.85)
scrim = Image.new("RGBA", (1200, 630), (0, 0, 0, 0))
ImageDraw.Draw(scrim).rounded_rectangle((180, 250, 1020, 340), 40, fill=(8, 9, 20, 110))
from PIL import ImageFilter
c.alpha_composite(scrim.filter(ImageFilter.GaussianBlur(30)))
K.wave_mark(c, 600, 120, 1.0, 1.0, 0.9)
K.text(c, "Kinetiq is free.", K.font(K.NY, 74, "Bold"), 600, 225, K.INK, 1, "mm")
K.text(c, "If it made your Mac a little more fun, fuel the next effect.", K.font(K.SF, 28, "Light"), 600, 300, K.SOFT, 1, "mm")
K.glow(c, 600, 410, 460, 92, (255, 221, 0), 0.6)
btn = Image.new("RGBA", (460, 92), (0, 0, 0, 0)); d = ImageDraw.Draw(btn)
d.rounded_rectangle((0, 0, 459, 91), 46, fill=(255, 221, 0, 255))
icon = K.coffee_icon(48); f = K.font(K.SF, 38, "Bold")
tw = d.textlength("Buy me a coffee", font=f); x = (460 - (48 + 16 + tw)) / 2
btn.alpha_composite(icon, dest=(int(x), 22)); d.text((x + 64, 46), "Buy me a coffee", font=f, fill=(20, 16, 10, 255), anchor="lm")
K.paste(c, btn, 370, 364)
K.text(c, "buymeacoffee.com/invernomut0", K.font(K.SF, 28, "Semibold"), 600, 505, (255, 221, 0), 1, "mm")
K.text(c, "github.com/Invernomut0/Kinetiq", K.font(K.SF, 20, "Regular"), 600, 575, (150, 156, 185), 1, "mm", tracking=1)
c.convert("RGB").save(os.path.join(OUTDIR, "Kinetiq-buy-me-a-coffee-1200x630.png"))
print("posters done")
