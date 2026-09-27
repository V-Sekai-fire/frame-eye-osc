-- SPDX-License-Identifier: MIT
/-!
# Just enough multicast DNS to find VRChat

VRChat advertises its OSCQuery HTTP server as `VRChat-Client-XXXXXX._oscjson._tcp.local`.
We ask for the PTR records of `_oscjson._tcp.local`, then read the SRV (port, host) and
A (address) records out of the answer and additional sections. RFC 6762/6763.
-/

namespace FrameEyeOsc.Dns

def typeA : UInt16 := 1
def typePTR : UInt16 := 12
def typeSRV : UInt16 := 33

def u16be (x : UInt16) : List UInt8 := [(x >>> 8).toUInt8, x.toUInt8]

def encodeName (name : String) : List UInt8 :=
  ((name.splitOn ".").filter (· ≠ "")).flatMap (fun l =>
    let b := l.toUTF8.toList
    b.length.toUInt8 :: b) ++ [0]

/-- A one-question query. `unicastResponse` sets the QU bit (RFC 6762 §5.4). -/
def query (name : String) (qtype : UInt16) (unicastResponse : Bool := true) : ByteArray :=
  let header := u16be 0 ++ u16be 0 ++ u16be 1 ++ u16be 0 ++ u16be 0 ++ u16be 0
  let qclass : UInt16 := if unicastResponse then 0x8001 else 0x0001
  ⟨(header ++ encodeName name ++ u16be qtype ++ u16be qclass).toArray⟩

def rd16 (b : ByteArray) (i : Nat) : Option Nat :=
  if i + 2 ≤ b.size then some (b[i]!.toNat * 256 + b[i+1]!.toNat) else none

/-- Read a possibly compressed name at `i`. Returns the name and the offset after it
in the original (uncompressed) stream. Pointer chains are bounded by `fuel`. -/
partial def readName (b : ByteArray) (i : Nat) (fuel : Nat := 32) : Option (String × Nat) := do
  let rec go (j : Nat) (acc : List String) (endAt : Option Nat) (fuel : Nat) : Option (String × Nat) := do
    if fuel == 0 || j ≥ b.size then none
    let len := b[j]!.toNat
    if len == 0 then
      some (".".intercalate acc.reverse, endAt.getD (j + 1))
    else if len &&& 0xC0 == 0xC0 then
      let ptr ← rd16 b j
      go (ptr &&& 0x3FFF) acc (some (endAt.getD (j + 2))) (fuel - 1)
    else
      if j + 1 + len > b.size then none
      let label ← String.fromUTF8? (b.extract (j + 1) (j + 1 + len))
      go (j + 1 + len) (label :: acc) endAt (fuel - 1)
  go i [] none fuel

inductive RData
  | ptr (target : String)
  | srv (port : Nat) (target : String)
  | a (ip : String)
  | other
  deriving Repr, Inhabited

structure Record where
  name : String
  data : RData
  deriving Repr, Inhabited

def parseRecord (b : ByteArray) (i : Nat) : Option (Record × Nat) := do
  let (name, j) ← readName b i
  let ty ← rd16 b j
  let rdlen ← rd16 b (j + 8)
  let r := j + 10
  if r + rdlen > b.size then none
  let data ←
    if ty == typePTR.toNat then (readName b r).map (RData.ptr ·.1)
    else if ty == typeSRV.toNat then do
      let port ← rd16 b (r + 4)
      let (t, _) ← readName b (r + 6)
      pure (RData.srv port t)
    else if ty == typeA.toNat && rdlen == 4 then
      pure (RData.a s!"{b[r]!}.{b[r+1]!}.{b[r+2]!}.{b[r+3]!}")
    else pure RData.other
  pure ({ name, data }, r + rdlen)

/-- All resource records in a response (answers, authority and additional). -/
def parse (b : ByteArray) : List Record := Id.run do
  let some qd := rd16 b 4 | return []
  let some an := rd16 b 6 | return []
  let some ns := rd16 b 8 | return []
  let some ar := rd16 b 10 | return []
  let mut i := 12
  for _ in [0:qd] do
    match readName b i with
    | some (_, j) => i := j + 4
    | none => return []
  let mut out := #[]
  for _ in [0:an + ns + ar] do
    match parseRecord b i with
    | some (r, j) => out := out.push r; i := j
    | none => break
  return out.toList

structure Service where
  instance_ : String
  ip : String
  port : Nat
  deriving Repr, Inhabited, BEq

/-- Join PTR → SRV → A. `fromIp` is the packet source, used when no A record came along. -/
def services (serviceType : String) (rs : List Record) (fromIp : String) : List Service :=
  let lower := String.toLower
  rs.filterMap fun r => do
    let .ptr inst := r.data | none
    guard (lower r.name == lower serviceType)
    let (port, host) ← rs.findSome? fun s =>
      match s.data with
      | .srv p t => if lower s.name == lower inst then some (p, t) else none
      | _ => none
    let ip := (rs.findSome? fun s =>
      match s.data with
      | .a ip => if lower s.name == lower host then some ip else none
      | _ => none).getD fromIp
    pure { instance_ := inst, ip, port }

end FrameEyeOsc.Dns
