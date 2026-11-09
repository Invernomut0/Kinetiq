"""Kinetiq promotional demo: a real screen recording, the promo film and the marketing
stills, cut on the beat of the music. Usage:
  python3 kinetiq_demo.py <recording.mov> <promo.mp4> <marketing dir> <out.mp4> [music.mp3]
KINETIQ_STILL="t1,t2" writes PNG stills to <out dir> instead of a video."""
import math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import kinetiq_lib as K

REC, PROMO, MKT, OUT = sys.argv[1:5]
MUSIC = sys.argv[5] if len(sys.argv) > 5 else None
STILL = os.environ.get("KINETIQ_STILL")
W, H, FPS = 1920, 1080, 30
BEAT = 60 / 161.5            # measured tempo of the music
BAR = 4 * BEAT
MUSIC_START = 91.033         # on a beat, a few bars before the track's lift
RS = 2560 / 3234             # recording pre-scale (source px -> working px)

clamp, ease_out, ease_io = K.clamp, K.ease_out, K.ease_io

class Reader:
    """Sequential frame source; monotonic `get(t)` in segment seconds."""
    def __init__(self, path, start, dur, width, height):
        self.size = (width, height)
        self.cmd = ["ffmpeg", "-v", "error", "-ss", f"{start}", "-t", f"{dur + 0.5}", "-i", path,
                    "-vf", f"fps={FPS},scale={width}:{height}:flags=lanczos", "-f", "rawvideo", "-pix_fmt", "rgb24", "-"]
        self.proc = None; self.index = -1; self.frame = None
    def get(self, t):
        if self.proc is None:
            self.proc = subprocess.Popen(self.cmd, stdout=subprocess.PIPE)
        want = max(0, int(t * FPS))
        n = self.size[0] * self.size[1] * 3
        while self.index < want:
            data = self.proc.stdout.read(n)
            if len(data) < n: break
            self.frame = Image.frombuffer("RGB", self.size, data, "raw", "RGB", 0, 1); self.index += 1
        return self.frame
    def close(self):
        if self.proc: self.proc.kill(); self.proc = None

