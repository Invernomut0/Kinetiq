# Kinetiq marketing assets — how to regenerate

Everything is rendered by Kinetiq's real effect engines on fictional demo windows
(no real data). Nothing here ships with the app.

1. Copy `MarketingFramesExporter.swift.txt` to `Tests/KinetiqTests/ZZMarketingFramesTests.swift`, then:

       KINETIQ_MARKETING=/tmp/kinetiq-frames swift test --filter ZZMarketingFramesTests

   It writes PNG sequences (30 fps) for each effect into `/tmp/kinetiq-frames`.
2. Score (original, synthesized, no samples):

       python3 kinetiq_score.py /tmp/score.wav 47

3. Film (1920×1080, 30 fps, H.264 + AAC):

       python3 kinetiq_film.py /tmp/kinetiq-frames ../Kinetiq-promo.mp4 /tmp/score.wav

4. Posters:

       KINETIQ_FRAMES=/tmp/kinetiq-frames python3 posters.py ..

Requires ffmpeg, numpy and Pillow; fonts are macOS system fonts (SF Pro, New York).

## Music credit

The published `Kinetiq-promo.mp4` uses **"Eternity" by Pufino** (Free To Use Music, freetouse.com),
47 s from 1:01.1, faded in over 0.8 s and out over the last 3 s, loudness-normalized to −14 LUFS.
Credit it wherever the video is posted, e.g.:

    Music: Eternity by Pufino — Free To Use Music (freetouse.com)

The MP3 itself is not stored in this repository. To remux with it:

    ffmpeg -i Kinetiq-promo.mp4 -ss 61.1 -t 47 -i "Pufino - Eternity (freetouse.com).mp3" -map 0:v:0 -map 1:a:0 -c:v copy \
      -af "afade=t=in:st=0:d=0.8,afade=t=out:st=44:d=3,loudnorm=I=-14:TP=-1.0:LRA=11" -ar 48000 -c:a aac -b:a 256k -shortest out.mp4

`kinetiq_score.py` still produces the original synthesized score as a royalty-free alternative.
