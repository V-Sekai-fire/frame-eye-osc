-- SPDX-License-Identifier: MIT
import FrameEyeOsc.Fixed
/-!
# Eye sample → expression weights

The Frame measures gaze and eyelid openness per eye. It has no face cameras, so the
mouth, jaw, cheek-puff and tongue shapes are not produced at all, and none are faked.

The vocabulary is the eye and brow subset of the 52 facial-action blendshapes that the
anny body model carries (`anny/src/anny/models/facial_actions.py`), with the Unified
Expressions names they map onto:

| measured or derived | anny label                 | Unified Expressions      |
|---------------------|----------------------------|--------------------------|
| gaze                | eyeLook{Up,Down,In,Out}*   | EyeX/EyeY per eye        |
| openness < neutral  | eyeBlink*                  | EyeOpenness, EyeLid      |
| openness > neutral  | eyeWide*                   | EyeWide                  |
| partial closure     | eyeSquint*                 | EyeSquint                |
| squint (heuristic)  | cheekSquint*, browDown*    | CheekSquint, BrowLowerer, BrowPinch |
| wide (heuristic)    | browInnerUp, browOuterUp*  | BrowInnerUp, BrowOuterUp |

The heuristic rows are the facial-action co-activations. They can be switched off, and
their gains come from `data/eye_facial_action.json`. Every theorem below holds for
every value of those gains.
-/

namespace FrameEyeOsc.Expressions

open FrameEyeOsc

/-- One eye, already in fixed point: `openness` as reported, gaze angles in [-1, 1]. -/
structure EyeIn where
  openness : Int
  x : Int
  y : Int
  deriving Repr, DecidableEq, Inhabited

/-- Per-eye openness calibration: fully closed, relaxed open, and wide open. -/
structure Calib where
  closed  : Int := 0
  neutral : Int := 7500
  wide    : Int := 10000
  deriving Repr, DecidableEq, Inhabited

/-- Force `closed < neutral < wide`, so neither denominator below can be zero. -/
def Calib.norm (c : Calib) : Calib :=
  { closed := min c.closed (c.neutral - 1), neutral := c.neutral, wide := max c.wide (c.neutral + 1) }

/-- Gains for the heuristic co-activations, in units of 1/10000. -/
structure Gains where
  squint             : Int := 10000
  cheekFromSquint    : Int := 6000
  browDownFromSquint : Int := 5000
  browPinchFromSquint: Int := 3000
  browInnerFromWide  : Int := 7000
  browOuterFromWide  : Int := 8000
  deriving Repr, DecidableEq, Inhabited

inductive Side | left | right
  deriving Repr, DecidableEq, Inhabited

structure EyeOut where
  x : Int
  y : Int
  lookUp : Int
  lookDown : Int
  lookIn : Int
  lookOut : Int
  blink : Int
  openness : Int
  wide : Int
  squint : Int
  lid : Int              -- VRCFT's EyeLid: 0 closed, 0.75 relaxed, 1 wide
  cheekSquint : Int
  browLowerer : Int
  browPinch : Int
  browInnerUp : Int
  browOuterUp : Int
  deriving Repr, DecidableEq, Inhabited

def blinkOf (c : Calib) (o : Int) : Int :=
  if o < c.norm.neutral then clamp01 ((c.norm.neutral - o) * unit / (c.norm.neutral - c.norm.closed)) else 0

def wideOf (c : Calib) (o : Int) : Int :=
  if c.norm.neutral < o then clamp01 ((o - c.norm.neutral) * unit / (c.norm.wide - c.norm.neutral)) else 0

/-- Peaks at half closure, zero when fully open or fully shut. -/
def tent (b : Int) : Int := 2 * min b (unit - b)

