-- SPDX-License-Identifier: MIT
import Plausible
import FrameEyeOsc
/-!
Property tests for what the theorems cannot reach: `Float` conversion, byte codecs
(OSC, the shm record, DNS) and matching real-looking avatar parameter lists.
`lake exe proptest` exits nonzero on the first counterexample.
-/
open Plausible FrameEyeOsc

/-- Build a record the way the eye server lays it out. -/
def le32 (x : UInt32) : List UInt8 := [x.toUInt8, (x >>> 8).toUInt8, (x >>> 16).toUInt8, (x >>> 24).toUInt8]
def le64 (x : UInt64) : List UInt8 := le32 x.toUInt32 ++ le32 (x >>> 32).toUInt32

def recordBytes (state : UInt32) (time : Float) (fs : List Float) : ByteArray := Id.run do
  let mut b := (List.replicate Layout.recordSize (0 : UInt8)).toArray
  let put (b : Array UInt8) (off : Nat) (bs : List UInt8) : Array UInt8 :=
    bs.zipIdx.foldl (fun acc (x, i) => acc.set! (off + i) x) b
  b := put b 0 (le32 state)
  b := put b 5 (le64 time.toBits)
  -- 38 consecutive f32 from gaze_direction (0x0d) to the end of estimate_extra (0xa1)
  for (f, i) in fs.zipIdx do
    b := put b (0x0d + 4 * i) (le32 f.toFloat32.toBits)
  return ⟨b⟩

def f32 (i : Int) : Float := (Float.ofInt i / 97.0).toFloat32.toFloat

open Decorations in
def chk (p : Prop) (p' : DecorationsOf p := by mk_decorations) [Testable p'] : IO (Option String) := do
  let r ← Testable.checkIO p' { quiet := true, numInst := 300 }
  pure (if r.isFailure then some (toString r) else none)

def shmOk (xs : List Int) (t : Int) : Bool :=
  let fs := (xs ++ List.replicate 38 0).take 38 |>.map f32
  match Shm.decode (recordBytes 1 (Float.ofInt t) fs) with
  | none => false
  | some s =>
    s.producerState == 1 && s.time == Float.ofInt t &&
    s.gaze[0]!.1 == fs[0]! && s.gaze[1]!.2.2 == fs[5]! &&
    s.fixation.1 == fs[12]! && s.openness[0]! == fs[27]! && s.openness[1]! == fs[28]! &&
    s.extra[7]! == fs[36]!

def props : List (String × IO (Option String)) := [
  ("ofFloat is odd", chk (∀ i : Int, ofFloat (-(Float.ofInt i / 7.0)) = -ofFloat (Float.ofInt i / 7.0))),
  ("ofFloat is within one step", chk (∀ i : Int, i.natAbs < 100000 →
      (ofFloat (Float.ofInt i / 10000.0) - i).natAbs ≤ 1)),
  ("toFloat ∘ clamp01 in [0,1]", chk (∀ i : Int,
      0.0 ≤ toFloat (clamp01 i) && toFloat (clamp01 i) ≤ 1.0)),
  ("OSC float round-trips through f32", chk (∀ (a : List Char) (i : Int) (b : Bool) (k : Int),
      let addr := "/avatar/parameters/" ++ String.ofList (a.filter (fun c => c.isAlphanum))
      let m : Osc.Message := { address := addr, args := [.f (f32 i), .b b, .i (Int32.ofInt k), .s addr] }
      Osc.decode (Osc.encode m) == some m)),
  ("OSC packets are word-aligned", chk (∀ (a : List Char) (n : Nat),
      (Osc.encode { address := String.ofList (a.filter (· ≠ '\x00')),
                    args := (List.range (n % 9)).map (fun _ => Osc.Arg.f 0.5) }).size % 4 = 0)),
  ("shm record decodes at the Layout offsets", chk (∀ (xs : List Int) (t : Int), shmOk xs t = true)),
  ("short buffers never decode", chk (∀ l : List Nat,
      l.length < Layout.recordSize → (Shm.decode ⟨(l.map Nat.toUInt8).toArray⟩).isNone)) ]

/-- One synthetic OSCQuery-style parameter list, float and bit-packed. -/
def avatar : List (String × String) := [
  ("/avatar/parameters/FT/v2/EyeLidLeft", "f"),
  ("/avatar/parameters/FT/v2/EyeLeftX", "f"),
  ("/avatar/parameters/FT/v2/EyeSquintRight1", "T"),
  ("/avatar/parameters/FT/v2/EyeSquintRight2", "T"),
  ("/avatar/parameters/FT/v2/EyeSquintRight4", "T"),
  ("/avatar/parameters/FT/v2/BrowExpressionLeft1", "T"),
  ("/avatar/parameters/FT/v2/BrowExpressionLeftNegative", "T"),
  ("/avatar/parameters/v2/EyeX", "f"),
  ("/avatar/parameters/LeftEyeLid", "f"),
  ("/avatar/parameters/FT/v2/JawOpen", "f"),          -- the Frame cannot drive this
  ("/avatar/parameters/VRCEmote", "i") ]

def unitChecks : List (String × Bool) :=
  let p := Params.plan avatar
  let widthOf (a : String) := p.findSome? fun e =>
    if e.address == a then match e.feed with | .bit _ _ w => some w | _ => none else none
  -- a mDNS answer carrying PTR, SRV and A for VRChat's OSCQuery service
  let name (s : String) := Dns.encodeName s
  let rr (n : String) (ty : UInt16) (rdata : List UInt8) :=
    name n ++ Dns.u16be ty ++ Dns.u16be 1 ++ [0, 0, 0, 120] ++ Dns.u16be rdata.length.toUInt16 ++ rdata
  let inst := "VRChat-Client-ABC123._oscjson._tcp.local"
  let resp : ByteArray := ⟨(Dns.u16be 0 ++ Dns.u16be 0x8400 ++ Dns.u16be 0 ++ Dns.u16be 3 ++ Dns.u16be 0 ++ Dns.u16be 0 ++
    rr "_oscjson._tcp.local" Dns.typePTR (name inst) ++
    rr inst Dns.typeSRV ([0, 0, 0, 0] ++ Dns.u16be 50123 ++ name "DESKTOP.local") ++
    rr "DESKTOP.local" Dns.typeA [192, 168, 1, 50]).toArray⟩
  [ ("plan drives the 9 Frame parameters and skips JawOpen/VRCEmote", p.length == 9),
    ("bit width is the number of bits the avatar has", widthOf "/avatar/parameters/FT/v2/EyeSquintRight1" == some 3),
    ("DNS answer resolves to the service",
      Dns.services "_oscjson._tcp.local" (Dns.parse resp) "0.0.0.0" ==
        [{ instance_ := inst, ip := "192.168.1.50", port := 50123 }]),
    ("DNS query parses back as zero records", (Dns.parse (Dns.query "_oscjson._tcp.local" Dns.typePTR)).isEmpty) ]

def main : IO UInt32 := do
  let mut bad := 0
  for (n, ok) in unitChecks do
    IO.println s!"{if ok then "ok  " else "FAIL"} {n}"
    unless ok do bad := bad + 1
  for (n, t) in props do
    match ← t with
    | none => IO.println s!"ok   {n}"
    | some r => IO.println s!"FAIL {n}\n     {r}"; bad := bad + 1
  return if bad == 0 then 0 else 1
