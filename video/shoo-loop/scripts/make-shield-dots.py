#!/usr/bin/env python3
"""Samples public/shoo-logo-3x.png on a square grid and writes src/shieldDots.json: one dot per grid
cell inside the logo's silhouette, with the logo's colour there and a size from its darkness (a
halftone of the real logo). The intro's dots form the actual shield, then collapse into the logo.
Run: python3 scripts/make-shield-dots.py"""
import json
import os
import subprocess

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "..", "public", "shoo-logo-3x.png")
OUT = os.path.join(HERE, "..", "src", "shieldDots.json")
W, H = 408, 456
PITCH = 17  # px in the logo image

raw = subprocess.run(
    ["ffmpeg", "-loglevel", "error", "-i", SRC, "-f", "rawvideo", "-pix_fmt", "rgba", "-"],
    check=True,
    capture_output=True,
).stdout
img = np.frombuffer(raw, dtype=np.uint8).reshape(H, W, 4).astype(float) / 255

dots = []
for y in np.arange(PITCH / 2, H, PITCH):
    for x in np.arange(PITCH / 2, W, PITCH):
        cell = img[int(y - PITCH / 2) : int(y + PITCH / 2), int(x - PITCH / 2) : int(x + PITCH / 2)]
        a = cell[..., 3].mean()
        if a < 0.5:
            continue
        rgb = (cell[..., :3] * cell[..., 3:]).sum((0, 1)) / max(cell[..., 3].sum(), 1e-6)
        lum = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        # white areas would vanish on the sky: tint them light blue
        if lum > 0.82:
            rgb = np.array([0.62, 0.82, 0.96])
        size = 0.45 + 0.55 * (1 - min(lum, 1))
        dots.append(
            {
                "x": round(float(x - W / 2), 1),
                "y": round(float(y - H / 2), 1),
                "c": "#%02x%02x%02x" % tuple(int(v * 255) for v in rgb),
                "s": round(float(size), 3),
            }
        )
json.dump({"w": W, "h": H, "pitch": PITCH, "dots": dots}, open(OUT, "w"))
print("wrote", os.path.abspath(OUT), len(dots), "dots")
