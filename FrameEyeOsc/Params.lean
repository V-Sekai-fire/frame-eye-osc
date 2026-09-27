-- SPDX-License-Identifier: MIT
import FrameEyeOsc.Expressions
/-!
# Expression weights → VRCFT avatar parameters

Avatars built for VRCFaceTracking name their parameters `FT/v2/<Name>`, sometimes
without the `FT/` prefix, and older ones use the SRanipal-era v1 names. Many parameters
are also bit-packed to save synced memory: `<Name>1`, `<Name>2`, `<Name>4` … are bools
holding the bits of a quantized magnitude, and `<Name>Negative` holds the sign. This
module maps each name to its value and does that packing. VRCFT is never involved.

`plan` is built from the avatar's real parameter list (OSCQuery), so only parameters
the avatar has are sent.
-/

namespace FrameEyeOsc.Params

open FrameEyeOsc Expressions

inductive Range | unit01 | signed
  deriving Repr, DecidableEq, Inhabited

structure Param where
  name  : String
  range : Range
  get   : FrameOut → Int

private def avg (a b : Int) : Int := (a + b) / 2
private def p01 (n : String) (g : FrameOut → Int) : Param := ⟨n, .unit01, g⟩
private def pS (n : String) (g : FrameOut → Int) : Param := ⟨n, .signed, g⟩

/-- The v2 names (`FT/v2/…`). -/
def v2 : List Param := [
  pS "EyeLeftX" (·.left.x),   pS "EyeLeftY" (·.left.y),
  pS "EyeRightX" (·.right.x), pS "EyeRightY" (·.right.y),
  pS "EyeX" (·.x),            pS "EyeY" (·.y),
  p01 "EyeLidLeft" (·.left.lid), p01 "EyeLidRight" (·.right.lid),
  p01 "EyeLid" (fun o => avg o.left.lid o.right.lid),
  p01 "EyeOpennessLeft" (·.left.openness), p01 "EyeOpennessRight" (·.right.openness),
  p01 "EyeWideLeft" (·.left.wide), p01 "EyeWideRight" (·.right.wide),
  p01 "EyeWide" (fun o => avg o.left.wide o.right.wide),
  p01 "EyeSquintLeft" (·.left.squint), p01 "EyeSquintRight" (·.right.squint),
  p01 "EyeSquint" (fun o => avg o.left.squint o.right.squint),
  p01 "CheekSquintLeft" (·.left.cheekSquint), p01 "CheekSquintRight" (·.right.cheekSquint),
  p01 "CheekSquint" (fun o => avg o.left.cheekSquint o.right.cheekSquint),
  p01 "BrowLowererLeft" (·.left.browLowerer), p01 "BrowLowererRight" (·.right.browLowerer),
  p01 "BrowPinchLeft" (·.left.browPinch), p01 "BrowPinchRight" (·.right.browPinch),
  p01 "BrowInnerUpLeft" (·.left.browInnerUp), p01 "BrowInnerUpRight" (·.right.browInnerUp),
  p01 "BrowInnerUp" (fun o => avg o.left.browInnerUp o.right.browInnerUp),
  p01 "BrowOuterUpLeft" (·.left.browOuterUp), p01 "BrowOuterUpRight" (·.right.browOuterUp),
  p01 "BrowOuterUp" (fun o => avg o.left.browOuterUp o.right.browOuterUp),
  p01 "BrowUpLeft" (fun o => avg o.left.browInnerUp o.left.browOuterUp),
  p01 "BrowUpRight" (fun o => avg o.right.browInnerUp o.right.browOuterUp),
  p01 "BrowUp" (fun o => avg (avg o.left.browInnerUp o.left.browOuterUp)
                             (avg o.right.browInnerUp o.right.browOuterUp)),
  p01 "BrowDownLeft" (·.left.browLowerer), p01 "BrowDownRight" (·.right.browLowerer),
  p01 "BrowDown" (fun o => avg o.left.browLowerer o.right.browLowerer),
  pS "BrowExpressionLeft" (fun o => avg o.left.browInnerUp o.left.browOuterUp - o.left.browLowerer),
  pS "BrowExpressionRight" (fun o => avg o.right.browInnerUp o.right.browOuterUp - o.right.browLowerer) ]

