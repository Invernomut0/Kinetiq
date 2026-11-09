"""Original ambient score for the Kinetiq film, synthesized from scratch (no samples)."""
import sys, wave
import numpy as np

SR = 48000
TOTAL = float(sys.argv[2]) if len(sys.argv) > 2 else 47.0
n = int(SR * TOTAL)
t = np.arange(n) / SR
L = np.zeros(n); R = np.zeros(n)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

# Am9 - Fmaj7 - Cmaj7(add9) - G6, 4 bars of 5.75 s, twice
chords = [[45, 57, 60, 64, 67, 71], [41, 53, 57, 60, 64, 69], [48, 55, 59, 62, 64, 67], [43, 55, 59, 62, 64, 66]]
bar = 5.75
rng = np.random.default_rng(3)

def env(start, dur, attack, release):
    e = np.zeros(n)
    i0, i1 = int(start * SR), min(n, int((start + dur + release) * SR))
    if i0 >= n: return e
    x = (np.arange(i0, i1) / SR) - start
    a = np.clip(x / attack, 0, 1)
    r = np.clip((start + dur + release - (x + start)) / release, 0, 1)
    e[i0:i1] = np.minimum(a, r) ** 1.6
    return e

# Pad: detuned soft saws (sum of harmonics with 1/k^1.6 rolloff), slow swell, stereo detune.
k = 0
start = 0.0
while start < TOTAL:
    notes = chords[k % 4]
    e = env(start, bar, 2.2, 2.8)
    for m in notes:
        f = hz(m)
        for det, side in ((-0.06, 0), (0.06, 1)):
            ff = f * 2 ** (det / 12)
            vib = 1 + 0.0025 * np.sin(2 * np.pi * 0.21 * t + m)
            sig = sum(np.sin(2 * np.pi * ff * h * t * vib) / h ** 1.7 for h in range(1, 6))
            amp = 0.020 if m > 50 else 0.032
            (L if side == 0 else R)[:] += sig * e * amp
    start += bar; k += 1

# Sub bass on chord roots
start, k = 0.0, 0
while start < TOTAL:
    e = env(start, bar, 0.8, 1.5)
    root = hz(chords[k % 4][0] - 12)
    s = np.sin(2 * np.pi * root * t) * 0.07 * e
    L += s; R += s
    start += bar; k += 1

# Glassy arpeggio plucks from 3.7 s (when the effects start), 8ths at 104 bpm, echoing.
step = 60 / 104 / 2
pattern = [0, 2, 3, 4, 3, 2, 5, 4]
i = 0; t0 = 3.7
while t0 < TOTAL - 5:
    chord = chords[int(t0 // bar) % 4]
    m = chord[1 + pattern[i % 8] % (len(chord) - 1)] + 12
    f = hz(m)
    i0 = int(t0 * SR); i1 = min(n, i0 + int(1.6 * SR))
    x = np.arange(i1 - i0) / SR
    pl = (np.sin(2 * np.pi * f * x) + 0.35 * np.sin(2 * np.pi * 2 * f * x) + 0.12 * np.sin(2 * np.pi * 3.01 * f * x)) * np.exp(-x * 4.2) * 0.035
    pan = 0.5 + 0.35 * np.sin(i * 0.9)
    for delay, gain in ((0, 1.0), (step * 3, 0.42), (step * 6, 0.18)):
        j0 = i0 + int(delay * SR); j1 = min(n, j0 + len(pl))
        if j0 < n:
            L[j0:j1] += pl[: j1 - j0] * gain * (1 - pan) * 2
            R[j0:j1] += pl[: j1 - j0] * gain * pan * 2
    t0 += step; i += 1

# Soft whooshes at scene changes: filtered noise with a rising/falling envelope.
cuts = [3.7, 7.3, 11.0, 14.0, 17.3, 20.4, 25.1, 28.6, 33.9, 40.6]
for c in cuts:
    i0 = int((c - 0.45) * SR); i1 = min(n, int((c + 0.5) * SR))
    x = np.arange(i1 - i0) / SR
    noise = rng.standard_normal(i1 - i0)
    # crude band-pass: difference of two moving averages
    a = np.convolve(noise, np.ones(18) / 18, "same"); b = np.convolve(noise, np.ones(140) / 140, "same")
    w = (a - b) * np.sin(np.pi * x / x[-1]) ** 2 * 0.06
    L[i0:i1] += w * 0.9; R[i0:i1] += w * 1.1

# Final shimmer on the Buy me a coffee reveal (42.4 s): a bright Cmaj9 bell chord.
for m, d in zip([72, 76, 79, 83, 86], [0, 0.07, 0.14, 0.21, 0.28]):
    i0 = int((42.4 + d) * SR); i1 = min(n, i0 + int(4 * SR))
    x = np.arange(i1 - i0) / SR
    bell = (np.sin(2 * np.pi * hz(m) * x) + 0.3 * np.sin(2 * np.pi * hz(m) * 2.76 * x)) * np.exp(-x * 1.1) * 0.03
    L[i0:i1] += bell; R[i0:i1] += bell

# Simple stereo reverb: a few decaying taps.
for d, g in ((0.031, 0.35), (0.047, 0.3), (0.073, 0.22), (0.11, 0.16), (0.17, 0.1)):
    s = int(d * SR)
    L[s:] += R[:-s] * g; R[s:] += L[:-s] * g * 0.9

# Master: fade in/out, soft clip, normalize to -1 dBFS peak.
master = np.minimum(np.clip(t / 1.2, 0, 1), np.clip((TOTAL - t) / 2.5, 0, 1))
L *= master; R *= master
st = np.stack([L, R], 1)
st = np.tanh(st * 1.4) / np.tanh(1.4)
st *= 0.89 / np.max(np.abs(st))
pcm = (st * 32767).astype(np.int16)
with wave.open(sys.argv[1], "wb") as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print("score", sys.argv[1], TOTAL)
