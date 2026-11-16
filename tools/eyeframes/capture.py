# Saves the eye-camera preview frames (200x200, both eyes, ~15/s each) from eyecam's tmpfs file as PGM, plus a CSV of eyecam's own readings.
# usage: python3 eyeframes.py SECONDS OUTDIR
import mmap, os, socket, struct, sys, time
secs, out = float(sys.argv[1]), sys.argv[2]
run = "/run/user/1000/eyecam"
os.makedirs(out, exist_ok=True)
def ctl(cmd):
    s = socket.socket(socket.AF_UNIX); s.settimeout(2); s.connect(run + "/ctl.sock"); s.sendall((cmd + "\n").encode()); r = s.recv(256).decode().strip(); s.close(); return r
print("preview on:", ctl("preview on"))
csv = open(out + "/readings.csv", "w"); csv.write("eye,count,t_mono_ns,flags,pupil_x,pupil_y,pupil_r\n")
seen = {0: 0, 1: 0}; saved = 0; end = time.time() + secs; last_on = 0; m = None
while time.time() < end:
    if time.time() - last_on >= 1.0:
        ctl("preview on"); last_on = time.time()
    if m is None:
        try:
            f = open(run + "/preview", "rb"); m = mmap.mmap(f.fileno(), 0, prot=mmap.PROT_READ); f.close()
        except (FileNotFoundError, ValueError, OSError):
            time.sleep(0.05); continue
    for _ in range(4):
        s0 = struct.unpack_from("<I", m, 24)[0]
        if s0 & 1: continue
        buf = bytes(m[:81920])
        if struct.unpack_from("<I", m, 24)[0] == s0: break
    else:
        continue
    magic, ver, hs, es, w, h = struct.unpack_from("<6I", buf, 0)
    if magic != 0x56505945 or ver != 1 or struct.unpack_from("<I", buf, 48)[0] != 1: time.sleep(0.02); continue
    for e in (0, 1):
        o = hs + e * es
        t, count, flags, px, py, pr = struct.unpack_from("<QQIfff", buf, o)
        if t == 0 or count == seen[e]: continue
        seen[e] = count
        with open(f"{out}/{'LR'[e]}_{count:07d}.pgm", "wb") as g:
            g.write(f"P5\n{w} {h}\n255\n".encode() + buf[o + 64:o + 64 + w * h])
        csv.write(f"{'LR'[e]},{count},{t},{flags},{px},{py},{pr}\n"); saved += 1
    time.sleep(0.02)
print("preview off:", ctl("preview off")); print("saved", saved, "frames to", out)
