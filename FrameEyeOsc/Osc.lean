-- SPDX-License-Identifier: MIT
/-!
# OSC 1.0 messages

Only what VRChat's avatar parameters use: float `f`, int `i`, and bools as the
argument-less `T`/`F` tags. The encoder builds a `List UInt8` so that its length is
something the kernel can reason about: `encode_len_mod4` proves every packet is a whole
number of 32-bit words, which OSC requires. The decoder round-trip is property-tested
in `Proptest.lean` and searched for counter-examples in `Falsify.lean`.
-/

namespace FrameEyeOsc.Osc

inductive Arg
  | f (x : Float)
  | i (x : Int32)
  | b (x : Bool)
  | s (x : String)
  deriving Repr, Inhabited

def Arg.beq : Arg → Arg → Bool
  | .f x, .f y => x.toFloat32.toBits == y.toFloat32.toBits
  | .i x, .i y => x == y
  | .b x, .b y => x == y
  | .s x, .s y => x == y
  | _, _ => false

instance : BEq Arg := ⟨Arg.beq⟩

structure Message where
  address : String
  args : List Arg
  deriving Repr, Inhabited, BEq

def pad4 (l : List UInt8) : List UInt8 := l ++ List.replicate ((4 - l.length % 4) % 4) 0

/-- An OSC string: the bytes, a NUL, then NULs up to a multiple of four. -/
def oscString (s : String) : List UInt8 := pad4 (s.toUTF8.toList ++ [0])

def be32 (x : UInt32) : List UInt8 :=
  [(x >>> 24).toUInt8, (x >>> 16).toUInt8, (x >>> 8).toUInt8, x.toUInt8]

def Arg.tag : Arg → Char
  | .f _ => 'f' | .i _ => 'i' | .b true => 'T' | .b false => 'F' | .s _ => 's'

def Arg.bytes : Arg → List UInt8
  | .f x => be32 x.toFloat32.toBits
  | .i x => be32 x.toUInt32
  | .b _ => []
  | .s x => oscString x

def encodeList (m : Message) : List UInt8 :=
  oscString m.address ++ oscString (String.ofList (',' :: m.args.map Arg.tag)) ++
    m.args.flatMap Arg.bytes

def encode (m : Message) : ByteArray := ⟨(encodeList m).toArray⟩

theorem pad4_len (l : List UInt8) : (pad4 l).length % 4 = 0 := by
  simp only [pad4, List.length_append, List.length_replicate]; omega

theorem oscString_len (s : String) : (oscString s).length % 4 = 0 := pad4_len _

theorem be32_len (x : UInt32) : (be32 x).length = 4 := rfl

theorem arg_bytes_len (a : Arg) : a.bytes.length % 4 = 0 := by
  cases a <;> simp [Arg.bytes, be32_len, oscString_len]

theorem flatMap_len (as : List Arg) : (as.flatMap Arg.bytes).length % 4 = 0 := by
  induction as with
  | nil => rfl
  | cons a as ih =>
    simp only [List.flatMap_cons, List.length_append]
    have := arg_bytes_len a; omega

/-- Every encoded message is a whole number of 32-bit words. -/
theorem encode_len_mod4 (m : Message) : (encodeList m).length % 4 = 0 := by
  simp only [encodeList, List.length_append]
  have h1 := oscString_len m.address
  have h2 := oscString_len (String.ofList (',' :: m.args.map Arg.tag))
  have h3 := flatMap_len m.args
  omega

-- ── Decoding ─────────────────────────────────────────────────────────────────

/-- Read an OSC string at `i`, returning it and the aligned offset after it. -/
def readString (b : ByteArray) (i : Nat) : Option (String × Nat) := do
  let rec findNul (j : Nat) (fuel : Nat) : Option Nat :=
    match fuel with
    | 0 => none
    | fuel + 1 => if j ≥ b.size then none else if b[j]! == 0 then some j else findNul (j + 1) fuel
  let z ← findNul i b.size
  let s ← String.fromUTF8? (b.extract i z)
  let next := (z + 1 + 3) / 4 * 4
  if next ≤ b.size then some (s, next) else none

def readU32 (b : ByteArray) (i : Nat) : Option UInt32 :=
  if i + 4 ≤ b.size then
    some ((b[i]!.toUInt32 <<< 24) ||| (b[i+1]!.toUInt32 <<< 16) |||
          (b[i+2]!.toUInt32 <<< 8) ||| b[i+3]!.toUInt32)
  else none

def decode (b : ByteArray) : Option Message := do
  let (address, i) ← readString b 0
  let (tags, i) ← readString b i
  guard (tags.startsWith ",")
  let mut args : Array Arg := #[]
  let mut j := i
  for t in (tags.drop 1).toString.toList do
    match t with
    | 'f' => let w ← readU32 b j; args := args.push (.f (Float32.ofBits w).toFloat); j := j + 4
    | 'i' => let w ← readU32 b j; args := args.push (.i w.toInt32); j := j + 4
    | 'T' => args := args.push (.b true)
    | 'F' => args := args.push (.b false)
    | 's' => let (s, k) ← readString b j; args := args.push (.s s); j := k
    | _ => none
  guard (j == b.size)
  pure { address, args := args.toList }

end FrameEyeOsc.Osc
