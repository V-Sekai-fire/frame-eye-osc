-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-FileCopyrightText: 2026 konsti219
-- SPDX-License-Identifier: MIT
import PlausibleWitnessDag
import FrameEyeOscTests.Ffi

/-!
# Tests for the Slang driver

Unit checks call the exported functions through `FrameEyeOscTests.Ffi`. Each property is a
plausible-witness-dag query for a candidate that breaks it, over deterministic candidates
derived from an index. The real code must come back `.provablyNone` inside `searchWidth`;
its control, which plants the defect the property rules out, must come back `.found`.
`.budgetHit` is a failure, never a pass.
-/

open PlausibleWitnessDag FrameEyeOscTests

namespace FrameEyeOscTests

def floats (xs : List Float) : FloatArray := ⟨xs.toArray⟩
def get (a : FloatArray) (i : Nat) : Float := a.get! i

def calibDefault : List Float := [0.0, 0.75, 1.0]
def gainsDefault : FloatArray := floats [1.0, 0.6, 0.5, 0.3, 0.7, 0.8]
def tuningDefault : FloatArray := floats [0.35, 0.55, 60.0, 140.0, 0.8, 250.0, 400.0, 0.2, 0.25]
def opened : Float := 0.0
def closed : Float := 2.0
def eyeStateDefault : List Float := [opened, 0.0, 1.0, 0.0]

-- ── Samples and messages ─────────────────────────────────────────────────────

/-- [producer_state, time, gaze L, gaze R, covariance L, covariance R, fixation, open L, open R]. -/
def sample (openL openR : Float) (state : Float := 1.0) : FloatArray :=
  floats ([state, 1.0] ++ [0, 0, -1, 0, 0, -1] ++ [0, 0, 0, 0, 0, 0] ++ [0, 0, -1] ++ [openL, openR])

def floatOf (ms : Array ByteArray) (address : String) : Option Float :=
  (ms.find? (Ffi.messageAddress · == address)).map (Ffi.messageFloat · 0)

def tagOf (m : ByteArray) : Char := Char.ofNat (Ffi.messageTag m 0).toNat

def bytes (xs : List Nat) : ByteArray := ⟨(xs.map (·.toUInt8)).toArray⟩

def be32 (n : Nat) : List Nat := [n / 16777216 % 256, n / 65536 % 256, n / 256 % 256, n % 256]

-- ── Unit checks ──────────────────────────────────────────────────────────────

def gazeChecks : List (String × Bool) :=
  let ahead := Ffi.gazeAngles (floats [0, 0, -1])
  let corner := Ffi.gazeAngles (floats [1, 1, -1])
  [ ("straight ahead is zero gaze", get ahead 0 == 0.0 && get ahead 1 == 0.0),
    ("45 degrees right and up map to 1", (get corner 0 - 1.0).abs < 1e-6 && (get corner 1 - 1.0).abs < 1e-6) ]

def referenceChecks : List (String × Bool) :=
  let winking := Ffi.referenceMessages (sample 0.05 0.8) "/FT"
  let clamped := Ffi.referenceMessages (sample (-0.2) 1.4) "/FT/"
  let lid (ms : Array ByteArray) (n : String) := floatOf ms s!"/avatar/parameters/FT/v2/{n}"
  let wide := (0.05 : Float).toFloat32.toFloat
  [ ("each lid follows its own eye", lid winking "EyeLidLeft" == some wide &&
      lid winking "EyeLidRight" == some (0.8 : Float).toFloat32.toFloat),
    ("lids are clamped to 0..1", lid clamped "EyeLidLeft" == some 0.0 && lid clamped "EyeLidRight" == some 1.0),
    ("the first message marks eye tracking active",
      winking.size == 9 && Ffi.messageAddress winking[0]! == "/avatar/parameters/FT/EyeTrackingActive" &&
      tagOf winking[0]! == 'T'),
    ("invalid samples are rejected", Ffi.sampleValid (sample 0.8 0.8) == 1 &&
      Ffi.sampleValid (sample 0.8 (0.0 / 0.0)) == 0 && Ffi.sampleValid (sample 0.8 0.8 0.0) == 0) ]

def put32 (b : ByteArray) (at_ : Nat) (bits : UInt32) : ByteArray := Id.run do
  let mut out := b
  for i in [0:4] do
    out := out.set! (at_ + i) (bits >>> (8 * i).toUInt32).toUInt8
  return out

