-- SPDX-License-Identifier: MIT
import FrameEyeOsc.Layout
import FrameEyeOsc.Fixed
import FrameEyeOsc.Expressions
/-!
# Decoding one eye-server record

`ffi/shm.c` hands back the packed `EyeDataMmap` record as raw bytes (`Layout.recordSize`
of them). This decodes it at the offsets in `FrameEyeOsc.Layout`, little-endian, and
turns it into the fixed-point `FrameIn` the expression mapping takes.
-/

namespace FrameEyeOsc.Shm

open FrameEyeOsc Layout

def u32le (b : ByteArray) (i : Nat) : UInt32 :=
  b[i]!.toUInt32 ||| (b[i+1]!.toUInt32 <<< 8) ||| (b[i+2]!.toUInt32 <<< 16) ||| (b[i+3]!.toUInt32 <<< 24)

def u64le (b : ByteArray) (i : Nat) : UInt64 :=
  (u32le b i).toUInt64 ||| ((u32le b (i + 4)).toUInt64 <<< 32)

def f32le (b : ByteArray) (i : Nat) : Float := (Float32.ofBits (u32le b i)).toFloat
def f64le (b : ByteArray) (i : Nat) : Float := Float.ofBits (u64le b i)
def vec3 (b : ByteArray) (i : Nat) : Float × Float × Float := (f32le b i, f32le b (i+4), f32le b (i+8))

structure EyeSample where
  producerState : UInt32
  time : Float
  gaze : Array (Float × Float × Float)      -- [left, right], unit vectors, -Z forward
  fixation : Float × Float × Float
  preFusionGaze : Array (Float × Float × Float)
  openness : Array Float                    -- [left, right]
  extra : Array Float                       -- 8 floats, not yet identified
  deriving Repr, Inhabited

def decode (b : ByteArray) : Option EyeSample :=
  if b.size < recordSize then none else
  let at_ := offsetOf record
  some {
    producerState := u32le b (at_ "producer_state")
    time := f64le b (at_ "sample_time")
    gaze := #[vec3 b (at_ "gaze_direction"), vec3 b (at_ "gaze_direction" + 12)]
    fixation := vec3 b (at_ "fixation_point")
    preFusionGaze := #[vec3 b (at_ "pre_fusion_gaze"), vec3 b (at_ "pre_fusion_gaze" + 12)]
    openness := #[f32le b (at_ "openness"), f32le b (at_ "openness" + 4)]
    extra := (List.range 8).toArray.map fun k => f32le b (at_ "estimate_extra" + 4 * k) }

def finite3 (v : Float × Float × Float) : Bool := v.1.isFinite && v.2.1.isFinite && v.2.2.isFinite

/-- Valid when the producer says so and nothing the mapping reads is NaN or infinite. -/
def EyeSample.valid (s : EyeSample) : Bool :=
  s.producerState == 1 && s.time.isFinite && s.gaze.all finite3 && finite3 s.fixation &&
  s.openness.all (·.isFinite)

/-- Gaze direction → angles, ±45° ↦ ±1 like Steam Link's OSC sender, +Y up. -/
def gazeAngles (v : Float × Float × Float) : Float × Float :=
  let (x, y, z) := v
  let k := 4.0 / 3.141592653589793
  (Float.atan2 x (-z) * k, Float.atan2 y (-z) * k)

/-- VRChat's native eye tracking, `/tracking/eye/LeftRightPitchYaw`: degrees, Unity
convention (positive pitch looks down, positive yaw looks right), clamped to ±45°. -/
def pitchYawDeg (v : Float × Float × Float) : Float × Float :=
  let (x, y, z) := v
  let d := 180.0 / 3.141592653589793
  let c (a : Float) := if a > 45.0 then 45.0 else if a < -45.0 then -45.0 else a
  (c (-(Float.atan2 y (-z)) * d), c (Float.atan2 x (-z) * d))

/-- The mean of both eyes' directions: one gaze for avatars that should not converge. -/
def centerDir (s : EyeSample) : Float × Float × Float :=
  let (a, b, c) := s.gaze[0]!
  let (d, e, f) := s.gaze[1]!
  let (x, y, z) := (a + d, b + e, c + f)
  let n := Float.sqrt (x * x + y * y + z * z)
  if n < 1.0e-6 then (0.0, 0.0, -1.0) else (x / n, y / n, z / n)

/-- Smoothstep from `lo` to `hi`: a decisive blink instead of a hovering eyelid. -/
def snap (lo hi v : Float) : Float :=
  let t := (v - lo) / (hi - lo)
  let t := if t < 0.0 then 0.0 else if t > 1.0 then 1.0 else t
  t * t * (3.0 - 2.0 * t)

def toFrameIn (s : EyeSample) : Expressions.FrameIn :=
  let eyeIn (i : Nat) : Expressions.EyeIn :=
    let (ax, ay) := gazeAngles s.gaze[i]!
    { openness := ofFloat s.openness[i]!, x := ofFloat ax, y := ofFloat ay }
  { left := eyeIn 0, right := eyeIn 1 }

end FrameEyeOsc.Shm
