-- SPDX-License-Identifier: MIT
import PlausibleWitnessDag
import FrameEyeOsc
/-!
# Counter-example search

Each query asks plausible-witness-dag for a candidate that breaks one claim, over
deterministic candidates derived from an index. A clean run needs two things. The real
code must come back `.provablyNone` inside the stated width. The matching broken
control must come back `.found`: a search that cannot catch a planted defect proves
nothing. `.budgetHit` is a failure, never a pass.
-/

open PlausibleWitnessDag FrameEyeOsc Expressions

/-- How far the deterministic readback looks. This, not the ladder's `finBound`, is
the width of the search, so it is stated here. -/
def searchWidth : Nat := 4000

/-- A cheap deterministic spread of integers from a candidate index. -/
def mix (c k : Nat) : Nat := (c * 2654435761 + k * 40503 + 12345) % 1000003
def signedAt (c k span : Nat) : Int := (mix c k % (2 * span + 1) : Nat) - (span : Int)

def sampleIn (c : Nat) : FrameIn :=
  { left := { openness := signedAt c 1 15000, x := signedAt c 2 20000, y := signedAt c 3 20000 }
    right := { openness := signedAt c 4 15000, x := signedAt c 5 20000, y := signedAt c 6 20000 } }
def calibAt (c : Nat) : FrameCalib :=
  { left := { closed := signedAt c 7 3000, neutral := signedAt c 8 12000, wide := signedAt c 9 15000 }
    right := { closed := signedAt c 10 3000, neutral := signedAt c 11 12000, wide := signedAt c 12 15000 } }
def gainsAt (c : Nat) : Gains :=
  { squint := signedAt c 13 30000, cheekFromSquint := signedAt c 14 30000,
    browDownFromSquint := signedAt c 15 30000, browPinchFromSquint := signedAt c 16 30000,
    browInnerFromWide := signedAt c 17 30000, browOuterFromWide := signedAt c 18 30000 }

def inU (v : Int) : Bool := 0 ≤ v && v ≤ unit
def inS (v : Int) : Bool := -unit ≤ v && v ≤ unit
def eyeOk (o : EyeOut) : Bool :=
  inS o.x && inS o.y && [o.lookUp, o.lookDown, o.lookIn, o.lookOut, o.blink, o.openness, o.wide,
    o.squint, o.lid, o.cheekSquint, o.browLowerer, o.browPinch, o.browInnerUp, o.browOuterUp].all inU

-- ── Claims, each with a control that plants the defect the claim rules out ────

/-- Range. Control: the squint co-activation without its clamp, under large gains. -/
def rangeBreaks (broken : Bool) (c : Nat) : Bool :=
  let o := frame (gainsAt c) true (calibAt c) (sampleIn c)
  let bad := !(eyeOk o.left && eyeOk o.right)
  if broken then bad || (scale (gainsAt c).squint (tent o.left.blink)) > unit else bad

/-- Blink/wide exclusion. Control: wide measured from a neutral 0.2 lower. -/
def exclusionBreaks (broken : Bool) (c : Nat) : Bool :=
  let e := sampleIn c; let k := (calibAt c).left
  let wide := if broken then wideOf { k with neutral := k.neutral - 2000 } e.left.openness else wideOf k e.left.openness
  blinkOf k e.left.openness > 0 && wide > 0

/-- Binary packing. Control: quantizing to 2^n levels instead of 2^n - 1, which overflows. -/
def binaryBreaks (broken : Bool) (c : Nat) : Bool :=
  let bits := 1 + mix c 20 % 6
  let v := signedAt c 21 12000
  let lvl := if broken then (min v.natAbs 10000 * 2 ^ bits) / 10000 else Params.level bits v
  Params.decodeBits (Params.encodeBits bits lvl) != lvl ||
    (min v.natAbs 10000 * (2 ^ bits - 1) : Nat) ≥ (lvl + 1) * 10000

/-- OSC. Control: an encoder that drops the string padding. -/
def oscBreaks (broken : Bool) (c : Nat) : Bool :=
  let addr := "/avatar/parameters/FT/v2/" ++ String.ofList ((List.range (mix c 22 % 13)).map fun i =>
    Char.ofNat (97 + (mix c (30 + i)) % 26))
  let m : Osc.Message := { address := addr, args := [.f (toFloat (signedAt c 23 10000)), .b (c % 2 == 0)] }
  let bytes := if broken then ⟨(addr.toUTF8.toList ++ [0] ++ Osc.oscString ",fT" ++
      Osc.be32 (toFloat (signedAt c 23 10000)).toFloat32.toBits).toArray⟩ else Osc.encode m
  bytes.size % 4 != 0 || Osc.decode bytes != some m

/-- Shm decode. Control: reading openness one byte late. -/
def shmBreaks (broken : Bool) (c : Nat) : Bool := Id.run do
  let mut b := (List.replicate Layout.recordSize (0 : UInt8)).toArray
  let o := Layout.offsetOf Layout.record "openness"
  let v : Float := (toFloat (signedAt c 24 10000))
  let bits := v.toFloat32.toBits
  for (x, i) in [bits.toUInt8, (bits >>> 8).toUInt8, (bits >>> 16).toUInt8, (bits >>> 24).toUInt8].zipIdx do
    b := b.set! (o + i) x
  let read := if broken then Shm.f32le ⟨b⟩ (o + 1) else ((Shm.decode ⟨b⟩).map (·.openness[0]!)).getD (0.0/0.0)
  return read.toFloat32.toBits != bits

def firstViolation (breaks : Nat → Bool) (steps : Nat) : Option Nat :=
  (List.range steps).find? breaks

def query (name : String) (breaks : Nat → Bool) : IO TraceEntry := do
  let readback : Nat → Readback (Option Nat) := fun steps =>
    match firstViolation breaks steps with
    | some w => { value := some w, found := true, witnessIdx := w, budgetHit := false }
    | none => { value := none, found := false, budgetHit := (firstViolation breaks searchWidth).isSome }
  let (_, _, trace) ← resolve name (fun _ c => breaks c) readback
  pure trace

def main : IO UInt32 := do
  let claims : List (String × (Bool → Nat → Bool)) := [
    ("weights in [0,1], axes in [-1,1]", rangeBreaks),
    ("blink and wide never both nonzero", exclusionBreaks),
    ("binary packing round-trips within one step", binaryBreaks),
    ("OSC packets word-aligned and round-trip", oscBreaks),
    ("shm decode reads the Layout offsets", shmBreaks) ]
  let mut bad := 0
  for (name, breaks) in claims do
    let real ← query name (breaks false)
    let ctl ← query s!"control: {name}" (breaks true)
    let realOk := real.outcome == .provablyNone
    let ctlOk := match ctl.outcome with | .found _ => true | _ => false
    IO.println s!"{if realOk && ctlOk then "ok  " else "FAIL"} {name}: real {repr real.outcome}, control {repr ctl.outcome}"
    unless realOk && ctlOk do bad := bad + 1
  if bad == 0 then
    IO.println s!"no counter-example in {searchWidth} candidates per claim, and every control was caught"
  return if bad == 0 then 0 else 1