def recordChecks : List (String × Bool) :=
  let r0 := ByteArray.mk (Array.replicate 0xebc 0)
  let f32 (x : Float) := x.toFloat32.toBits
  let r := put32 r0 0x00 1
  let t := (12.5 : Float).toBits
  let r := put32 r 0x05 t.toUInt32
  let r := put32 r 0x09 (t >>> 32).toUInt32
  let r := put32 r 0x19 (f32 (-0.1))
  let r := put32 r 0x39 (f32 0.06)
  let r := put32 r 0x45 (f32 (-2.0))
  let r := put32 r 0x79 (f32 0.25)
  let r := put32 r 0x7d (f32 0.75)
  let s := Ffi.decode r
  [ ("a record decodes at the reference offsets",
      s.size == 19 && get s 0 == 1.0 && get s 1 == 12.5 && get s 5 == (-0.1 : Float).toFloat32.toFloat &&
      get s 13 == (0.06 : Float).toFloat32.toFloat && get s 16 == -2.0 && get s 17 == 0.25 && get s 18 == 0.75),
    ("control: a short record does not decode", (Ffi.decode (ByteArray.mk (Array.replicate 100 0))).size == 0) ]

def oscChecks : List (String × Bool) :=
  let one := Ffi.addFloat (Ffi.message "/a") 1.0
  let four := Ffi.addBool (Ffi.message "/abc") 1
  let a := Ffi.addFloat (Ffi.message "/a") 0.5
  let b := Ffi.addBool (Ffi.message "/b") 1
  let c := Ffi.addInt (Ffi.message "/c") 7
  let got := Ffi.decodePacket (Ffi.bundle #[a, b, c])
  let x := Ffi.addInt (Ffi.message "/x") 1
  let y := Ffi.addInt (Ffi.message "/y") 2
  let inner := Ffi.bundle #[x, y]
  let outer := bytes ([35, 98, 117, 110, 100, 108, 101, 0] ++ List.replicate 8 0 ++ be32 inner.size) ++ inner
  let nested := Ffi.decodePacket outer
  let wire := Ffi.encode (Ffi.addFloat (Ffi.message "/abc") 0.5) 1024
  [ ("a float message encodes as padded address, tag and big-endian value",
      Ffi.encode one 1024 == bytes [47, 97, 0, 0, 44, 102, 0, 0, 0x3f, 0x80, 0, 0]),
    ("an address of four characters still gets a terminator",
      Ffi.encode four 1024 == bytes [47, 97, 98, 99, 0, 0, 0, 0, 44, 84, 0, 0]),
    ("encoding refuses a buffer that is too small", (Ffi.encode a 8).size == 0),
    ("a bundle of three messages decodes to all three", got.size == 3 &&
      Ffi.messageEqual got[0]! a == 1 && Ffi.messageEqual got[1]! b == 1 && Ffi.messageEqual got[2]! c == 1),
    ("a nested bundle is flattened", nested.size == 2 && Ffi.messageEqual nested[1]! y == 1),
    ("control: a truncated message does not decode", (Ffi.decodeMessage wire).size > 0 &&
      (Ffi.decodeMessage (wire.extract 0 (wire.size - 1))).size == 0) ]

def expressionChecks : List (String × Bool) :=
  let f := floats [0.8, 0.3, -0.1, 0.8, -0.2, 0.4]
  let o := Ffi.frame gainsDefault 1 (floats (calibDefault ++ calibDefault)) (Ffi.parallel f)
  let n := Ffi.calibNormalized (floats [0.9, 0.5, 0.1])
  let settled := (List.range 5000).foldl (fun c k => Ffi.calibStep c (if k % 50 == 0 then 0.0 else 0.9))
    (floats calibDefault)
  let relaxed := Ffi.eye 0 gainsDefault 1 (floats calibDefault) (floats [0.75, 0, 0])
  let shut := Ffi.eye 0 gainsDefault 1 (floats calibDefault) (floats [0.0, 0, 0])
  [ ("parallel gaze gives both eyes the same direction", get o 0 == get o 16 && get o 1 == get o 17),
    ("a normalized calibration is strictly ordered", get n 0 < get n 1 && get n 1 < get n 2),
    ("neutral follows open samples and ignores blinks", (get settled 1 - 0.9).abs < 0.01),
    ("relaxed open reads 0.75 on the lid, shut reads 0", (get relaxed 10 - 0.75).abs < 1e-6 && get shut 10 == 0.0) ]

/-- Half a second of steps at 90 Hz with a fixed relative openness per eye. -/
def hold (start : FloatArray) (rl rr : Float) : FloatArray :=
  (List.range 45).foldl (fun s _ => Ffi.styleStep tuningDefault 11.0 s rl rr) start

def animeChecks : List (String × Bool) :=
  let fresh := floats (eyeStateDefault ++ eyeStateDefault)
  let wink := hold fresh 0.0 0.4
  let shut := hold fresh 0.0 0.0
  let reopened := hold (hold fresh 0.0 1.0) 1.0 1.0
  let gate (ll lr : UInt8) := Ffi.winkGate ll lr 0.1 0.2
  let still := (List.range 90).foldl (fun f _ => Ffi.oneEuroStep f 0.0 0.011) (floats [0, 0, 0])
  let moved := (List.range 9).foldl (fun f _ => Ffi.oneEuroStep f 20.0 0.011) still
  let py := Ffi.pitchYaw (floats [0.3, -0.3, -1.0])
  [ ("a wink leaves a half-open eye open", get wink 0 == closed && get wink 4 == opened),
    ("control: both eyes shut close both", get shut 0 == closed && get shut 4 == closed),
    ("a shut eye shows shut and an open eye open",
      Ffi.level tuningDefault (floats [closed, 0, 1, 0]) == 0.0 && Ffi.level tuningDefault (floats eyeStateDefault) == 1.0),
    ("an eye reopens after its reading rises", get reopened 0 == opened),
    ("the wink gate holds open only the eye the tracker still sees",
      gate 1 0 == floats [(0.1 : Float).toFloat32.toFloat, 1.0] &&
      gate 0 1 == floats [1.0, (0.2 : Float).toFloat32.toFloat] &&
      gate 1 1 == floats [(0.1 : Float).toFloat32.toFloat, (0.2 : Float).toFloat32.toFloat]),
    ("a covariance past the threshold marks the eye lost",
      Ffi.eyeLost (floats [0.001, 0.05, 0.001]) 0.02 == 1 && Ffi.eyeLost (floats [0.001, 0.001, 0.001]) 0.02 == 0),
    ("the One Euro filter holds still at rest and reaches a saccade", get still 0 == 0.0 && get moved 0 > 15.0),
    ("pitch is positive looking down, yaw positive looking right", get py 0 > 0.0 && get py 1 > 0.0) ]

def avatarAddresses : Array String := #[
  "/avatar/parameters/FT/v2/EyeLidLeft", "/avatar/parameters/FT/v2/EyeLeftX",
  "/avatar/parameters/FT/v2/EyeSquintRight1", "/avatar/parameters/FT/v2/EyeSquintRight2",
  "/avatar/parameters/FT/v2/EyeSquintRight4", "/avatar/parameters/FT/v2/BrowExpressionLeft1",
  "/avatar/parameters/FT/v2/BrowExpressionLeftNegative", "/avatar/parameters/v2/EyeX",
  "/avatar/parameters/LeftEyeLid", "/avatar/parameters/FT/v2/JawOpen", "/avatar/parameters/VRCEmote" ]
