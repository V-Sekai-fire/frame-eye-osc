-- SPDX-License-Identifier: MIT
import FrameEyeOsc.Expressions
/-!
# Anime style: eyes constructed from the raw values

Real eyelids hover, flutter and pass through half-closed on every blink. Stylised eyes
read best when they are clean, so this layer rebuilds the eyelid, squint and wide
channels from the raw per-eye openness:

* **Blinks are events.** Openness below `closeAt` starts a blink: the lid shuts in
  `closeMs`, stays shut until openness passes `openAt` (hysteresis), then eases open over
  `openMs`. Wobble between blinks never reaches the avatar.
* **Each eye blinks on its own reading.** One eye closing never pulls the other along.
* **Squint is held, not passed through.** Only partial closure sustained for
  `squintAfterMs` becomes a squint, so a blink's half-way frames never show as one.
* **The lid follows the gaze.** Looking down lowers the upper lid a little, as anime rigs do.
* **Wide has a dead-zone** above relaxed-open.

Everything is integer 1/10000 units and milliseconds. `eye_style_valid` and
`frame_style_valid` prove every rebuilt channel stays in range for any input and any
tuning.
-/

namespace FrameEyeOsc.Anime

open FrameEyeOsc Expressions

structure Tuning where
  closeAt       : Int := 3500    -- raw openness (fraction of relaxed-open) that starts a blink
  openAt        : Int := 5500    -- and that ends it
  closeMs       : Nat := 60
  openMs        : Nat := 140
  squintAt      : Int := 8000    -- partial closure below this counts toward a squint
  squintAfterMs : Nat := 250
  squintFullMs  : Nat := 400
  wideDeadZone  : Int := 2000
  lidFollow     : Int := 2500    -- how far the lid drops per unit of downward gaze
  deriving Repr, Inhabited

inductive Phase | opened | closing | closed | opening
  deriving Repr, DecidableEq, Inhabited

structure EyeState where
  phase : Phase := .opened
  t : Nat := 0                 -- ms in the current phase
  from_ : Int := unit          -- lid level when the phase began
  partialMs : Nat := 0         -- ms of sustained partial closure
  deriving Repr, Inhabited

structure State where
  left : EyeState := {}
  right : EyeState := {}
  deriving Repr, Inhabited

/-- Raw openness relative to this eye's calibration: 0 shut, 1 relaxed-open, >1 wide. -/
def rel (c : Calib) (o : Int) : Int :=
  (o - c.norm.closed) * unit / (c.norm.neutral - c.norm.closed)

/-- The lid level a phase shows `t` ms in. Ease-out on opening. -/
def level (k : Tuning) (s : EyeState) : Int :=
  match s.phase with
  | .opened => unit
  | .closed => 0
  | .closing =>
    let d := (k.closeMs : Int)
    if d ≤ 0 then 0 else clamp01 (s.from_ - s.from_ * min (s.t : Int) d / d)
  | .opening =>
    let d := (k.openMs : Int)
    if d ≤ 0 then unit else
      let r := d - min (s.t : Int) d          -- time remaining
      clamp01 (unit - unit * r * r / (d * d))

def start (k : Tuning) (s : EyeState) (p : Phase) : EyeState :=
  { s with phase := p, t := 0, from_ := level k s }

/-- Advance one eye by `dt` ms given its relative openness `r`. -/
def stepEye (k : Tuning) (dt : Nat) (s : EyeState) (r : Int) : EyeState :=
  let s := { s with t := s.t + dt }
  let partialMs := if s.phase == .opened && r < k.squintAt && r ≥ k.closeAt then s.partialMs + dt else 0
  let s := { s with partialMs }
  match s.phase with
  | .opened  => if r < k.closeAt then start k s .closing else s
  | .closing => if s.t ≥ k.closeMs then start k s .closed else s
  | .closed  => if r > k.openAt then start k s .opening else s
  | .opening =>
    if r < k.closeAt then start k s .closing
    else if s.t ≥ k.openMs then start k s .opened else s

/-- A wink the fused openness misses. The tracker reports both lids shut during a wink,
but only the closed eye loses its gaze fix; the eye it still sees is held open. -/
def winkGate (occL occR : Bool) (rl rr : Int) : Int × Int :=
  if occL && !occR then (rl, max rr unit)
  else if occR && !occL then (max rl unit, rr)
  else (rl, rr)

/-- Unless exactly one eye is lost, both readings pass through: a blink stays a blink. -/
theorem winkGate_same (o : Bool) (rl rr : Int) : winkGate o o rl rr = (rl, rr) := by
  cases o <;> rfl