def eye (side : Side) (g : Gains) (heuristics : Bool) (c : Calib) (e : EyeIn) : EyeOut :=
  let x := clampSym e.x
  let y := clampSym e.y
  let nasal := match side with | .left => x | .right => -x
  let blink := blinkOf c e.openness
  let wide := wideOf c e.openness
  let squint := if heuristics then clamp01 (scale g.squint (tent blink)) else 0
  let co (k v : Int) := if heuristics then clamp01 (scale k v) else 0
  { x, y
    lookUp := clamp01 y, lookDown := clamp01 (-y)
    lookIn := clamp01 nasal, lookOut := clamp01 (-nasal)
    blink, wide, squint
    openness := clamp01 (unit - blink)
    lid := clamp01 ((unit - blink) * 3 / 4 + wide / 4)
    cheekSquint := co g.cheekFromSquint squint
    browLowerer := co g.browDownFromSquint squint
    browPinch   := co g.browPinchFromSquint squint
    browInnerUp := co g.browInnerFromWide wide
    browOuterUp := co g.browOuterFromWide wide }

structure FrameIn where
  left : EyeIn
  right : EyeIn
  deriving Repr, DecidableEq, Inhabited

structure FrameCalib where
  left : Calib := {}
  right : Calib := {}
  deriving Repr, DecidableEq, Inhabited

structure FrameOut where
  left : EyeOut
  right : EyeOut
  x : Int          -- combined gaze
  y : Int
  deriving Repr, DecidableEq, Inhabited

def frame (g : Gains) (heuristics : Bool) (c : FrameCalib) (f : FrameIn) : FrameOut :=
  let l := eye .left g heuristics c.left f.left
  let r := eye .right g heuristics c.right f.right
  { left := l, right := r, x := mid l.x r.x, y := mid l.y r.y }

-- ── Range ────────────────────────────────────────────────────────────────────

def w01 (v : Int) : Prop := 0 ≤ v ∧ v ≤ unit
def wSym (v : Int) : Prop := -unit ≤ v ∧ v ≤ unit

def EyeOut.valid (o : EyeOut) : Prop :=
  wSym o.x ∧ wSym o.y ∧ w01 o.lookUp ∧ w01 o.lookDown ∧ w01 o.lookIn ∧ w01 o.lookOut ∧
  w01 o.blink ∧ w01 o.openness ∧ w01 o.wide ∧ w01 o.squint ∧ w01 o.lid ∧
  w01 o.cheekSquint ∧ w01 o.browLowerer ∧ w01 o.browPinch ∧ w01 o.browInnerUp ∧ w01 o.browOuterUp

theorem clamp01_w01 (x : Int) : w01 (clamp01 x) := ⟨clamp01_nonneg x, clamp01_le x⟩
theorem zero_w01 : w01 0 := by unfold w01 unit; omega

theorem blinkOf_w01 (c : Calib) (o : Int) : w01 (blinkOf c o) := by
  unfold blinkOf; split
  · exact clamp01_w01 _
  · exact zero_w01

theorem wideOf_w01 (c : Calib) (o : Int) : w01 (wideOf c o) := by
  unfold wideOf; split
  · exact clamp01_w01 _
  · exact zero_w01

theorem ite_w01 (b : Bool) (x : Int) : w01 (if b then clamp01 x else 0) := by
  cases b
  · exact zero_w01
  · exact clamp01_w01 x

/-- Every weight is in [0, 1] and every axis in [-1, 1], for any input, calibration and gains. -/
theorem eye_valid (side : Side) (g : Gains) (h : Bool) (c : Calib) (e : EyeIn) :
    (eye side g h c e).valid := by
  have hx := clampSym_range e.x
  have hy := clampSym_range e.y
  refine ⟨hx, hy, clamp01_w01 _, clamp01_w01 _, clamp01_w01 _, clamp01_w01 _,
    blinkOf_w01 c _, clamp01_w01 _, wideOf_w01 c _, ite_w01 _ _, clamp01_w01 _,
    ite_w01 _ _, ite_w01 _ _, ite_w01 _ _, ite_w01 _ _, ite_w01 _ _⟩

theorem frame_valid (g : Gains) (h : Bool) (c : FrameCalib) (f : FrameIn) :
    (frame g h c f).left.valid ∧ (frame g h c f).right.valid :=
  ⟨eye_valid _ _ _ _ _, eye_valid _ _ _ _ _⟩

