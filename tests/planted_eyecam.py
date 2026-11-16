# SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
# SPDX-License-Identifier: MIT
"""Plants one defect at a time in a scratch copy of src/eyecam.slang and runs the Lean tests.

Each mutant must make the suite fail, and the failing line must be the one named for it, so a
defect that only crashes the build or fails for another reason does not count as caught. The
unmutated tree runs first and must pass, and every mutant must change the file (the replacement
matches exactly once). Run on Linux, where the tests build: python3 tests/planted_eyecam.py
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH = os.environ.get("PLANT_DIR", "/tmp/feo-planted")

# The future-stamp guard in cam_eye has no mutant: with it removed, the unsigned p_now_ns - t wraps to
# a huge age and the frame is still refused, so that mutant is equivalent to the original.
# The seqlock retry in cam_read has no mutant: an odd sequence is refused by fe_eyecam_decode too, and a torn
# copy needs a concurrent writer, which a static file cannot make. That path is untested.
# (name, text in src/eyecam.slang, replacement, substring the failing line must contain)
MUTANTS = [
    ("magic not checked", "if (cam_u32(p_page, 0) != PAGE_MAGIC)", "if (false)", "a wrong magic is refused"),
    ("version not checked", "if (cam_u32(p_page, 4) != PAGE_VERSION)", "if (false)", "a version other than 1 is refused"),
    ("struct size not checked", "if (cam_u32(p_page, 8) < uint32_t(PAGE_BYTES))", "if (cam_u32(p_page, 8) < uint32_t(100))",
     "a struct size under 200 is refused"),
    ("odd sequence read", "if ((cam_u32(p_page, SEQ_AT) & 1) != 0)", "if (false)", "an odd sequence is refused"),
    ("idle page read", "if (cam_u32(p_page, LIVE_AT) != 1)", "if (false)", "live 0 is refused"),
    ("age edge exclusive", "p_now_ns - t > p_max_age_ns", "p_now_ns - t >= p_max_age_ns", "exactly max-age old"),
    ("unstamped frame used", "t == 0 ||", "", "a frame stamped 0 is not used"),
    ("valid flag ignored", "cam_u32(p_page, p_at + 24) != 1 ||", "", "a valid 0 eye is not used"),
    ("non-finite lid used", "if (!isfinite(lid) ||", "if (", "a non-finite value makes the eye unusable"),
    ("right eye read from the left", "page.right = cam_eye(p_page, EYE_AT + EYE_BYTES,", "page.right = cam_eye(p_page, EYE_AT,",
     "swapping the page's eyes swaps"),
    ("lid not clamped", "float lid = fe_clamp01(p_cam.lid);", "float lid = p_cam.lid;", "every output stays in 0..1"),
    ("closed flag ignored", "if (p_cam.closed == 1)\n    {\n        lid = 0.0;", "if (false)\n    {\n        lid = 0.0;",
     "the closed eye is shut"),
    ("wide kept while shut", "o.wide = o.blink > 0.0 ? 0.0 : fe_clamp01(p_cam.wide);", "o.wide = fe_clamp01(p_cam.wide);",
     "blink and wide never both nonzero"),
    ("unusable frame edits the base", "if (p_cam.usable != 1)\n    {\n        return p_base;",
     "if (p_cam.usable != 1)\n    {\n        p_base.lid = 0.0;\n        return p_base;", "an unusable frame leaves the base eye"),
    ("brows ignore heuristics off", "    if (p_heuristics)\n    {\n        o.cheek_squint", "    if (true)\n    {\n        o.cheek_squint",
     "without heuristics the squint stays"),
    ("right pupil sent to the left address", 'text_add(t, "/v2/PupilDiameterRight");', 'text_add(t, "/v2/PupilDiameterLeft");',
     "golden pupil messages", "outputs.slang"),
    ("pupil not clamped", "clamp(p_cam.pupil_mm / 10.0, 0.0, 1.0)", "p_cam.pupil_mm / 10.0", "pupil centimetres stay in 0..1"),
]


def run_tests(tests_dir):
    build = subprocess.run(["lake", "build", "tests"], cwd=tests_dir, capture_output=True, text=True)
    if build.returncode != 0:
        return None, build.stdout + build.stderr
    run = subprocess.run([os.path.join(tests_dir, ".lake/build/bin/tests")], cwd=tests_dir, capture_output=True, text=True)
    return run.returncode, run.stdout + run.stderr


def main():
    if os.path.exists(SCRATCH):
        shutil.rmtree(SCRATCH)
    shutil.copytree(ROOT, SCRATCH, ignore=shutil.ignore_patterns(".lake", "build", ".git"))
    tests_dir = os.path.join(SCRATCH, "tests")
    originals = {}
    code, out = run_tests(tests_dir)
    if code != 0:
        print("FAIL the unmutated tree does not pass; no mutant can be judged")
        print(out[-2000:])
        return 1
    clean_lines = out.count("\nok   ")
    print(f"ok   clean tree passes ({clean_lines} ok lines)")
    bad = 0
    for entry in MUTANTS:
        name, old, new, expect = entry[:4]
        target = os.path.join(SCRATCH, "src", entry[4] if len(entry) > 4 else "eyecam.slang")
        original = originals.setdefault(target, open(target).read())
        if original.count(old) != 1:
            print(f"FAIL {name}: the text to replace matches {original.count(old)} times, not once")
            bad += 1
            continue
        mutated = original.replace(old, new)
        assert mutated != original
        open(target, "w").write(mutated)
        code, out = run_tests(tests_dir)
        open(target, "w").write(original)
        failing = [line for line in out.splitlines() if line.startswith("FAIL")]
        if code is None:
            print(f"FAIL {name}: the build broke instead of the test failing")
            bad += 1
        elif code == 0:
            print(f"FAIL {name}: SURVIVED, the suite still passes")
            bad += 1
        elif not any(expect in line for line in failing):
            print(f"FAIL {name}: failed, but not on '{expect}'; failing lines: {failing[:3]}")
            bad += 1
        else:
            print(f"ok   {name}: caught by '{expect}' ({len(failing)} failing lines)")
    print(f"{len(MUTANTS)} planted defects, {bad} not caught")
    return 1 if bad else 0


sys.exit(main())