def rec_reader(start, dur): return Reader(REC, start, dur, 2560, int(1984 * RS) // 2 * 2)
def promo_reader(start, dur): return Reader(PROMO, start, dur, W, H)

def kenburns(frame, box0, box1, k):
    """Crop an animated box (x, y, w, h in working px, 16:9) and scale to the canvas."""
    e = ease_io(k)
    x, y, w, h = [a + (b - a) * e for a, b in zip(box0, box1)]
    x = clamp(x, 0, frame.width - w); y = clamp(y, 0, frame.height - h)
    return frame.crop((int(x), int(y), int(x + w), int(y + h))).resize((W, H), Image.LANCZOS)

def path_box(keys, t):
    ts = [k[0] for k in keys]
    cx, cy, w = (float(np.interp(t, ts, [k[i] for k in keys])) for i in (1, 2, 3))
    return box(cx, cy, w)

def box(cx, cy, w):  # source-px centre and width -> working-px 16:9 box
    w *= RS; h = w * 9 / 16
    return (cx * RS - w / 2, cy * RS - h / 2, w, h)

_scrim = []
def scrim(c, strength=1.0):
    if not _scrim:
        g = np.zeros((H, W), np.float32)
        yy = np.linspace(0, 1, H)[:, None]; xx = np.linspace(0, 1, W)[None, :]
        g = np.clip((yy - 0.45) / 0.55, 0, 1) ** 1.6 * 0.85 + np.clip((0.55 - xx) / 0.55, 0, 1) ** 2 * np.clip((yy - 0.3) / 0.7, 0, 1) * 0.35
        a = (np.clip(g, 0, 0.9) * 255).astype(np.uint8)
        layer = Image.new("RGBA", (W, H), (6, 7, 16, 0)); layer.putalpha(Image.fromarray(a))
        _scrim.append(layer)
    K.paste(c, _scrim[0], 0, 0, strength)

def caption(c, t, over, title, sub=None, x=110, y=800):
    K.reveal(c, over, K.font(K.SF, 24, "Semibold"), x, y, t, 0.05, 0.35, K.ACCENT, tracking=5, rise=14)
    K.reveal(c, title, K.font(K.NY, 92, "Bold"), x, y + 44, t, 0.12, 0.35, rise=30)
    if sub: K.reveal(c, sub, K.font(K.SF, 32, "Light"), x, y + 160, t, 0.3, 0.4, K.SOFT, rise=14)

def live_badge(c, t, ox=0, oy=0):
    a = ease_out(t / 0.3)
    layer = Image.new("RGBA", (W, H), (0, 0, 0, 0)); d = ImageDraw.Draw(layer)
    d.rounded_rectangle((60 + ox, 54 + oy, 410 + ox, 104 + oy), 25, fill=(10, 10, 18, int(190 * a)))
    blink = 0.6 + 0.4 * math.sin(t * 6)
    d.ellipse((80 + ox, 69 + oy, 100 + ox, 89 + oy), fill=(255, 70, 70, int(255 * a * blink)))
    d.text((114 + ox, 79 + oy), "RECORDED LIVE ON macOS", font=K.font(K.SF, 22, "Semibold"), fill=(240, 242, 255, int(255 * a)), anchor="lm")
    c.alpha_composite(layer)

def punch(img, t, amount=0.06, dur=0.28):
    """Beat hit: the shot starts slightly enlarged and snaps into place."""
    k = 1 + amount * (1 - ease_out(t / dur))
    if k <= 1.0005: return img
    w, h = int(W * k), int(H * k)
    big = img.resize((w, h), Image.BICUBIC)
    return big.crop(((w - W) // 2, (h - H) // 2, (w - W) // 2 + W, (h - H) // 2 + H))

def flash(img, t, strength=0.55, dur=0.12):
    k = strength * (1 - clamp(t / dur))
    return Image.blend(img, Image.new(img.mode, img.size, (255, 255, 255) if img.mode == "RGB" else (255, 255, 255, 255)), k) if k > 0.01 else img

_stills = {}
def still(name):
    if name not in _stills: _stills[name] = Image.open(os.path.join(MKT, name)).convert("RGBA")
    return _stills[name]

# ---------------------------------------------------------------- scenes
class Scene:
    def __init__(self, bars, fn, hit=False, flash=False, reader=None):
        self.dur = bars * BAR; self.fn = fn; self.hit = hit; self.flash = flash; self.reader = reader

CARD = (260, 46, 1400, 788)   # framed layout for UI footage: x, y, w, h

_card_mask = {}
def card_frame(c, shot, t):
    x, y, w, h = CARD
    if "m" not in _card_mask:
        m = Image.new("L", (w, h), 0); ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, h - 1), 26, fill=255)
        _card_mask["m"] = m
    k = ease_out(t / 0.45)
    K.glow(c, x + w / 2, y + h / 2, w, h, K.ACCENT, 0.55 * k)
    im = shot.resize((w, h), Image.LANCZOS).convert("RGBA"); im.putalpha(_card_mask["m"])
    edge = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    ImageDraw.Draw(edge).rounded_rectangle((0, 0, w - 1, h - 1), 26, outline=(255, 255, 255, 60), width=2)
    im.alpha_composite(edge)
    K.paste(c, im, x, y + (1 - k) * 60, k)

def recording(start, dur, keys, speed=1.0, over="", title="", sub=None, cap_delay=0.2, framed=False):
    """keys: [(segment seconds, cx, cy, width)] camera path in source pixels."""
    reader = rec_reader(start, dur * speed + 0.2)
    def fn(t, total):
        frame = reader.get(t * speed)
        shot = kenburns(frame, path_box(keys, t * speed), path_box(keys, t * speed), 0)
        if framed:
            img = K.background(20 + t, 1.1)
            card_frame(img, shot, t)
            tc = t - cap_delay
            K.reveal(img, over, K.font(K.SF, 22, "Semibold"), W / 2, 872, tc, 0.05, 0.35, K.ACCENT, "ma", tracking=5, rise=12)
            K.reveal(img, title, K.font(K.NY, 70, "Bold"), W / 2, 906, tc, 0.12, 0.35, anchor="ma", rise=24)
            if sub: K.reveal(img, sub, K.font(K.SF, 28, "Light"), W / 2, 1000, tc, 0.3, 0.4, K.SOFT, "ma", rise=12)
            live_badge(img, t, CARD[0] + CARD[2] - 410, CARD[1] - 34 + 0)
            return img
        img = shot.convert("RGBA")
        scrim(img)
        live_badge(img, t)
        if title: caption(img, t - cap_delay, over, title, sub)
        return img
    return fn, reader

def promo(start, dur):
    reader = promo_reader(start, dur + 0.2)
    def fn(t, total):
        return reader.get(t).convert("RGBA")
    return fn, reader

def slam(t, total):
    c = K.background(30 + t, 1.2)
    k = ease_out(t / 0.22)
    K.text(c, "Real windows.", K.font(K.NY, 150, "Bold"), W / 2, 450 - (1 - k) * 40, K.INK, k, "mm")
    k2 = ease_out((t - BEAT * 2) / 0.22)
    K.text(c, "Real effects.", K.font(K.NY, 150, "Bold"), W / 2, 630 - (1 - k2) * 40, (190, 175, 255), k2, "mm")
    return c

def poster(t, total):
    """Hero still, slow push-out to full frame."""
    img = still("Kinetiq-hero-2560x1440.png")
    k = 1.10 - 0.10 * ease_out(t / total)
    win_w, win_h = img.width / k, img.height / k
    x, y = (img.width - win_w) / 2, (img.height - win_h) / 2
    return img.crop((int(x), int(y), int(x + win_w), int(y + win_h))).resize((W, H), Image.LANCZOS)

def studio_still(t, total):
    c = K.background(36 + t, 1.0)
    im = still("Kinetiq-animation-studio-1920x1080.png")
    k = 1.06 - 0.06 * ease_out(t / total)
    big = im.resize((int(W * k), int(H * k)), Image.LANCZOS)
    K.paste(c, big, (W - big.width) / 2, (H - big.height) / 2)
    return c

def burst(t, total):
    """Three marketing stills fly in on consecutive beats."""
    c = K.background(40 + t, 1.15)
    K.reveal(c, "EVERYTHING, IN ONE MENU BAR APP", K.font(K.SF, 24, "Semibold"), W / 2, 96, t, 0.0, 0.3, K.ACCENT, "mm", tracking=5, rise=12)
    cards = [("Kinetiq-close-effects-1080.png", 330, 600, 560, -5), ("Kinetiq-layouts-1920x1080.png", 960, 560, 760, 0),
             ("Kinetiq-animation-studio-1920x1080.png", 1590, 600, 620, 5)]
    for i, (name, cx, cy, width, angle) in enumerate(cards):
        k = K.back((t - i * BEAT) / 0.35)
        if k <= 0: continue
        im = still(name); h = int(im.height * width / im.width)
        card = Image.new("RGBA", (width + 24, h + 24), (0, 0, 0, 0))
        card.alpha_composite(im.resize((width, h), Image.LANCZOS), dest=(12, 12))
        mask = Image.new("L", card.size, 0); ImageDraw.Draw(mask).rounded_rectangle((12, 12, 12 + width, 12 + h), 18, fill=255)
        card.putalpha(Image.eval(mask, lambda v: v))
        card = card.rotate(angle * (1 - 0.3 * clamp(k)), resample=Image.BICUBIC, expand=True)
        sc = 0.7 + 0.3 * k
        card = card.resize((max(1, int(card.width * sc)), max(1, int(card.height * sc))), Image.BICUBIC)
        K.glow(c, cx, cy, width, h, K.ACCENT, 0.4 * clamp(k))
        K.paste(c, card, cx - card.width / 2, cy - card.height / 2 + (1 - clamp(k)) * 120, clamp(k))
    K.reveal(c, "Free and open source for macOS 14+", K.font(K.SF, 34, "Light"), W / 2, 985, t, 3 * BEAT, 0.4, K.SOFT, "mm")
    return c

def build():
    scenes = []
    def add(bars, fn_reader, **kw):
        fn, reader = fn_reader if isinstance(fn_reader, tuple) else (fn_reader, None)
        scenes.append(Scene(bars, fn, reader=reader, **kw))
    add(2, poster)
    add(1.5, slam, hit=True, flash=True)
    add(3, recording(34.0, 3 * BAR, [(0, 1250, 1280, 2500), (0.5, 1300, 1300, 2500), (1.5, 1650, 1330, 2550),
                                     (2.5, 1950, 1250, 2550), (3.5, 2100, 1200, 2500), (5, 2100, 1200, 2500)],
                     1.0, "WOBBLY WINDOWS", "Drag it. It wobbles.", "A real spring mesh, like Compiz."), hit=True, flash=True)
    add(2.5, recording(50.9, 2.5 * BAR, [(0, 900, 1170, 2100), (3.2, 820, 1120, 1800)], 0.85,
                       "MY EFFECT · RIPPLE → INCINERATE", "Close it with fire.", "Made in the Animation Studio."), hit=True)
    add(2, promo(11.35, 2 * BAR), hit=True)
    add(2, promo(14.55, 2 * BAR), hit=True)
    add(2.5, recording(39.7, 2.5 * BAR, [(0, 2050, 1180, 2400), (1.5, 1950, 1280, 2700), (4.5, 1900, 1350, 2800)], 1.0,
                     "WINDOW DESTRUCTION", "Let it fall apart.", "Letters drop, then the glass shatters."), hit=True, flash=True)
    add(2, promo(17.75, 2 * BAR), hit=True)
    add(2, promo(21.0, 2 * BAR), hit=True)
    add(3, recording(2.0, 3 * BAR, [(0, 2250, 640, 1960), (12, 2290, 600, 1900)], 12.0 / (3 * BAR),
                     "EFFECTS LIBRARY", "66 effects. Live previews.", "Pick what plays when you drag, open, close or minimize.",
                     framed=True), hit=True)
    add(2.5, recording(17.6, 2.5 * BAR, [(0, 2250, 640, 1960), (3.8, 2290, 620, 1900)], 1.0,
                       "ANIMATION STUDIO", "Build your own.", "Layer effects, reverse them, keyframe them.", framed=True), hit=True)
    add(2, studio_still, hit=True)
    add(3, promo(29.0, 3 * BAR), hit=True)
    add(3, burst, hit=True, flash=True)
    add(4.4, promo(40.6, 4.4 * BAR), hit=True)
    return scenes

def main():
    scenes = build()
    starts = np.cumsum([0] + [s.dur for s in scenes])
    total = float(starts[-1])
    def frame_at(T):
        i = int(np.searchsorted(starts, T, side="right") - 1); i = min(i, len(scenes) - 1)
        s = scenes[i]; t = T - starts[i]
        img = s.fn(t, s.dur).convert("RGB")
        if s.hit: img = punch(img, t)
        if s.flash: img = flash(img, t)
        return img, i
    if STILL:
        for v in STILL.split(","):
            T = float(v)
            # readers are sequential: build a fresh scene list per still
            img, _ = frame_at(T); img.save(os.path.join(OUT, f"demo-{T:05.2f}.png"))
            for s in scenes:
                if s.reader: s.reader.close(); s.reader.proc = None; s.reader.index = -1
        return
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{W}x{H}", "-r", str(FPS), "-i", "-"]
    if MUSIC:
        fade_out = total - 2.2
        cmd += ["-ss", f"{MUSIC_START}", "-t", f"{total}", "-i", MUSIC, "-af",
                f"afade=t=in:st=0:d=0.25,afade=t=out:st={fade_out:.2f}:d=2.2,loudnorm=I=-14:TP=-1.0:LRA=11",
                "-ar", "48000", "-c:a", "aac", "-b:a", "256k", "-shortest"]
    cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", "16", "-pix_fmt", "yuv420p", "-movflags", "+faststart",
            "-metadata", "comment=Music: Eternity by Pufino (Free To Use Music, freetouse.com)", OUT]
    p = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    n = int(total * FPS); current = -1
    for f in range(n):
        img, i = frame_at(f / FPS)
        if i != current:
            if current >= 0 and scenes[current].reader: scenes[current].reader.close()
            current = i
        p.stdin.write(img.tobytes())
        if f % 150 == 0: print(f"frame {f}/{n}  scene {i}", flush=True)
    p.stdin.close(); p.wait()
    print("done", OUT, f"{total:.2f}s")

if __name__ == "__main__":
    main()