/-- The v1 names, for avatars made before Unified Expressions. -/
def v1 : List Param := [
  pS "LeftEyeX" (·.left.x), pS "RightEyeX" (·.right.x),
  pS "EyesX" (·.x), pS "EyesY" (·.y),
  p01 "LeftEyeLid" (·.left.openness), p01 "RightEyeLid" (·.right.openness),
  p01 "CombinedEyeLid" (fun o => avg o.left.openness o.right.openness),
  p01 "LeftEyeWiden" (·.left.wide), p01 "RightEyeWiden" (·.right.wide),
  p01 "EyesWiden" (fun o => avg o.left.wide o.right.wide),
  p01 "LeftEyeSqueeze" (·.left.squint), p01 "RightEyeSqueeze" (·.right.squint),
  p01 "EyesSqueeze" (fun o => avg o.left.squint o.right.squint),
  pS "LeftEyeLidExpandedSqueeze" (fun o => o.left.lid - o.left.squint),
  pS "RightEyeLidExpandedSqueeze" (fun o => o.right.lid - o.right.squint) ]

-- ── Binary packing ───────────────────────────────────────────────────────────

/-- The quantized magnitude a `bits`-bit parameter carries, truncating like VRCFT. -/
def level (bits : Nat) (v : Int) : Nat :=
  (min v.natAbs unit.toNat * (2 ^ bits - 1)) / unit.toNat

def encodeBits (bits l : Nat) : List Bool := (List.range bits).map (fun i => l.testBit i)

def decodeBits (bs : List Bool) : Nat :=
  bs.foldr (fun b acc => 2 * acc + if b then 1 else 0) 0

/-- The level fits in the bits available. -/
theorem level_lt (bits : Nat) (v : Int) : level bits v < 2 ^ bits := by
  unfold level
  have hpos : 0 < 2 ^ bits := Nat.two_pow_pos bits
  have hm : min v.natAbs unit.toNat ≤ unit.toNat := Nat.min_le_right _ _
  have hu : (0 : Nat) < unit.toNat := by decide
  calc (min v.natAbs unit.toNat * (2 ^ bits - 1)) / unit.toNat
      ≤ (unit.toNat * (2 ^ bits - 1)) / unit.toNat :=
        Nat.div_le_div_right (Nat.mul_le_mul_right _ hm)
    _ = 2 ^ bits - 1 := Nat.mul_div_cancel_left _ hu
    _ < 2 ^ bits := by omega

/-- Truncation error is under one quantization step. With `m = 2^bits - 1` and the
magnitude `a = min |v| 1`, the decoded value `level/m` satisfies `level/m ≤ a < (level+1)/m`,
written without division as below. -/
theorem level_error (bits : Nat) (v : Int) :
    level bits v * unit.toNat ≤ min v.natAbs unit.toNat * (2 ^ bits - 1) ∧
    min v.natAbs unit.toNat * (2 ^ bits - 1) < (level bits v + 1) * unit.toNat := by
  unfold level
  have hu : (0 : Nat) < unit.toNat := by decide
  refine ⟨Nat.div_mul_le_self _ _, ?_⟩
  rw [Nat.add_mul, Nat.one_mul]
  exact Nat.lt_div_mul_add hu

/-- Packing and unpacking the bits gives the level back, for every width VRCFT uses. -/
theorem bits_roundtrip_1 : ∀ l : Fin 2,  decodeBits (encodeBits 1 l) = l := by decide
theorem bits_roundtrip_2 : ∀ l : Fin 4,  decodeBits (encodeBits 2 l) = l := by decide
theorem bits_roundtrip_3 : ∀ l : Fin 8,  decodeBits (encodeBits 3 l) = l := by decide
theorem bits_roundtrip_4 : ∀ l : Fin 16, decodeBits (encodeBits 4 l) = l := by decide
theorem bits_roundtrip_5 : ∀ l : Fin 32, decodeBits (encodeBits 5 l) = l := by decide
theorem bits_roundtrip_6 : ∀ l : Fin 64, decodeBits (encodeBits 6 l) = l := by decide

