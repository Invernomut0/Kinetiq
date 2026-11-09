"""Kinetiq marketing film: composes real Kinetiq effect renders into a 1080p promo."""
import math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H, FPS = 1920, 1080, 30
FR = sys.argv[1]            # frames directory from the exporter
OUT = sys.argv[2]           # output mp4
AUDIO = sys.argv[3] if len(sys.argv) > 3 else None
STILL = os.environ.get("KINETIQ_STILL")  # "t1,t2,..." -> write PNGs instead of video

SF, NY = "/System/Library/Fonts/SFNS.ttf", "/System/Library/Fonts/NewYork.ttf"
_fonts = {}
def font(path, size, var):
    key = (path, size, var)
    if key not in _fonts:
        f = ImageFont.truetype(path, size); f.set_variation_by_name(var); _fonts[key] = f
    return _fonts[key]

def clamp(x, a=0.0, b=1.0): return max(a, min(b, x))
def ease_out(t): t = clamp(t); return 1 - (1 - t) ** 3
def ease_io(t): t = clamp(t); return 4 * t ** 3 if t < 0.5 else 1 - (-2 * t + 2) ** 3 / 2
def back(t): t = clamp(t) - 1; return 1 + 2.4 * t ** 3 + 1.4 * t ** 2

INK = (244, 246, 255); SOFT = (184, 192, 224); ACCENT = (150, 132, 255); CYAN = (90, 210, 230); WARM = (255, 150, 110)

# ---------------------------------------------------------------- background
LW, LH = 384, 216
yy, xx = np.mgrid[0:LH, 0:LW].astype(np.float32)
xx /= LW; yy /= LH
base = np.zeros((LH, LW, 3), np.float32)
top, bottom = np.array([7, 8, 18], np.float32), np.array([15, 14, 34], np.float32)
base[:] = top + (bottom - top) * yy[..., None]
rng = np.random.default_rng(7)
grain = (rng.standard_normal((H + 64, W + 64)).astype(np.float32) * 3.2)
vy, vx = np.mgrid[0:H, 0:W].astype(np.float32)
vign = 1 - 0.55 * (((vx / W - 0.5) ** 2) * 1.2 + ((vy / H - 0.5) ** 2) * 1.6)
vign = np.clip(vign, 0.35, 1)[..., None]
BLOBS = [((123, 92, 255), 0.13, 0.0, 0.33), ((59, 201, 219), 0.11, 2.1, 0.30), ((255, 92, 150), 0.09, 4.2, 0.26), ((80, 120, 255), 0.07, 1.0, 0.36)]

def background(t, boost=1.0):
    img = base.copy()
    for color, speed, phase, sigma in BLOBS:
        cx = 0.5 + 0.34 * math.cos(t * speed * 2 * math.pi / 3 + phase)
        cy = 0.5 + 0.30 * math.sin(t * speed * 2 * math.pi / 2.3 + phase * 1.3)
        d = ((xx - cx) * 1.78) ** 2 + (yy - cy) ** 2
        img += np.exp(-d / (2 * sigma ** 2))[..., None] * np.array(color, np.float32) * 0.32 * boost
    big = np.asarray(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).resize((W, H), Image.BICUBIC), np.float32)
    ox, oy = int(t * 37) % 64, int(t * 53) % 64
    big = big * vign + grain[oy:oy + H, ox:ox + W, None]
    return Image.fromarray(np.clip(big, 0, 255).astype(np.uint8)).convert("RGBA")

# ---------------------------------------------------------------- helpers
def paste(canvas, im, x, y, alpha=1.0):
    x, y = int(round(x)), int(round(y))
    if alpha < 1:
        im = im.copy(); a = im.getchannel("A").point(lambda v: int(v * alpha)); im.putalpha(a)
    sx, sy = max(0, -x), max(0, -y)
    dx, dy = max(0, x), max(0, y)
    w, h = min(im.width - sx, canvas.width - dx), min(im.height - sy, canvas.height - dy)
    if w <= 0 or h <= 0: return
    canvas.alpha_composite(im, dest=(dx, dy), source=(sx, sy, sx + w, sy + h))