def avatarTypes : List Char := ['f', 'f', 'T', 'T', 'T', 'T', 'T', 'f', 'f', 'f', 'i']
def avatarPlan : Array ByteArray := Ffi.plan avatarAddresses ⟨(avatarTypes.map (·.toNat.toUInt8)).toArray⟩

def findEntry (es : Array ByteArray) (address : String) : Option ByteArray :=
  es.find? (Ffi.entryAddress · == address)

def sortedAddresses (es : Array ByteArray) : List String :=
  (es.toList.map Ffi.entryAddress).mergeSort (· ≤ ·)

def paramChecks : List (String × Bool) :=
  let es := avatarPlan
  let squint := findEntry es "/avatar/parameters/FT/v2/EyeSquintRight1"
  let levels := (List.range 6).all fun w =>
    let width := w + 1
    let steps := 2 ^ width - 1
    (List.range (steps + 1)).all fun level =>
      let got := Ffi.quantize width.toUInt32 (level.toFloat / steps.toFloat + 1e-6)
      got.toNat == level && got.toNat < 2 ^ width
  let truncation := (List.range 1001).all fun k =>
    let v := k.toFloat / 1000.0
    let step := 1.0 / 7.0
    let back := (Ffi.quantize 3 v).toNat.toFloat * step
    back ≤ v + 1e-6 && v - back < step
  let frown := floats (List.replicate 12 0 ++ [1.0] ++ List.replicate 21 0)
  let tagFor (a : String) := ((findEntry es a).map fun e => tagOf (Ffi.messageFor e frown)).getD '?'
  let output := #[Ffi.addString (Ffi.message "/avatar/change") "avtr_test"] ++
    (avatarAddresses.zip avatarTypes.toArray).map fun (a, t) =>
      if t == 'f' then Ffi.addFloat (Ffi.message a) 0.25
      else if t == 'i' then Ffi.addInt (Ffi.message a) 3 else Ffi.addBool (Ffi.message a) 0
  let (avatar, learned) := Ffi.learn (Ffi.decodePacket (Ffi.bundle output))
  let counts := Ffi.learnedCounts #[Ffi.addFloat (Ffi.message "/avatar/parameters/FT/v2/EyeLidLeft") 0.5,
    Ffi.addString (Ffi.message "/avatar/change") "other"]
  let fallback := Ffi.fallbackPlan "FT/"
  [ ("the plan drives the 9 eye parameters and skips what the tracker cannot", es.size == 9 &&
      (findEntry es "/avatar/parameters/FT/v2/JawOpen").isNone && (findEntry es "/avatar/parameters/VRCEmote").isNone),
    ("a bit parameter knows how many bits the avatar has",
      (squint.map Ffi.entryWidth) == some 3 && (squint.map Ffi.entryBit) == some 0),
    ("packed bits decode back to every level, for every width in use", levels),
    ("quantizing truncates by less than one step", truncation),
    ("a negative expression sets the sign bit and the magnitude bits",
      tagFor "/avatar/parameters/FT/v2/BrowExpressionLeftNegative" == 'T' &&
      tagFor "/avatar/parameters/FT/v2/BrowExpressionLeft1" == 'T'),
    ("learning from the client's output builds the same plan as a parameter list",
      avatar == "avtr_test" && sortedAddresses learned == sortedAddresses es),
    ("a new avatar clears what was learned", get counts 0 == 1.0 && get counts 1 == 0.0),
    ("the fallback plan sends every v2 float under the prefix", fallback.size == (Ffi.v2Count ()).toNat &&
      (findEntry fallback "/avatar/parameters/FT/v2/EyeLidRight").isSome) ]