-- ── Matching the avatar's parameters ─────────────────────────────────────────

/-- The OSC value to send. -/
inductive Value | float (q : Int) | bool (b : Bool)
  deriving Repr, DecidableEq, Inhabited

/-- How one avatar parameter is fed. -/
inductive Feed
  | float (p : Param)
  | bit (p : Param) (bitIdx : Nat) (width : Nat)   -- width = how many bits the avatar has
  | negative (p : Param)

structure Entry where
  address : String
  feed : Feed

def paramsPrefix := "/avatar/parameters/"

private def stripPrefix? (pre s : String) : Option String :=
  if s.startsWith pre then some (s.drop pre.length).toString else none

/-- `FT/v2/EyeLid` → (true, "EyeLid"); `FT/LeftEyeLid` → (false, "LeftEyeLid"). -/
def splitName (full : String) : Option (Bool × String) := do
  let n ← stripPrefix? paramsPrefix full
  let n := (stripPrefix? "FT/" n).getD n
  match stripPrefix? "v2/" n with
  | some rest => some (true, rest)
  | none => if n.contains '/' then none else some (false, n)

private def bitSuffixes : List (String × Nat) :=
  [("128", 7), ("64", 6), ("32", 5), ("16", 4), ("8", 3), ("4", 2), ("2", 1), ("1", 0)]

private def lookup (isV2 : Bool) (name : String) : Option Param :=
  (if isV2 then v2 else v1).find? (·.name == name)

/-- Build the send list from `(fullPath, oscType)` pairs as OSCQuery reports them.
`oscType` is `"f"` for floats and `"T"`/`"F"` for bools. -/
def plan (avatarParams : List (String × String)) : List Entry :=
  let parsed := avatarParams.filterMap fun (path, ty) => do
    let (isV2, n) ← splitName path
    pure (path, ty, isV2, n)
  -- how many bit parameters each packed base has
  let width (isV2 : Bool) (base : String) : Nat :=
    (parsed.filter fun (_, ty, v, n) =>
        v == isV2 && ty != "f" && bitSuffixes.any fun (s, _) => n == base ++ s).length
  parsed.filterMap fun (path, ty, isV2, n) =>
    if ty == "f" then
      (lookup isV2 n).map fun p => { address := path, feed := .float p }
    else if n.endsWith "Negative" then
      (lookup isV2 (n.dropEnd 8).toString).map fun p => { address := path, feed := .negative p }
    else
      bitSuffixes.findSome? fun (s, idx) =>
        if n.endsWith s then
          (lookup isV2 (n.dropEnd s.length).toString).map fun p =>
            { address := path, feed := .bit p idx (width isV2 (n.dropEnd s.length).toString) }
        else none

/-- Clamp a parameter's raw value to its range. -/
def ranged (p : Param) (o : FrameOut) : Int :=
  match p.range with
  | .unit01 => clamp01 (p.get o)
  | .signed => clampSym (p.get o)

def valueOf (o : FrameOut) : Feed → Value
  | .float p => .float (ranged p o)
  | .negative p => .bool (ranged p o < 0)
  | .bit p idx width => .bool ((level width (ranged p o)).testBit idx)

/-- Every float sent is in [-1, 1], and a [0,1] parameter's in [0, 1]. -/
theorem ranged_bounds (p : Param) (o : FrameOut) :
    -unit ≤ ranged p o ∧ ranged p o ≤ unit := by
  unfold ranged
  cases p.range with
  | unit01 => have := clamp01_nonneg (p.get o); have := clamp01_le (p.get o)
              simp only; unfold unit at *; omega
  | signed => exact clampSym_range _

/-- With no avatar list (no OSCQuery), send every v2 float, as upstream frameeyeosc did. -/
def fallbackPlan (pre : String) : List Entry :=
  v2.map fun p => { address := s!"{paramsPrefix}{pre}v2/{p.name}", feed := .float p }

end FrameEyeOsc.Params