def text(canvas, s, f, x, y, color=INK, alpha=1.0, anchor="la", tracking=0):
    if alpha <= 0.01: return
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    col = color + (int(255 * clamp(alpha)),)
    if tracking == 0:
        d.text((x, y), s, font=f, fill=col, anchor=anchor)
    else:
        widths = [d.textlength(ch, font=f) for ch in s]
        total = sum(widths) + tracking * (len(s) - 1)
        cx = x - total / 2 if anchor[0] == "m" else (x - total if anchor[0] == "r" else x)
        for ch, w in zip(s, widths):
            d.text((cx, y), ch, font=f, fill=col, anchor="l" + anchor[1]); cx += w + tracking
    canvas.alpha_composite(layer)

def reveal(canvas, s, f, x, y, t, delay=0.0, dur=0.7, color=INK, anchor="la", tracking=0, rise=26):
    e = ease_out((t - delay) / dur)
    text(canvas, s, f, x, y + (1 - e) * rise, color, e, anchor, tracking)

class Seq:
    def __init__(self, name):
        self.dir = os.path.join(FR, name)
        self.files = sorted(f for f in os.listdir(self.dir) if f.endswith(".png"))
        first = Image.open(os.path.join(self.dir, self.files[0])).convert("RGBA")
        a = np.asarray(first.getchannel("A"))
        ys, xs = np.where(a >= 250)
        self.box = (xs.min(), ys.min(), xs.max() + 1, ys.max() + 1) if len(xs) else (0, 0, first.width, first.height)
        self.cache = {}
    def __len__(self): return len(self.files)
    def frame(self, i, scale):
        i = int(clamp(i, 0, len(self.files) - 1))
        key = (i, round(scale, 4))
        if key not in self.cache:
            im = Image.open(os.path.join(self.dir, self.files[i])).convert("RGBA")
            self.cache = {k: v for k, v in self.cache.items() if abs(k[0] - i) < 3}
            self.cache[key] = im.resize((max(1, int(im.width * scale)), max(1, int(im.height * scale))), Image.LANCZOS)
        return self.cache[key]
    def draw(self, canvas, t, cx, cy, width, delay=0.0, alpha=1.0, speed=1.0, loop=None):
        bx0, by0, bx1, by1 = self.box
        s = width / (bx1 - bx0)
        local = t - delay
        if loop is not None and local > 0:
            span = len(self.files) / FPS
            local %= span + loop
            if local > span:  # between plays the window comes back, fading in
                alpha *= ease_out((local - span) / loop)
                local = 0
        im = self.frame(local * FPS * speed, s)
        paste(canvas, im, cx - (bx0 + (bx1 - bx0) / 2) * s, cy - (by0 + (by1 - by0) / 2) * s, alpha)

_glows = {}
def glow(canvas, cx, cy, w, h, color, alpha):
    key = (int(w), int(h), color)
    if key not in _glows:
        pad = 160
        g = Image.new("RGBA", (int(w) + 2 * pad, int(h) + 2 * pad), (0, 0, 0, 0))
        ImageDraw.Draw(g).rounded_rectangle((pad, pad, pad + w, pad + h), 40, fill=color + (150,))
        _glows[key] = g.filter(ImageFilter.GaussianBlur(70))
    g = _glows[key]
    paste(canvas, g, cx - g.width / 2, cy - g.height / 2, alpha)

