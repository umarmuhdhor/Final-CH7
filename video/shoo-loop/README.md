# Shoo exhibition loop (Remotion)

40-beat loop for the exhibition screen with music: 1920×1080, **60 fps**, 20 s at 120 BPM
(30 frames a beat). Picture and sound both loop without a seam.

Look: the Commas "Vibe Funnels" launch film (soft sky, dots that become the logo, typed prompt, glass
cards, zoom-through cuts) in Shoo's brand blues. Rhythm: the Moolah app promo (every cut, word and
pop lands on the beat, fast in and slow out).

```bash
npm ci                                   # once
python3 scripts/make-music.py            # src/beats.json → public/audio/music.wav (needs numpy)
python3 scripts/make-shield-dots.py      # public/shoo-logo-3x.png → src/shieldDots.json (needs numpy, ffmpeg)
npm run dev                              # Remotion Studio
npx remotion render ShooLoop out/shoo-loop.mp4 --codec=h264 --crf=14 --x264-preset=slow \
  --pixel-format=yuv420p --image-format=png --audio-codec=aac --audio-bitrate=320k
```

Play it on the booth Mac with QuickTime → View → Loop (⌥⌘L), full screen.

## One beat map: `src/beats.json`
The picture (`src/timing.ts`) and the music (`scripts/make-music.py`) both read it, so a hit is on the
same frame in both. Change a beat there, re-run the music script, render.

| Beats | Picture | Sound |
|---|---|---|
| 0–8 | a halftone of the logo in dots pulses on each beat, tightens into the logo (3), S·H·O·O (4.5), tagline (6) | muffled heartbeat kick, pads opening, claps from 5, snare roll + riser |
| 8–16 | "Satu link mencurigakan…", URL typed on 16ths (9–11.75), enter on 12, scan, "Shoo memeriksanya seketika." | **drop** on 8 (impact), key ticks, enter click, scan sweep |
| 16–28 | "Diperiksa 4 lapis.": an isometric stack of plates (Shoo on top, then database, link, form, AI) opens on 17; one plate lights and lifts on 18, 20, 22, 24 with its finding (0 · +45 · +30 · +17), the score climbs to 92 and the Shoo plate turns red past 80; the stack shuts on 25.5, red flood **Diblokir.** on 26 | crash on 16, a "thock" on each card, half-beat dropout then impact + alarm on 26 |
| 28–34 | phone with the real block screen slams up (28), headline on 29 and 30, family push (31.5) | crash, two-note chime on 31 |
| 34–40 | mascot, logo, S·H·O·O, tagline, App Store badge, fade 38–40 | crash, sparkle, groove stops on 36, pads close back to the intro |

The layers follow the real pipeline (`detector/` = layers 1–2 on the phone, `ai/` = 3–4 on the server):
a brand-new scam is not in the database yet, the link and the form bring it to 75, which is inside
30–79 so the AI check runs, and its +17 makes 92 (≥ 80: blocked).

## Music
Synthesized in numpy (no samples, no generated audio): house groove in A minor (Am7 · Fmaj7 · Cadd9 ·
G), kick on every beat, claps on 2 and 4, offbeat bass and hats, chord stabs, a 16th arp with
ping-pong echo, sidechain under the kick. Everything, reverb included, is mixed circularly over the
loop length, so the outro's closing low-pass runs straight into the intro.

## Smoothness rules
- Everything is driven by the frame number, eased with `src/motion.ts`: `snap` (fast in, slow out)
  for things landing on a beat, `punch` springs for hits, a camera punch (`accent`) on the big hits.
- Scenes land on their beat and leave by zooming through the viewer in the half beat before the next.
- The backdrop moves on sine curves whose period is the whole video.
- Rendered from PNG frames, x264 `slow`, CRF 14.

Images (`public/`) are copied from `../shoo-promo/public`.

The layer scene follows the "Layered Stack" platform diagram Moty Weiss made for Cycode
(https://dribbble.com/shots/23407362-Platform-Diagram-Layered-Stack-for-Security-Platform): a closed stack
that opens into evenly spaced plates, names on the left on dotted leaders, the product on top.
