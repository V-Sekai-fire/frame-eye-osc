# SPDX-License-Identifier: MIT
"""Speak random close/open eye cues through Windows SAPI and print "<epoch> OPEN|CLOSE" per cue.
Usage: vrc_cues_voice.py [SECONDS=90] [--look]   (--look adds look left/right/straight cues: LEFT, RIGHT, OPEN)"""
import time, random, subprocess, sys
# Spoken cues through Windows SAPI (Steam Link streams PC audio to the headset).
ps = subprocess.Popen(["powershell", "-NoProfile", "-Command", "-"], stdin=subprocess.PIPE, text=True)
def say(text):
    ps.stdin.write("Add-Type -AssemblyName System.Speech; $s=New-Object System.Speech.Synthesis.SpeechSynthesizer; $s.Rate=1; try { $s.SelectVoiceByHints([System.Speech.Synthesis.VoiceGender]::Female) } catch {}; $s.SpeakAsync('%s') | Out-Null; Start-Sleep -Milliseconds 1500\n" % text); ps.stdin.flush()
args = [a for a in sys.argv[1:] if a != "--look"]; look = "--look" in sys.argv[1:]
rnd = random.Random()
secs = float(args[0]) if args else 90
plan = [("get ready, eyes open", 6)]
while sum(d for _, d in plan) < secs - 5:
    plan.append(("close your eyes", rnd.uniform(3, 9)))
    plan.append(("open your eyes", rnd.uniform(3, 8)))
if look:
    plan.insert(3, ("look left", 4)); plan.insert(4, ("look right", 4)); plan.insert(5, ("look straight ahead", 3))
plan.append(("done, thank you", 4))
def label(text):
    if text.startswith("close"): return "CLOSE"
    if text.startswith(("open", "get", "done", "look straight")): return "OPEN"
    if "left" in text: return "LEFT"
    if "right" in text: return "RIGHT"
    return text
for text, dur in plan:
    t = time.time(); say(text); print("%.3f %s" % (t, label(text)), flush=True)
    time.sleep(dur)
print("%.3f end" % time.time(), flush=True)
ps.stdin.close(); ps.wait()