def chip(canvas, s, x, y, alpha, fill=(255, 255, 255, 26), color=INK, size=21, anchor="m"):
    f = font(SF, size, "Semibold")
    d = ImageDraw.Draw(Image.new("RGBA", (1, 1)))
    w = d.textlength(s, font=f) + 36
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    dd = ImageDraw.Draw(layer)
    x0 = x - w / 2 if anchor == "m" else x
    dd.rounded_rectangle((x0, y - 20, x0 + w, y + 20), 20, fill=fill[:3] + (int(fill[3] * alpha),),
                         outline=(255, 255, 255, int(40 * alpha)))
    dd.text((x0 + w / 2, y), s, font=f, fill=color + (int(255 * alpha),), anchor="mm")
    canvas.alpha_composite(layer)

def wave_mark(canvas, cx, cy, t, alpha, scale=1.0):
    S = 4; w, h = int(150 * scale), int(70 * scale)
    im = Image.new("RGBA", (w * S, h * S), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    for k, col in enumerate([(150, 132, 255), (110, 170, 255), (90, 215, 230)]):
        pts = []
        for i in range(0, 121):
            u = i / 120
            y = h * S / 2 + (k - 1) * 18 * scale * S + math.sin(u * 2 * math.pi * 1.2 + t * 2.2 + k * 0.6) * 9 * scale * S * (0.6 + 0.4 * math.sin(u * math.pi))
            pts.append((u * w * S, y))
        d.line(pts, fill=col + (255,), width=int(7 * scale * S), joint="curve")
    im = im.resize((w, h), Image.LANCZOS)
    paste(canvas, im, cx - w / 2, cy - h / 2, alpha)

def coffee_icon(size, color=(20, 16, 10)):
    S = 4; s = size * S
    im = Image.new("RGBA", (s, s), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    d.rounded_rectangle((s * 0.16, s * 0.40, s * 0.70, s * 0.88), s * 0.10, fill=color + (255,))
    d.arc((s * 0.58, s * 0.48, s * 0.88, s * 0.76), -90, 90, fill=color + (255,), width=int(s * 0.07))
    for k in range(3):
        x = s * (0.28 + k * 0.14)
        pts = [(x + math.sin(v / 10 * math.pi * 2) * s * 0.03, s * 0.34 - v / 10 * s * 0.22) for v in range(11)]
        d.line(pts, fill=color + (255,), width=int(s * 0.045), joint="curve")
    return im.resize((size, size), Image.LANCZOS)

# ---------------------------------------------------------------- scenes
SEQ = {}
def seq(name):
    if name not in SEQ: SEQ[name] = Seq(name)
    return SEQ[name]

def feature(canvas, t, over, title_lines, sub, x=150, y=360, align="la"):
    reveal(canvas, over, font(SF, 22, "Semibold"), x, y, t, 0.15, color=ACCENT, tracking=5, anchor=align)
    for i, line in enumerate(title_lines):
        reveal(canvas, line, font(NY, 84, "Bold"), x, y + 46 + i * 96, t, 0.3 + i * 0.12, anchor=align)
    if sub:
        reveal(canvas, sub, font(SF, 30, "Light"), x, y + 66 + len(title_lines) * 96, t, 0.6, color=SOFT, anchor=align)

def window_in(t, delay=0.0): return ease_out((t - delay) / 0.5)

def s_intro(c, t):
    t -= 0.9  # the wordmark enters once the opening poster has dissolved
    e = ease_out((t - 0.3) / 1.4)
    wave_mark(c, W / 2, 360 - (1 - e) * 20, t, e, 1.4)
    tr = 46 - 36 * ease_out((t - 0.4) / 1.8)
    text(c, "Kinetiq", font(NY, 168, "Bold"), W / 2, 520 + (1 - e) * 30, INK, e, "mm", tracking=tr)
    reveal(c, "Your Mac, in motion.", font(SF, 40, "Light"), W / 2, 640, t, 0.9, 0.8, SOFT, "mm")
    reveal(c, "Window effects for macOS", font(SF, 22, "Semibold"), W / 2, 720, t, 1.3, 0.8, ACCENT, "mm", tracking=6)

def s_wobbly(c, t):
    feature(c, t, "WOBBLY WINDOWS", ["Drag it.", "Watch it wobble."], "A real spring mesh, like Compiz.")
    a = window_in(t, 0.1)
    glow(c, 1250, 560, 860, 560, ACCENT, 0.55 * a)
    seq("wobbly").draw(c, t, 1250, 560 + (1 - a) * 40, 860, delay=0.5, alpha=a)

def s_incinerate(c, t):
    feature(c, t, "CLOSE EFFECTS", ["Close it", "with fire."], "Incinerate.")
    a = window_in(t, 0.1)
    glow(c, 1250, 560, 860, 560, WARM, 0.5 * a * (1 - clamp((t - 2.2) / 1.2)))
    seq("incinerate").draw(c, t, 1250, 560 + (1 - a) * 40, 860, delay=0.75, alpha=a)

def s_snap(c, t):
    feature(c, t, "CLOSE EFFECTS", ["Or let it", "turn to dust."], "Snap of Disintegration.", x=1770, align="ra")
    a = window_in(t, 0.1)
    glow(c, 680, 560, 860, 560, CYAN, 0.45 * a * (1 - clamp((t - 1.8) / 1.0)))
    seq("snap").draw(c, t, 680, 560 + (1 - a) * 40, 860, delay=0.7, alpha=a)

def s_montage(c, t):
    reveal(c, "THIRTY GPU CLOSE EFFECTS", font(SF, 22, "Semibold"), W / 2, 92, t, 0.1, color=ACCENT, anchor="mm", tracking=5)
    reveal(c, "Thirty ways to say goodbye.", font(NY, 64, "Bold"), W / 2, 158, t, 0.25, anchor="mm")
    cells = [("fire", "Fire", 620, 440), ("glass", "Broken Glass", 1300, 440), ("matrix", "Matrix", 620, 780), ("wisps", "Wisps", 1300, 780)]
    for k, (name, label, cx, cy) in enumerate(cells):
        a = window_in(t, 0.15 + k * 0.08)
        seq(name).draw(c, t, cx, cy + (1 - a) * 30, 430, delay=0.7 + k * 0.22, alpha=a)
        chip(c, label, cx, cy + 162, a)

def s_minimize(c, t):
    reveal(c, "MINIMIZE", font(SF, 22, "Semibold"), W / 2, 92, t, 0.1, color=ACCENT, anchor="mm", tracking=5)
    reveal(c, "Minimize with style.", font(NY, 64, "Bold"), W / 2, 158, t, 0.25, anchor="mm")
    reveal(c, "Nine Dock morphs, from Genie to Whirlpool.", font(SF, 28, "Light"), W / 2, 222, t, 0.45, color=SOFT, anchor="mm")
    for k, (name, label, cx) in enumerate([("genie", "Genie", 640), ("whirlpool", "Whirlpool", 1280)]):
        a = window_in(t, 0.15 + k * 0.1)
        seq(name).draw(c, t, cx, 520 + (1 - a) * 30, 500, delay=0.6 + k * 0.25, alpha=a, loop=0.45)
        chip(c, label, cx, 900, a)

def s_liquid(c, t):
    feature(c, t, "LIQUID", ["Melt it away."], "A real fluid simulation that pools", y=400)
    reveal(c, "and drains off the bottom of the screen.", font(SF, 30, "Light"), 150, 400 + 66 + 96 + 40, t, 0.7, color=SOFT)
    a = window_in(t, 0.1)
    seq("liquid").draw(c, t, 1260, 330 + (1 - a) * 40, 640, delay=0.6, alpha=a)

def s_destruction(c, t):
    feature(c, t, "WINDOW DESTRUCTION", ["Let it", "fall apart."], "Every button and letter becomes a piece.", x=1770, align="ra")
    a = window_in(t, 0.1)
    seq("destruction").draw(c, t, 660, 590 + (1 - a) * 40, 680, delay=0.6, alpha=a)

_display = {}
DISPLAY_SEQ = "orbit"
def display(c, t, cx, cy, w, alpha):
    h = int(w * 900 / 1440)
    if w not in _display:
        wall = Image.new("RGBA", (w, h))
        g = np.zeros((h, w, 3), np.float32)
        yy2, xx2 = np.mgrid[0:h, 0:w].astype(np.float32)
        g[:] = np.array([28, 30, 64], np.float32) + (np.array([70, 40, 110], np.float32) - [28, 30, 64]) * (xx2 / w)[..., None]
        g += np.exp(-(((xx2 / w - 0.7) * 1.6) ** 2 + (yy2 / h - 0.3) ** 2) / 0.08)[..., None] * np.array([60, 120, 160], np.float32)
        wall = Image.fromarray(np.clip(g, 0, 255).astype(np.uint8)).convert("RGBA")
        mask = Image.new("L", (w, h), 0); ImageDraw.Draw(mask).rounded_rectangle((0, 0, w, h), 22, fill=255)
        frame = Image.new("RGBA", (w + 28, h + 28), (0, 0, 0, 0))
        ImageDraw.Draw(frame).rounded_rectangle((0, 0, w + 27, h + 27), 34, fill=(18, 18, 26, 255), outline=(255, 255, 255, 40), width=2)
        _display[w] = (wall, mask, frame)
    wall, mask, frame = _display[w]
    paste(c, frame, cx - frame.width / 2, cy - frame.height / 2, alpha)
    screen = wall.copy()
    ov = seq(DISPLAY_SEQ)
    im = ov.frame(t * FPS, w / 1440)
    screen.alpha_composite(im.crop((0, 0, w, h)) if im.width >= w else im)
    screen.putalpha(Image.eval(mask, lambda v: int(v * alpha)))
    paste(c, screen, cx - w / 2, cy - h / 2)

def s_layouts(c, t):
    feature(c, t, "LAYOUTS  ·  ⌃⌥↑", ["Every window,", "in 3D."], "Exposé, Orbit and Cube.", y=330)
    reveal(c, "Hover to lift. Click to focus.", font(SF, 30, "Light"), 150, 330 + 66 + 2 * 96 + 40, t, 0.75, color=SOFT)
    a = window_in(t, 0.15)
    glow(c, 1290, 560, 940, 590, ACCENT, 0.35 * a)
    display(c, max(0, t - 0.3), 1290, 560 + (1 - a) * 30, 940, a)

def ui_panel(c, t, alpha):
    """A faithful sketch of the Animation Studio, driven by the real composition frames."""
    x0, y0, w, h = 300, 300, 1320, 700
    layer = Image.new("RGBA", (w, h), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    d.rounded_rectangle((0, 0, w - 1, h - 1), 20, fill=(27, 28, 38, 245), outline=(255, 255, 255, 34), width=2)
    d.rounded_rectangle((0, 0, w - 1, 52), 20, fill=(36, 37, 50, 255)); d.rectangle((0, 30, w - 1, 52), fill=(36, 37, 50, 255))
    for i, col in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        d.ellipse((20 + i * 22, 19, 33 + i * 22, 32), fill=col + (255,))
    f14, f16, f18 = font(SF, 15, "Medium"), font(SF, 17, "Regular"), font(SF, 19, "Semibold")
    def button(x, y, label, fill=(255, 255, 255, 22), color=(235, 238, 250), wb=None):
        wb = wb or d.textlength(label, font=f16) + 30
        d.rounded_rectangle((x, y, x + wb, y + 32), 8, fill=fill); d.text((x + wb / 2, y + 16), label, font=f16, fill=color + (255,), anchor="mm")
        return x + wb
    button(110, 10, "★  My Effects")
    d.rounded_rectangle((260, 10, 520, 42), 8, fill=(255, 255, 255, 14)); d.text((274, 26), "Ripple, then Incinerate", font=f16, fill=(240, 242, 255, 255), anchor="lm")
    hl = ease_io((t - 4.6) / 0.3) * (1 - ease_io((t - 5.6) / 0.3))
    button(w - 330, 10, "Save")
    button(w - 250, 10, "Use when…", fill=(110 + int(40 * hl), 90 + int(30 * hl), 255, 255), color=(255, 255, 255), wb=200)
    # preview area
    px0, py0, pw, ph = 20, 70, 860, 430
    d.rounded_rectangle((px0, py0, px0 + pw, py0 + ph), 12, fill=(16, 17, 26, 255))
    # inspector
    ix = 900
    d.text((ix, 84), "Incinerate", font=f18, fill=(245, 246, 255, 255)); d.text((ix + 108, 86), "Built-in · Close effect", font=f14, fill=(150, 155, 185, 255))
    d.rounded_rectangle((ix, 118, w - 24, 150), 8, fill=(255, 255, 255, 16))
    for k, tab in enumerate(["Edit", "Keyframes", "Advanced"]):
        tx = ix + k * 132
        if k == 0: d.rounded_rectangle((tx + 2, 120, tx + 128, 148), 7, fill=(255, 255, 255, 40))
        d.text((tx + 65, 134), tab, font=f14, fill=(235, 238, 250, 255), anchor="mm")
    rows = [("Enabled", "on"), ("Play in reverse", "off"), ("Starts at", "0.9 s"), ("Duration", "2.0 s"), ("Speed curve", "linear")]
    for k, (label, value) in enumerate(rows):
        yv = 180 + k * 48
        d.text((ix, yv), label, font=f16, fill=(210, 214, 235, 255), anchor="lm")
        if value in ("on", "off"):
            on = value == "on"
            d.rounded_rectangle((w - 80, yv - 12, w - 36, yv + 12), 12, fill=(110, 92, 255, 255) if on else (80, 82, 100, 255))
            d.ellipse((w - 58 if on else w - 78, yv - 10, w - 38 if on else w - 58, yv + 10), fill=(255, 255, 255, 255))
        else:
            d.rounded_rectangle((w - 150, yv - 14, w - 36, yv + 14), 7, fill=(255, 255, 255, 18))
            d.text((w - 46, yv), value, font=f16, fill=(240, 242, 255, 255), anchor="rm")
    # timeline
    ty = 520
    d.line((20, ty, w - 20, ty), fill=(255, 255, 255, 26), width=1)
    d.text((24, ty + 22), "Timeline", font=f18, fill=(245, 246, 255, 255), anchor="lm")
    button(130, ty + 6, "+  Add Layer")
    tx0, tx1, dur = 190, w - 40, 2.9
    for k in range(5):
        xk = tx0 + (tx1 - tx0) * k / 4
        d.text((xk, ty + 64), f"{dur * k / 4:.1f} s", font=f14, fill=(140, 146, 175, 255), anchor="mm")
    layers = [("Ripple", 0.0, 1.2, (96, 120, 255)), ("Incinerate", 0.9, 2.9, (255, 140, 70))]
    for k, (name, s0, s1, col) in enumerate(layers):
        yl = ty + 92 + k * 42
        d.text((40, yl + 14), name, font=f16, fill=(225, 228, 245, 255), anchor="lm")
        d.rounded_rectangle((tx0, yl, tx1, yl + 28), 6, fill=(255, 255, 255, 10))
        d.rounded_rectangle((tx0 + (tx1 - tx0) * s0 / dur, yl + 2, tx0 + (tx1 - tx0) * s1 / dur, yl + 26), 6, fill=col + (205,))
    loop_t = (t - 0.6) % 3.5 if t > 0.6 else 0.0   # the composition loops while the UI is shown
    play = clamp(loop_t, 0, dur)
    xp = tx0 + (tx1 - tx0) * play / dur
    d.line((xp, ty + 50, xp, ty + 186), fill=(255, 255, 255, 230), width=2)
    # menu after clicking Use when…
    if t > 4.85:
        m = ease_out((t - 4.85) / 0.25) * (1 - ease_io((t - 5.9) / 0.25))
        if m > 0.01:
            mx, my = w - 250, 50
            d.rounded_rectangle((mx, my, mx + 300, my + 150), 12, fill=(44, 45, 60, int(250 * m)), outline=(255, 255, 255, int(40 * m)))
            for k, item in enumerate(["When a window opens", "When a window closes", "When you minimize"]):
                yi = my + 12 + k * 44
                if k == 1 and t > 5.3: d.rounded_rectangle((mx + 8, yi, mx + 292, yi + 38), 8, fill=(110, 92, 255, int(255 * m)))
                d.text((mx + 22, yi + 19), item, font=f16, fill=(240, 242, 255, int(255 * m)), anchor="lm")
    # composite real frames into the preview area
    s = seq("studio")
    bx0, by0, bx1, by1 = s.box
    scale = 420 / (bx1 - bx0)
    im = s.frame(loop_t * FPS, scale)
    cx, cy = px0 + pw / 2, py0 + ph / 2 + 10
    clip = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    paste(clip, im, cx - px0 - (bx0 + (bx1 - bx0) / 2) * scale, cy - py0 - (by0 + (by1 - by0) / 2) * scale)
    layer.alpha_composite(clip, dest=(px0, py0))
    rise = (1 - ease_out(t / 0.7)) * 50
    paste(c, layer, x0, y0 + rise, alpha)
    # toast
    if t > 5.6:
        k = ease_out((t - 5.6) / 0.4)
        chip(c, "✓  Plays when a window closes", W / 2, y0 + h + 32 - (1 - k) * 10, k, fill=(46, 160, 100, 220), size=22)

def s_studio(c, t):
    reveal(c, "ANIMATION STUDIO", font(SF, 22, "Semibold"), W / 2, 92, t, 0.1, color=ACCENT, anchor="mm", tracking=5)
    reveal(c, "Make it yours.", font(NY, 72, "Bold"), W / 2, 162, t, 0.25, anchor="mm")
    reveal(c, "Stack 60+ Studio and built-in effects on a timeline, reverse them, and use them on close.",
           font(SF, 28, "Light"), W / 2, 232, t, 0.45, color=SOFT, anchor="mm")
    a = ease_out((t - 0.15) / 0.6)
    glow(c, W / 2, 650, 1320, 700, ACCENT, 0.3 * a)
    ui_panel(c, t, a)

def s_outro(c, t):
    e = ease_out((t - 0.2) / 1.0)
    wave_mark(c, W / 2, 250, t, e, 1.0)
    text(c, "Kinetiq", font(NY, 120, "Bold"), W / 2, 360 + (1 - e) * 24, INK, e, "mm", tracking=10)
    reveal(c, "Free and open source for macOS.", font(SF, 36, "Light"), W / 2, 460, t, 0.6, 0.8, SOFT, "mm")
    reveal(c, "Made with care by one developer. If it made you smile:", font(SF, 26, "Regular"), W / 2, 560, t, 1.3, 0.8, SOFT, "mm")
    b = back((t - 1.8) / 0.7)
    if b > 0:
        pulse = 1 + 0.025 * math.sin(max(0, t - 2.6) * 3.2)
        bw, bh = int(520 * pulse * b), int(100 * pulse * b)
        if bw > 10:
            glow(c, W / 2, 690, 520, 100, (255, 221, 0), 0.55 * clamp(b))
            btn = Image.new("RGBA", (bw, bh), (0, 0, 0, 0)); bd = ImageDraw.Draw(btn)
            bd.rounded_rectangle((0, 0, bw - 1, bh - 1), bh // 2, fill=(255, 221, 0, 255))
            f = font(SF, max(8, int(40 * pulse * b)), "Bold")
            icon = coffee_icon(max(8, int(52 * pulse * b)))
            label = "Buy me a coffee"
            tw = bd.textlength(label, font=f)
            gap = 18 * b
            total = icon.width + gap + tw
            bx = (bw - total) / 2
            btn.alpha_composite(icon, dest=(int(bx), int((bh - icon.height) / 2)))
            bd.text((bx + icon.width + gap, bh / 2), label, font=f, fill=(20, 16, 10, 255), anchor="lm")
            paste(c, btn, W / 2 - bw / 2, 690 - bh / 2, clamp(b))
    reveal(c, "buymeacoffee.com/invernomut0", font(SF, 30, "Semibold"), W / 2, 790, t, 2.3, 0.8, (255, 221, 0), "mm")
    reveal(c, "github.com/Invernomut0/Kinetiq", font(SF, 22, "Regular"), W / 2, 980, t, 2.8, 0.8, (140, 146, 175), "mm", tracking=1)

#            name          start   dur   fn
SCENES = [("intro",        0.0,   4.0,  s_intro),
          ("wobbly",       3.7,   3.9,  s_wobbly),
          ("incinerate",   7.3,   4.0,  s_incinerate),
          ("snap",        11.0,   3.3,  s_snap),
          ("montage",     14.0,   3.6,  s_montage),
          ("minimize",    17.3,   3.4,  s_minimize),
          ("liquid",      20.4,   5.0,  s_liquid),
          ("destruction", 25.1,   3.8,  s_destruction),
          ("layouts",     28.6,   5.6,  s_layouts),
          ("studio",      33.9,   7.0,  s_studio),
          ("outro",       40.6,   6.4,  s_outro)]
FADE = 0.35
TOTAL = SCENES[-1][1] + SCENES[-1][2]

def render(T):
    boost = 1.0 + 0.25 * math.exp(-((T - 41.5) / 2.5) ** 2)
    canvas = background(T, boost)
    for name, start, dur, fn in SCENES:
        if start - 0.001 <= T < start + dur:
            t = T - start
            a = clamp(t / FADE) if start > 0 else 1.0
            a = min(a, clamp((start + dur - T) / FADE)) if name != "outro" else a
            layer = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            fn(layer, t)
            if a < 0.999:
                layer.putalpha(layer.getchannel("A").point(lambda v: int(v * a)))
            canvas.alpha_composite(layer)
    # Opens on the marketing poster (it is also the player's preview frame) and
    # ends resting on the Buy me a coffee frame instead of black.
    if T < POSTER_HOLD + POSTER_FADE:
        k = ease_io((T - POSTER_HOLD) / POSTER_FADE)
        canvas = Image.blend(poster(), canvas, k)
    return canvas.convert("RGB")

POSTER_HOLD, POSTER_FADE = 0.8, 0.7
_poster = []
def poster():
    if not _poster:
        path = os.environ.get("KINETIQ_POSTER")
        _poster.append(Image.open(path).convert("RGBA").resize((W, H), Image.LANCZOS))
    return _poster[0]

if STILL:
    for s in STILL.split(","):
        render(float(s)).save(os.path.join(OUT, f"still-{float(s):05.1f}.png"))
    sys.exit(0)

frames = int(TOTAL * FPS)
cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
if AUDIO: cmd += ["-i", AUDIO, "-c:a", "aac", "-b:a", "192k", "-shortest"]
cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", "15", "-pix_fmt", "yuv420p", "-movflags", "+faststart", OUT]
p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
for i in range(frames):
    p.stdin.write(render(i / FPS).tobytes())
    if i % 150 == 0: print(f"frame {i}/{frames}", flush=True)
p.stdin.close(); p.wait()
print("done", OUT)
