# SPDX-License-Identifier: MIT
"""Contact sheet of fixed-box crops (the mirror face) two per cue (45% and 85% into it), each
labelled with the nearest frameeyeosc --trace sample: yaw, pitch, closed, shut and the offset in frames.
Usage: trace_sheet.py FRAMES CUES TRACE OUT.png [X0 Y0 X1 Y1]
  FRAMES  vrc_ring.py output dir (<epoch>.png, half-res)
  CUES    vrc_cues_voice.py stdout ("<epoch> LABEL" lines)
  TRACE   frameeyeosc --trace file (12-column lines; t, gaze0, gaze1, closed, ..., shut)
  box     crop in half-res pixel coords, default 1000 330 1480 690 (the mirror face at 4K)"""
import os, sys, bisect, time as _t
from PIL import Image, ImageDraw
ring, cuef, tracef, out = sys.argv[1:5]; FPS = 30
tc = lambda t: (lambda lt: '%02d:%02d:%02d:%02d' % (lt.tm_hour, lt.tm_min, lt.tm_sec, int((t % 1) * FPS)))(_t.localtime(t))
cues = [(float(l.split()[0]), l.split()[1]) for l in open(cuef) if len(l.split()) >= 2]
def cue(t):
    cur = "-"
    for ct, c in cues:
        if t >= ct: cur = c
    return cur
tr = sorted(tuple(l.split()) for l in open(tracef) if len(l.split()) >= 12)
tt = [float(x[0]) for x in tr]
frames = sorted((float(f[:-4]), f) for f in os.listdir(ring) if f.endswith(".png"))
box = tuple(int(v) for v in sys.argv[5:9]) if len(sys.argv) >= 9 else (1000, 330, 1480, 690)
w, h = box[2] - box[0], box[3] - box[1]
picks = []
for i, (ct, c) in enumerate(cues[:-1]):
    nt = cues[i + 1][0]
    for frac in (0.45, 0.85):                 # mid-cue and late-cue
        want = ct + frac * (nt - ct)
        j = min(range(len(frames)), key=lambda k: abs(frames[k][0] - want)); picks.append(frames[j])
cols = 6; rows = (len(picks) + cols - 1) // cols
sheet = Image.new("RGB", (cols * w, rows * (h + 80)), "white"); d = ImageDraw.Draw(sheet)
for i, (t, f) in enumerate(picks):
    k = bisect.bisect_left(tt, t); k = min([x for x in (k - 1, k) if 0 <= x < len(tr)], key=lambda x: abs(tt[x] - t))
    r = tr[k]; x, y = (i % cols) * w, (i // cols) * (h + 80)
    sheet.paste(Image.open(os.path.join(ring, f)).crop(box), (x, y + 80))
    c = cue(t); col = (0, 90, 200) if c in ("CLOSE",) else (0, 0, 0)
    d.text((x + 6, y + 2), "%s  cue %s" % (tc(t), c), fill=col, font_size=24)
    d.text((x + 6, y + 30), "yaw %+.1f pitch %+.1f closed %.2f shut %s" % (float(r[2]), float(r[1]), float(r[3]), r[11]), fill=(180, 0, 0), font_size=20)
    d.text((x + 6, y + 56), "trace %s  offset %.1f fr" % (tc(tt[k]), abs(tt[k] - t) * FPS), fill=(0, 120, 0), font_size=17)
sheet.save(out); print(len(picks), "tiles ->", out)
