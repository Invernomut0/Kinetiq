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
