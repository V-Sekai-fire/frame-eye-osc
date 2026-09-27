# SPDX-License-Identifier: MIT
"""Capture the VRChat window into a ring buffer of timestamped frames, written as PNG.
Usage: vrc_ring.py HWND SECONDS OUTDIR   (keeps the last 90 s, writes them all at the end)"""
import ctypes, ctypes.wintypes as W, time, io, os, sys, collections
from PIL import Image
u32, g32 = ctypes.windll.user32, ctypes.windll.gdi32
ctypes.windll.shcore.SetProcessDpiAwareness(2)
hwnd, secs, out = int(sys.argv[1]), float(sys.argv[2]), sys.argv[3]
r = W.RECT(); u32.GetClientRect(hwnd, ctypes.byref(r)); w, h = r.right, r.bottom
hdc = u32.GetDC(hwnd); mdc = g32.CreateCompatibleDC(hdc); bmp = g32.CreateCompatibleBitmap(hdc, w, h); g32.SelectObject(mdc, bmp)
class BMI(ctypes.Structure):
    _fields_ = [("biSize", W.DWORD), ("biWidth", W.LONG), ("biHeight", W.LONG), ("biPlanes", W.WORD), ("biBitCount", W.WORD),
                ("biCompression", W.DWORD), ("biSizeImage", W.DWORD), ("a", W.LONG), ("b", W.LONG), ("c", W.DWORD), ("d", W.DWORD)]
bmi = BMI(ctypes.sizeof(BMI), w, -h, 1, 32, 0, 0, 0, 0, 0, 0)
buf = ctypes.create_string_buffer(w * h * 4)
# one wall-clock reading, then the high-resolution counter
epoch0, perf0 = time.time(), time.perf_counter()
ring = collections.deque(maxlen=int(90 * 16))  # ~90 s at the measured ~14 fps
end = perf0 + secs
while time.perf_counter() < end:
    u32.PrintWindow(hwnd, mdc, 3)
    t = epoch0 + (time.perf_counter() - perf0)          # stamp right after the grab
    g32.GetDIBits(mdc, bmp, 0, h, buf, ctypes.byref(bmi), 0)
    half = Image.frombuffer("RGBA", (w, h), buf, "raw", "BGRA", 0, 1).convert("RGB").reduce(2)
    ring.append((t, half.tobytes()))                      # raw half-res RGB; PNG-encode after capture
os.makedirs(out, exist_ok=True)
open(os.path.join(out, 'CAPTURED'), 'w').write('%.3f' % (epoch0 + (time.perf_counter() - perf0)))  # capture over; encoding follows
n = len(ring)
while ring:
    t, raw = ring.popleft()
    im = Image.frombytes("RGB", (w // 2, h // 2), raw)
    im.save(os.path.join(out, "%.3f.png" % t), compress_level=1)
print("frames", n, "fps %.1f" % (n / secs))