-- ── Blink and wide exclude each other ────────────────────────────────────────

theorem blink_pos_lt {c : Calib} {o : Int} (h : 0 < blinkOf c o) : o < c.norm.neutral := by
  unfold blinkOf at h
  by_cases ho : o < c.norm.neutral
  · exact ho
  · simp only [ho, if_false] at h; omega

/-- An eye is never reported both closing and wide open. -/
theorem blink_wide_exclusive (c : Calib) (o : Int) (h : 0 < blinkOf c o) : wideOf c o = 0 := by
  have hlt := blink_pos_lt h
  unfold wideOf
  have : ¬ (c.norm.neutral < o) := by omega
  simp [this]

theorem eye_blink_wide_exclusive (side : Side) (g : Gains) (hb : Bool) (c : Calib) (e : EyeIn)
    (h : 0 < (eye side g hb c e).blink) : (eye side g hb c e).wide = 0 :=
  blink_wide_exclusive c e.openness h

-- ── Left/right mirror symmetry ───────────────────────────────────────────────

/-- Reflect the head through its midplane: swap eyes, negate horizontal gaze. -/
def FrameIn.mirror (f : FrameIn) : FrameIn :=
  { left := { f.right with x := -f.right.x }, right := { f.left with x := -f.left.x } }

def FrameCalib.swap (c : FrameCalib) : FrameCalib := { left := c.right, right := c.left }

def EyeOut.mirror (o : EyeOut) : EyeOut := { o with x := -o.x }

def FrameOut.mirror (o : FrameOut) : FrameOut :=
  { left := o.right.mirror, right := o.left.mirror, x := -o.x, y := o.y }

theorem eye_mirror_left (g : Gains) (h : Bool) (c : Calib) (e : EyeIn) :
    eye .left g h c { e with x := -e.x } = (eye .right g h c e).mirror := by
  simp [eye, EyeOut.mirror, clampSym_neg]

theorem eye_mirror_right (g : Gains) (h : Bool) (c : Calib) (e : EyeIn) :
    eye .right g h c { e with x := -e.x } = (eye .left g h c e).mirror := by
  simp [eye, EyeOut.mirror, clampSym_neg]

/-- Mirroring the face mirrors every output: no expression favours one side. -/
theorem frame_mirror (g : Gains) (h : Bool) (c : FrameCalib) (f : FrameIn) :
    frame g h c.swap f.mirror = (frame g h c f).mirror := by
  simp only [frame, FrameIn.mirror, FrameCalib.swap, FrameOut.mirror,
    eye_mirror_left, eye_mirror_right, EyeOut.mirror]
  congr 1
  · rw [mid_comm, ← mid_neg]
  · rw [mid_comm]

-- ── Parallel gaze: never cross-eyed ──────────────────────────────────────────

/-- Give both eyes the combined gaze, dropping vergence. Stylised avatars with large
eyes look cross-eyed when each eye converges on a near point, as real eyes do. -/
def FrameIn.parallel (f : FrameIn) : FrameIn :=
  let x := mid f.left.x f.right.x
  let y := mid f.left.y f.right.y
  { left := { f.left with x, y }, right := { f.right with x, y } }

/-- With `parallel`, both eyes always report the same gaze: never crossed, never walled. -/
theorem parallel_uncrossed (g : Gains) (h : Bool) (c : FrameCalib) (f : FrameIn) :
    (frame g h c f.parallel).left.x = (frame g h c f.parallel).right.x ∧
    (frame g h c f.parallel).left.y = (frame g h c f.parallel).right.y := by
  simp [frame, eye, FrameIn.parallel]

/-- `parallel` keeps the mirror symmetry of the whole mapping. -/
theorem parallel_mirror (f : FrameIn) : f.mirror.parallel = f.parallel.mirror := by
  simp only [FrameIn.parallel, FrameIn.mirror]
  rw [mid_comm (-f.right.x), mid_neg, mid_comm f.right.y]

end FrameEyeOsc.Expressions
