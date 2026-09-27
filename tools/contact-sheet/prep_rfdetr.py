# SPDX-License-Identifier: MIT
"""Pick one ring frame every 3 s (from 1 s after the first) and write it as an RF-DETR input tensor:
312x312, ImageNet-normalised, CHW float32 raw (<epoch>.f32), plus frames.txt listing them.
Usage: prep_rfdetr.py FRAMES OUTDIR"""
import os, sys, numpy as np
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
frames = sorted(f for f in os.listdir(src) if f.endswith(".png"))
t0 = float(frames[0][:-4]); picks, want = [], t0 + 1.0
for f in frames:
    if float(f[:-4]) >= want:
        picks.append(f); want += 3.0
mean = np.array([0.485, 0.456, 0.406], np.float32); std = np.array([0.229, 0.224, 0.225], np.float32)
paths = []
for f in picks:
    im = Image.open(os.path.join(src, f)).convert("RGB").resize((312, 312), Image.BILINEAR)
    a = (np.asarray(im, np.float32) / 255.0 - mean) / std
    p = os.path.join(out, f[:-4] + ".f32"); a.transpose(2, 0, 1).astype(np.float32).tofile(p); paths.append(p)
open(os.path.join(out, "frames.txt"), "w").write("\n".join(paths) + "\n")
print(len(paths), "frames ->", out)
