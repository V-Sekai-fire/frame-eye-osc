-- SPDX-License-Identifier: MIT
/-!
# Fixed-point weights

Everything between decoding a sample and encoding an OSC float is integer arithmetic in
units of 1/10000, so the range, exclusion and symmetry theorems are about the code that
runs and not about a model of it. `Float` is opaque to the kernel. `Int` is not, and
`omega` decides the linear facts below.

Floats enter once (`ofFloat`, at decode) and leave once (`toFloat`, at OSC encode).
Those two edges are covered by `lake exe proptest` instead.
-/

namespace FrameEyeOsc

/-- One whole unit. A weight of `unit` is 1.0. -/
def unit : Int := 10000

/-- Clamp to a weight, [0, 1]. -/
def clamp01 (x : Int) : Int := max 0 (min unit x)

/-- Clamp to a signed axis, [-1, 1]. -/
def clampSym (x : Int) : Int := max (-unit) (min unit x)

theorem clamp01_nonneg (x : Int) : 0 ≤ clamp01 x := by unfold clamp01 unit; omega
theorem clamp01_le (x : Int) : clamp01 x ≤ unit := by unfold clamp01 unit; omega
theorem clamp01_of_nonpos {x : Int} (h : x ≤ 0) : clamp01 x = 0 := by unfold clamp01 unit; omega
theorem clampSym_range (x : Int) : -unit ≤ clampSym x ∧ clampSym x ≤ unit := by
  unfold clampSym unit; omega
theorem clampSym_neg (x : Int) : clampSym (-x) = -clampSym x := by unfold clampSym unit; omega

/-- Scale `x` by the weight `k`, rounding toward zero so that `scale k (-x) = -scale k x`. -/
def scale (k x : Int) : Int := (k * x).tdiv unit

theorem scale_neg (k x : Int) : scale k (-x) = -scale k x := by
  unfold scale; rw [Int.mul_neg, Int.neg_tdiv]

/-- Mean of two signed values, rounding toward zero, so it commutes with negation. -/
def mid (a b : Int) : Int := (a + b).tdiv 2

theorem mid_neg (a b : Int) : mid (-a) (-b) = -mid a b := by
  unfold mid; rw [← Int.neg_add, Int.neg_tdiv]

theorem mid_comm (a b : Int) : mid a b = mid b a := by unfold mid; rw [Int.add_comm]

/-- Saturating, NaN-safe conversion, truncating toward zero so it is odd: `ofFloat (-f) = -ofFloat f`. -/
def ofFloat (f : Float) : Int :=
  if f.isNaN then 0 else
    let g := f * 10000.0
    let g := if g > 1.0e9 then 1.0e9 else if g < -1.0e9 then -1.0e9 else g
    if g ≥ 0 then (g.floor.toUInt64.toNat : Int) else -(((-g).floor.toUInt64.toNat : Nat) : Int)

def toFloat (q : Int) : Float := Float.ofInt q / 10000.0

end FrameEyeOsc
