-- SPDX-License-Identifier: MIT
import Lean.Data.Json
import FrameEyeOsc.Expressions
/-!
# Openness calibration and the gains file

Raw openness differs per person and per fit. Blink and wide are measured against a
per-eye "relaxed open" level that tracks the wearer:

* `neutral` follows a slow average of openness, ignoring samples well below it (blinks);
* `wide` is the highest openness seen, decaying slowly back toward `neutral`;
* `closed` stays at the configured floor.

The state persists in `~/.config/frameeyeosc/calib.json`. `Expressions.Calib.norm`
guarantees an ordering, so no value read from disk can make the mapping divide by zero.
-/

namespace FrameEyeOsc.Calib

open Lean FrameEyeOsc Expressions

/-- One sample's update of one eye. Integer arithmetic, 1/10000 units. -/
def step (c : Calib) (o : Int) : Calib :=
  let neutral := if o > c.neutral - 2000 then c.neutral + (o - c.neutral) / 512 else c.neutral
  let wide := if o > c.wide then o else max (neutral + 500) (c.wide - 1)
  { c with neutral, wide }

def stepFrame (c : FrameCalib) (f : FrameIn) : FrameCalib :=
  { left := step c.left f.left.openness, right := step c.right f.right.openness }

instance : ToJson Calib := ⟨fun c => json% {closed: $(c.closed), neutral: $(c.neutral), wide: $(c.wide)}⟩
instance : FromJson Calib := ⟨fun j => do
  return { closed := ← j.getObjValAs? Int "closed", neutral := ← j.getObjValAs? Int "neutral",
           wide := ← j.getObjValAs? Int "wide" }⟩
instance : ToJson FrameCalib := ⟨fun c => json% {left: $(c.left), right: $(c.right)}⟩
instance : FromJson FrameCalib := ⟨fun j => do
  return { left := ← j.getObjValAs? Calib "left", right := ← j.getObjValAs? Calib "right" }⟩

def path : IO System.FilePath := do
  let home := (← IO.getEnv "HOME").getD "."
  return System.FilePath.mk home / ".config" / "frameeyeosc" / "calib.json"

def load : IO FrameCalib := do
  try
    let j ← IO.ofExcept (Json.parse (← IO.FS.readFile (← path)))
    IO.ofExcept (fromJson? j)
  catch _ => return {}

def save (c : FrameCalib) : IO Unit := do
  let p ← path
  if let some d := p.parent then IO.FS.createDirAll d
  IO.FS.writeFile p ((toJson c).pretty ++ "\n")

/-- `data/eye_facial_action.json`: the co-activation gains, with defaults for missing keys. -/
def loadGains (p : System.FilePath) : IO Gains := do
  let d : Gains := {}
  let j ← try IO.ofExcept (Json.parse (← IO.FS.readFile p)) catch _ => return d
  let g (k : String) (dflt : Int) : Int :=
    match j.getObjValAs? Float k with
    | .ok f => (f * 10000.0).round.toInt64.toInt
    | .error _ => dflt
  return { squint := g "eyeSquint_from_partial_closure" d.squint
           cheekFromSquint := g "cheekSquint_from_eyeSquint" d.cheekFromSquint
           browDownFromSquint := g "browDown_from_eyeSquint" d.browDownFromSquint
           browPinchFromSquint := g "browPinch_from_eyeSquint" d.browPinchFromSquint
           browInnerFromWide := g "browInnerUp_from_eyeWide" d.browInnerFromWide
           browOuterFromWide := g "browOuterUp_from_eyeWide" d.browOuterFromWide }

end FrameEyeOsc.Calib
