# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: MIT
"""Converts captured eye frames (PGM) to lossless WebP and deletes each PGM only after the WebP decodes to the same bytes.

usage: python3 to_webp.py DIR      (every DIR/*.pgm)
       python3 to_webp.py --self-test
"""
import glob
import io
import os
import sys

from PIL import Image


def encode(img, lossless=True):
    out = io.BytesIO()
    img.save(out, "WEBP", lossless=lossless, quality=100, method=6, exact=True)
    return out.getvalue()


def same_pixels(img, webp_bytes):
    """WebP keeps gray as RGB, so the three channels must be equal to each other and to the source."""
    back = Image.open(io.BytesIO(webp_bytes)).convert("RGB")
    if back.size != img.size:
        return False
    r, g, b = back.split()
    return r.tobytes() == g.tobytes() == b.tobytes() == img.convert("L").tobytes()


def convert(directory):
    done = failed = 0
    for path in sorted(glob.glob(os.path.join(directory, "*.pgm"))):
        img = Image.open(path)
        img.load()
        data = encode(img)
        if not same_pixels(img, data):
            print("FAIL not lossless:", path)
            failed += 1
            continue
        with open(path[:-4] + ".webp", "wb") as f:
            f.write(data)
        os.remove(path)
        done += 1
    print(f"{done} converted, {failed} failed")
    return 1 if failed else 0


def self_test():
    import random
    rng = random.Random(7)
    noise = Image.frombytes("L", (200, 200), bytes(rng.randrange(256) for _ in range(200 * 200)))
    ramp = Image.frombytes("L", (200, 200), bytes((x + y) % 256 for y in range(200) for x in range(200)))
    bad = 0
    for name, img in (("noise", noise), ("ramp", ramp)):
        ok = same_pixels(img, encode(img, True))
        control = same_pixels(img, encode(img, False))
        print(("ok  " if ok and not control else "FAIL"), f"{name}: lossless round-trips {ok}; lossy control round-trips {control} (must be False)")
        bad += 0 if ok and not control else 1
    print(f"2 images, {bad} failures")
    return 1 if bad else 0


sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else convert(sys.argv[1]))