-- ── Outputs (constants and layouts from sasaken1102r's frameeyeosc) ─────────

/-- Gaze L x, y, R x, y, combined x, y, then both VRCFT eyelids. -/
def eyesOf (gaze : List Float) (lidL lidR : Float) : FloatArray := floats (gaze ++ [lidL, lidR])
def near (a b : Float) : Bool := (a - b).abs < 1e-5
def f32 (x : Float) : Float := x.toFloat32.toFloat
def msgNamed (ms : Array ByteArray) (address : String) : Option ByteArray :=
  ms.find? (Ffi.messageAddress · == address)
def argF (ms : Array ByteArray) (address : String) (i : Nat := 0) : Option Float :=
  (msgNamed ms address).map (Ffi.messageFloat · i.toUInt32)
def argI (ms : Array ByteArray) (address : String) : Option UInt32 :=
  (msgNamed ms address).map (Ffi.messageInt · 0)
/-- Big-endian float bytes. -/
def beF (x : Float) : List Nat := be32 x.toFloat32.toBits.toNat

def outputChecks : List (String × Bool) :=
  let e := eyesOf [0.2, -0.1, 0.25, -0.1, 0.22, -0.1] 0.3 0.9
  let sl := Ffi.steamlinkMessages e
  let p (n : String) := s!"/avatar/parameters/{n}"
  let order := sl.toList.map Ffi.messageAddress
  let nat := Ffi.nativeMessages e 0
  let natInd := Ffi.nativeMessages e 1
  let closedAmt := argF nat "/tracking/eye/EyesClosedAmount"
  let v := Ffi.gazeVector 0.3 (-0.2)
  -- Unity +Z forward back to the Frame's -Z forward, then the angles we send.
  let back := Ffi.gazeAngles (floats [get v 0, get v 1, -(get v 2)])
  let actB := Ffi.activeMessage "/FT" 1 0
  let actF := Ffi.activeMessage "/FT" 0 1
  let actOff := Ffi.activeMessage "/FT" 1 2
  let et := Ffi.etvrMessages e "/FT"
  let shapes := Ffi.livelinkShapes e
  let ramp := floats ((List.range 61).map fun i => i.toFloat / 100.0)
  let pkt := Ffi.livelinkPacket 1000.5 ramp
  let expected := [6] ++ be32 11 ++ "frameeyeosc".toList.map (·.toNat) ++ be32 10 ++
    "SteamFrame".toList.map (·.toNat) ++ be32 90045 ++ beF 0.0 ++ be32 90 ++ be32 1 ++ [61] ++
    (List.range 61).flatMap fun i => beF (i.toFloat / 100.0)
  let later := Ffi.livelinkPacket (1000.5 + 0.25 / 90.0) ramp
  [ ("Steam Link names come in its order, Y turned over, eyelid as closedness",
      order == [p "LeftEyeX", p "LeftEyeY", p "RightEyeX", p "RightEyeY",
                p "RightEyeLid", p "RightEyeLidExpandedSqueeze", p "RightEyeSqueezeToggle", p "RightEyeWidenToggle",
                p "LeftEyeLid", p "LeftEyeLidExpandedSqueeze", p "LeftEyeSqueezeToggle", p "LeftEyeWidenToggle"] &&
      argF sl (p "LeftEyeY") == some (f32 0.1) && argF sl (p "RightEyeLid") == some 0.0 &&
      (argF sl (p "LeftEyeLid")).any (near · 0.6)),
    ("Steam Link squeeze follows a half-closed eye, and widen is always 1",
      argI sl (p "LeftEyeSqueezeToggle") == some 1 && argI sl (p "RightEyeSqueezeToggle") == some 0 &&
      argF sl (p "LeftEyeLidExpandedSqueeze") == some 0.0 && argF sl (p "RightEyeLidExpandedSqueeze") == some (f32 0.8) &&
      argI sl (p "LeftEyeWidenToggle") == some 1 &&
      (msgNamed sl (p "LeftEyeSqueezeToggle")).map tagOf == some 'i'),
    ("Steam Link closedness: relaxed and widened are open, shut is 1",
      Ffi.steamlinkClosed 0.75 == 0.0 && Ffi.steamlinkClosed 1.0 == 0.0 && Ffi.steamlinkClosed 0.0 == 1.0),
    ("the gaze vector undoes the gaze angles", near (get back 0) 0.3 && near (get back 1) (-0.2) &&
      near (get v 0 * get v 0 + get v 1 * get v 1 + get v 2 * get v 2) 1.0 && get v 2 > 0.0),
    ("VRChat's own eyes: one look address and the closed amount of both eyelids",
      nat.size == 2 && Ffi.messageAddress nat[0]! == "/tracking/eye/CenterVec" && Ffi.messageArgc nat[0]! == 3 &&
      closedAmt.any (near · (1.0 - (0.3 + 0.9) / 2.0 / 0.75))),
    ("VRChat's own eyes, moved separately, send both vectors",
      natInd.size == 2 && Ffi.messageAddress natInd[0]! == "/tracking/eye/LeftRightVec" &&
      Ffi.messageArgc natInd[0]! == 6),
    ("EyeTrackingActive goes as a bool, a float or not at all",
      actB.size == 1 && Ffi.messageAddress actB[0]! == "/avatar/parameters/FT/EyeTrackingActive" &&
      tagOf actB[0]! == 'T' && actF.size == 1 && tagOf actF[0]! == 'f' && Ffi.messageFloat actF[0]! 0 == 0.0 &&
      actOff.size == 0),
    ("ETVR eyelids treat relaxed as fully open", Ffi.etvrLid 0.0 == 0.0 && near (Ffi.etvrLid 0.375) 0.5 &&
      Ffi.etvrLid 0.75 == 1.0 && Ffi.etvrLid 1.0 == 1.0),
    ("ETVR gets only the six per-eye values",
      et.toList.map Ffi.messageAddress == ["EyeLeftX", "EyeLeftY", "EyeRightX", "EyeRightY", "EyeLidLeft",
        "EyeLidRight"].map (s!"/avatar/parameters/FT/v2/{·}") &&
      (argF et "/avatar/parameters/FT/v2/EyeLidLeft").any (near · 0.4)),
    ("Live Link shapes split each eyelid into blink and widen, pitch turned over",
      shapes.size == 61 && near (get shapes 0) 0.6 && get shapes 6 == 0.0 && get shapes 7 == 0.0 &&
      near (get shapes 13) 0.6 && get shapes 55 == f32 0.2 && get shapes 56 == f32 0.1 &&
      get shapes 58 == f32 0.25 && get shapes 59 == f32 0.1),
    ("the Live Link packet matches the Live Link Face layout",
      pkt.size == 291 && pkt.toList.map (·.toNat) == expected),
    ("Live Link keeps a steady 50 a second from 90 Hz samples (control: 20 ms since the last send gives 44)",
      let steady := Ffi.throttleCount 11111 10 0
      let planted := Ffi.throttleCount 11111 10 1
      steady ≥ 495 && steady ≤ 501 && planted < 460),
    ("the Live Link frame carries its fraction",
      (later.extract 30 34).toList.map (·.toNat) == be32 90045 && (later.extract 34 38).toList.map (·.toNat) == beF 0.25) ]

def ioChecks : IO (List (String × Bool)) := do
  let path := "/dev/shm/frameeyeosc-lean-test"
  let _ ← Ffi.shmCreate path 4
  let producer ← IO.asTask do
    IO.sleep 20
    Ffi.shmPublish path 0.1 0.9
  let first ← Ffi.eyeReadOnce path 1000
  let _ ← IO.wait producer
  let quiet ← Ffi.eyeReadOnce path 20
  let _ ← Ffi.shmCreate path 3
  let refused ← try
      let _ ← Ffi.eyeReadOnce path 20
      pure false
    catch e => pure (((toString e).splitOn "version 3").length > 1)
  -- Version 5 (SteamOS 0.4.3 on): the record sits 5 bytes later, after the dominant-eye setting.
  let _ ← Ffi.shmCreate path 5
  let producer5 ← IO.asTask do
    IO.sleep 20
    Ffi.shmPublish path 0.25 0.75
  let fifth ← try Ffi.eyeReadOnce path 1000 catch _ => pure (floats [])
  let _ ← IO.wait producer5
  -- A sample published while the last one was being processed is read at once, because the
  -- next one was requested in the same lock that took the last.
  let _ ← Ffi.shmCreate path 5
  let _ ← Ffi.shmSetDominant path 1 1
  let busy ← try Ffi.eyeReadBusy path catch _ => pure (floats [])
  let _ ← Ffi.shmCreate path 4
  let busy4 ← try Ffi.eyeReadBusy path catch _ => pure (floats [])
  IO.FS.removeFile path
  let back ← Ffi.calibRoundTrip "/tmp/frameeyeosc-calib-test.txt" (floats [0.1, 0.7, 0.95, 0.05, 0.8, 1.1])
  pure [
    ("a new record is read, then the source times out", get first 0 == 1.0 &&
      get first 1 == (0.1 : Float).toFloat32.toFloat && get first 2 == (0.9 : Float).toFloat32.toFloat &&
      get quiet 0 == 0.0),
    ("control: a wrong shared-memory version is refused", refused),
    ("version 5 is read at its own record offset", get fifth 0 == 1.0 &&
      get fifth 1 == (0.25 : Float).toFloat32.toFloat && get fifth 2 == (0.75 : Float).toFloat32.toFloat),
    ("taking a sample requests the next one in the same lock", get busy 0 == 1.0 && get busy 1 == 1.0),
    ("a sample published while busy is read without waiting", get busy 2 == 1.0 &&
      get busy 3 == (0.6 : Float).toFloat32.toFloat && get busy 4 == 0.0),
    ("version 5 reports the dominant eye; version 4 has none", get busy 5 == 1.0 && get busy4 5 == -1.0),
    ("the dominant-eye setting parses off, left and right, and distrusts anything else",
      let d := fun (bs : List UInt8) => Ffi.dominantEye (ByteArray.mk bs.toArray)
      d [0, 0xff, 0xff, 0xff, 0xff] == -1 && d [0, 1, 0, 0, 0] == -1 && d [1, 0, 0, 0, 0] == 0 &&
      d [1, 1, 0, 0, 0] == 1 && d [1, 2, 0, 0, 0] == -2 && d [1, 0xff, 0xff, 0xff, 0xff] == -2 &&
      d [2, 0, 0, 0, 0] == -2),
    ("calibration saves and loads", back.size == 6 && (get back 5 - 1.1).abs < 1e-5 && (get back 1 - 0.7).abs < 1e-5) ]

-- ── Properties, each with a control that plants the defect ───────────────────

/-- How far the deterministic readback looks: the width of every search. -/
def searchWidth : Nat := 4000

/-- A cheap deterministic spread from a candidate index. -/
def mix (c k : Nat) : Nat := (c * 2654435761 + k * 40503 + 12345) % 1000003
def valueAt (c k : Nat) (lo hi : Float) : Float := lo + (hi - lo) * (mix c k).toFloat / 1000003.0

def inputAt (c : Nat) : FloatArray :=
  floats ((List.range 6).map fun k => if k % 3 == 0 then valueAt c k (-0.5) 2.5 else valueAt c k (-3.0) 3.0)
def calibAt (c : Nat) (k : Nat) : List Float := [valueAt c k (-0.5) 1.0, valueAt c (k + 1) (-0.5) 1.5, valueAt c (k + 2) (-0.5) 2.0]
def gainsAt (c : Nat) : FloatArray := floats ((List.range 6).map fun k => valueAt c (20 + k) (-3.0) 3.0)

def in01 (v : Float) : Bool := 0.0 ≤ v && v ≤ 1.0
def eyeInRange (o : FloatArray) (base : Nat) : Bool :=
  (get o base).abs ≤ 1.0 && (get o (base + 1)).abs ≤ 1.0 && (List.range 14).all fun k => in01 (get o (base + 2 + k))

def rangeBreaks (broken : Bool) (c : Nat) : Bool :=
  let o := Ffi.frame (gainsAt c) 1 (floats (calibAt c 10 ++ calibAt c 13)) (inputAt c)
  if broken then get o 10 != get o 26 else !(eyeInRange o 0 && eyeInRange o 16)

def exclusionBreaks (broken : Bool) (c : Nat) : Bool :=
  let k := calibAt c 10
  let o := valueAt c 30 (-0.5) 2.5
  let shifted := floats [k[0]!, k[1]! - 0.2, k[2]!]
  let wide := if broken then Ffi.wideOf shifted o else Ffi.wideOf (floats k) o
  Ffi.blinkOf (floats k) o > 0.0 && wide > 0.0

def mirrorBreaks (broken : Bool) (c : Nat) : Bool :=
  let l := calibAt c 10
  let r := calibAt c 13
  let f := inputAt c
  let swapped := if broken then floats (l ++ r) else floats (r ++ l)
  let a := Ffi.frame (gainsAt c) 1 swapped (Ffi.mirror f)
  let b := Ffi.frame (gainsAt c) 1 (floats (l ++ r)) f
  !(get a 10 == get b 26 && get a 26 == get b 10 && get a 0 == -(get b 16) && get a 4 == get b 20 && get a 33 == get b 33)

def styleBreaks (broken : Bool) (c : Nat) : Bool :=
  let state := floats [(mix c 40 % 4).toFloat, valueAt c 41 0 500, valueAt c 42 (-0.5) 1.5, valueAt c 43 0 2000]
  let raw := valueAt c 44 (-1.0) 3.0
  let calib := floats (calibAt c 45)
  let base := (Ffi.eye 0 gainsDefault 1 (floats calibDefault) (floats [0.75, 0, 0])).set! 3 (valueAt c 48 0 1)
  let o := Ffi.styleEye tuningDefault gainsDefault 1 calib raw state base
  let n := Ffi.calibNormalized calib
  let rel := (raw - get n 0) / (get n 1 - get n 0)
  if broken then (0.8 - rel) / (0.8 - 0.35) > 1.0 else !((List.range 14).all fun k => in01 (get o (2 + k)))

def expressiveBreaks (broken : Bool) (c : Nat) : Bool :=
  let a := valueAt c 50 (-90) 90
  let b := valueAt c 51 (-90) 90
  let lo := min a b
  let hi := max a b
  let e (x : Float) := Ffi.expressive 1.8 30.0 1.5 x
  if broken then (1.8 * a).abs > 30.0
  else !(e lo == -(e (-lo)) && (e lo).abs ≤ 30.0 && e lo ≤ e hi)

def gazeBreaks (broken : Bool) (c : Nat) : Bool :=
  let d := [valueAt c 60 (-10) 10, valueAt c 61 (-10) 10, valueAt c 62 (-10) (-0.01)]
  let g := Ffi.gazeAngles (floats d)
  let m := Ffi.gazeAngles (floats [-d[0]!, -d[1]!, d[2]!])
  if broken then (Float.atan2 d[0]! (-d[2]!) * 4.0 / 3.14159265).abs > 1.0
  else !((get g 0).abs ≤ 1.0 && (get g 1).abs ≤ 1.0 && get g 0 == -(get m 0) && get g 1 == -(get m 1))

def messageAt (c : Nat) : ByteArray := Id.run do
  let name := String.ofList ((List.range (mix c 70 % 30)).map fun i => Char.ofNat (97 + mix c (71 + i) % 26))
  let address := s!"/avatar/parameters/{name}"
  let mut m := Ffi.message address
  for k in [0:mix c 72 % 5] do
    let kind := mix c (73 + k) % 4
    m := if kind == 0 then Ffi.addFloat m (valueAt c (80 + k) (-1000) 1000)
      else if kind == 1 then Ffi.addInt m (mix c (80 + k)).toUInt32
      else if kind == 2 then Ffi.addBool m (mix c (80 + k) % 2).toUInt8
      else Ffi.addString m address
  return m

def oscBreaks (broken : Bool) (c : Nat) : Bool :=
  let m := messageAt c
  let wire := Ffi.encode m 4096
  let sent := if broken then wire.extract 0 (wire.size - 1) else wire
  let back := Ffi.decodeMessage sent
  !(sent.size % 4 == 0 && back.size > 0 && Ffi.messageEqual back m == 1)

def firstViolation (breaks : Nat → Bool) (steps : Nat) : Option Nat :=
  (List.range steps).find? breaks

def query (name : String) (breaks : Nat → Bool) : IO TraceEntry := do
  let readback : Nat → Readback (Option Nat) := fun steps =>
    match firstViolation breaks steps with
    | some w => { value := some w, found := true, witnessIdx := w, budgetHit := false }
    | none => { value := none, found := false, budgetHit := (firstViolation breaks searchWidth).isSome }
  let (_, _, trace) ← resolve name (fun _ c => breaks c) readback
  pure trace

def properties : List (String × (Bool → Nat → Bool)) := [
  ("weights in 0..1 and axes in -1..1 (control: both lids always equal)", rangeBreaks),
  ("blink and wide never both nonzero (control: wide from a neutral 0.2 lower)", exclusionBreaks),
  ("mirroring the face mirrors every output (control: calibration left unswapped)", mirrorBreaks),
  ("the anime layer keeps every channel in 0..1 (control: squint without its clamp)", styleBreaks),
  ("expressive gaze is odd, bounded and monotone (control: gain without the tanh limit)", expressiveBreaks),
  ("gaze stays in -1..1 and mirrors (control: angle without the clamp)", gazeBreaks),
  ("OSC messages round-trip word-aligned (control: last byte dropped)", oscBreaks) ]

end FrameEyeOscTests

open FrameEyeOscTests in
def main : IO UInt32 := do
  let unit := gazeChecks ++ referenceChecks ++ recordChecks ++ oscChecks ++ expressionChecks ++ animeChecks ++ paramChecks ++
    outputChecks
  let io ← ioChecks
  let mut bad := 0
  for (name, ok) in unit ++ io do
    IO.println s!"{if ok then "ok  " else "FAIL"} {name}"
    unless ok do bad := bad + 1
  for (name, breaks) in properties do
    let real ← query name (breaks false)
    let control ← query s!"control: {name}" (breaks true)
    let realOk := real.outcome == .provablyNone
    let controlOk := match control.outcome with | .found _ => true | _ => false
    IO.println s!"{if realOk && controlOk then "ok  " else "FAIL"} {name}: real {repr real.outcome}, control {repr control.outcome}"
    unless realOk && controlOk do bad := bad + 1
  IO.println s!"{(unit ++ io).length} checks and {properties.length} properties, {bad} failures"
  return if bad == 0 then 0 else 1
