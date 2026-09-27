# SPDX-License-Identifier: MIT
"""Cue-aligned face sheet: two tiles per OPEN/CLOSE cue (1.5 s and 3.5 s after it), each cropped
around the avatar's face found by BiRefNet_HR-matting, labelled with the expected eye state.
Usage: cue_sheet.py ANNY_RENDER_CORPUS FRAMES CUES OUT.png
  ANNY_RENDER_CORPUS  checkout of 6-datasource/anny-render-corpus; its matte_refine.py is imported
  FRAMES              vrc_ring.py output dir (<epoch>.png)
  CUES                vrc_cues_voice.py stdout ("<epoch> OPEN|CLOSE" lines)
Run inside the matting-hr pixi env (torch, cv2, the BiRefNet weights)."""
import sys, os, time, numpy as np, cv2
from PIL import Image, ImageDraw, ImageFont
sys.path.insert(0, sys.argv[1]); import matte_refine as mr  # explicit dependency: anny-render-corpus/matte_refine.py
fdir, cues, out = sys.argv[2:5]
frames = sorted((float(f[:-4]), f) for f in os.listdir(fdir) if f.endswith(".png"))
ts = np.array([t for t, _ in frames])
cl = [(float(a), b) for a, b in (l.split()[:2] for l in open(cues) if len(l.split()) >= 2) if b in ("OPEN", "CLOSE")]
picks = []
for i, (t, lab) in enumerate(cl):
    nxt = cl[i + 1][0] if i + 1 < len(cl) else t + 5
    for dt in (1.5, 3.5):
        if t + dt < nxt: picks.append((t + dt, lab))
model = mr.load_model("ZhengPeng7/BiRefNet_HR-matting")
try: font = ImageFont.truetype("arial.ttf", 20)
except Exception: font = ImageFont.load_default()
tiles = []
for want, lab in picks:
    k = int(np.argmin(abs(ts - want))); t, f = frames[k]
    rgb = np.array(Image.open(os.path.join(fdir, f)).convert("RGB")); h, w = rgb.shape[:2]
    a = mr.matte(model, rgb) > 0.5
    n, cc, st, _ = cv2.connectedComponentsWithStats(a.astype(np.uint8), 8)
    cw, ch = int(w * 0.34), int(h * 0.34)
    if n > 1:
        j = 1 + int(np.argmax(st[1:, cv2.CC_STAT_AREA])); ys, xs = np.nonzero(cc == j)
        y0, y1 = ys.min(), ys.max(); lo, hi = y0 + 0.28 * (y1 - y0), y0 + 0.52 * (y1 - y0); sel = (ys >= lo) & (ys <= hi)
        cx, cy = xs[sel].mean(), 0.5 * (lo + hi)
    else:
        cx, cy = w / 2, h / 3
    x0 = int(min(max(cx - cw / 2, 0), w - cw)); y0c = int(min(max(cy - ch / 2, 0), h - ch))
    tile = Image.fromarray(rgb[y0c:y0c + ch, x0:x0 + cw]).resize((480, int(480 * ch / cw)))
    d = ImageDraw.Draw(tile)
    lt = time.strftime("%H:%M:%S", time.localtime(t)) + (".%d" % int((t % 1) * 10))
    d.rectangle((0, 0, 300, 26), fill=(0, 0, 0))
    d.text((5, 3), "%s  expect %s" % (lt, "CLOSED" if lab == "CLOSE" else "OPEN"), fill=(255, 90, 90) if lab == "CLOSE" else (120, 255, 120), font=font)
    tiles.append(tile)
cols = 4; tw, th = tiles[0].size; rows = (len(tiles) + cols - 1) // cols
s = Image.new("RGB", (cols * (tw + 4) + 4, rows * (th + 4) + 4), (30, 30, 30))
for i, t in enumerate(tiles): s.paste(t, (4 + (i % cols) * (tw + 4), 4 + (i // cols) * (th + 4)))
s.save(out); print(out, len(tiles), "tiles")