/-- The eye the tracker lost always keeps its own reading. -/
theorem winkGate_keeps_lost (rl rr : Int) :
    (winkGate true false rl rr).1 = rl ∧ (winkGate false true rl rr).2 = rr := by
  simp [winkGate]

/-- The eye it still sees is never shown more closed than relaxed-open. -/
theorem winkGate_opens_seen (rl rr : Int) :
    unit ≤ (winkGate true false rl rr).2 ∧ unit ≤ (winkGate false true rl rr).1 := by
  simp [winkGate]; omega

/-- Step each eye independently. -/
def step (k : Tuning) (dt : Nat) (st : State) (rl rr : Int) : State :=
  { left := stepEye k dt st.left rl, right := stepEye k dt st.right rr }

/-- Rebuild one eye's lid channels from the style state. Gaze, look and co-activation
gains are kept from the base mapping; everything rebuilt goes through `clamp01`. -/
def styleEye (k : Tuning) (g : Gains) (heuristics : Bool) (c : Calib) (raw : Int)
    (s : EyeState) (o : EyeOut) : EyeOut :=
  let lvl := level k s
  let follow := clamp01 (lvl - scale k.lidFollow o.lookDown)
  let r := rel c raw
  let wide := if s.phase == .opened then clamp01 ((r - unit - k.wideDeadZone) * unit / (unit + 1)) else 0
  let hold := (s.partialMs : Int) - k.squintAfterMs
  let squint := if heuristics && s.phase == .opened && hold > 0 then
      clamp01 (min unit (hold * unit / max 1 (k.squintFullMs : Int)) * (k.squintAt - r) / max 1 (k.squintAt - k.closeAt))
    else 0
  let co (gain v : Int) := if heuristics then clamp01 (scale gain v) else 0
  { o with
    blink := clamp01 (unit - follow)
    openness := follow
    lid := clamp01 (follow * 3 / 4 + wide / 4)
    wide, squint
    cheekSquint := co g.cheekFromSquint squint
    browLowerer := co g.browDownFromSquint squint
    browPinch := co g.browPinchFromSquint squint
    browInnerUp := co g.browInnerFromWide wide
    browOuterUp := co g.browOuterFromWide wide }

def styleFrame (k : Tuning) (g : Gains) (heuristics : Bool) (c : FrameCalib) (f : FrameIn)
    (st : State) (o : FrameOut) : FrameOut :=
  { o with left := styleEye k g heuristics c.left f.left.openness st.left o.left
           right := styleEye k g heuristics c.right f.right.openness st.right o.right }

-- ── Range ────────────────────────────────────────────────────────────────────

theorem co_w01 (h : Bool) (gain v : Int) : w01 (if h then clamp01 (scale gain v) else 0) :=
  ite_w01 h _

theorem wide_w01 (b : Bool) (x : Int) : w01 (if b then clamp01 x else 0) := ite_w01 b x

/-- The anime layer keeps every channel in range, for any state, raw input and tuning. -/
theorem eye_style_valid (k : Tuning) (g : Gains) (h : Bool) (c : Calib) (raw : Int)
    (s : EyeState) (o : EyeOut) (hv : o.valid) : (styleEye k g h c raw s o).valid := by
  obtain ⟨hx, hy, hu, hd, hi, ho, -, -, -, -, -, -, -, -, -, -⟩ := hv
  refine ⟨hx, hy, hu, hd, hi, ho, clamp01_w01 _, clamp01_w01 _, wide_w01 _ _, ?_, clamp01_w01 _,
    co_w01 _ _ _, co_w01 _ _ _, co_w01 _ _ _, co_w01 _ _ _, co_w01 _ _ _⟩
  simp only [styleEye]
  split
  · exact clamp01_w01 _
  · exact zero_w01

theorem frame_style_valid (k : Tuning) (g : Gains) (h : Bool) (c : FrameCalib) (f : FrameIn)
    (st : State) :
    (styleFrame k g h c f st (frame g h c f)).left.valid ∧
    (styleFrame k g h c f st (frame g h c f)).right.valid :=
  ⟨eye_style_valid _ _ _ _ _ _ _ (eye_valid _ _ _ _ _),
   eye_style_valid _ _ _ _ _ _ _ (eye_valid _ _ _ _ _)⟩

/-- A shut eye is shown fully shut: no half-lidded frame while `closed`. -/
theorem closed_level (k : Tuning) (s : EyeState) (h : s.phase = .closed) : level k s = 0 := by
  simp [level, h]

/-- An open eye is shown fully open between blinks, whatever the raw openness does. -/
theorem opened_level (k : Tuning) (s : EyeState) (h : s.phase = .opened) : level k s = unit := by
  simp [level, h]

end FrameEyeOsc.Anime
