-- SPDX-License-Identifier: MIT
import Lean.Data.Json
import FrameEyeOsc.Dns
import FrameEyeOsc.Ffi
/-!
# Finding VRChat, wherever it runs

VRChat advertises OSCQuery over mDNS. That finds it on the Windows PC across the LAN,
or on the Frame itself over loopback, with no configuration. From its OSCQuery server
we read the OSC port (`?HOST_INFO`), the current avatar (`/avatar/change`) and that
avatar's parameters (`/avatar/parameters`), so `Params.plan` sends only what the avatar
has.
-/

namespace FrameEyeOsc.Discovery

open Lean FrameEyeOsc Ffi

def mdnsGroup := "224.0.0.251"
def oscJson := "_oscjson._tcp.local"

/-- Browse for `_oscjson._tcp` for `ms` milliseconds. Two queries go out: a multicast one
from port 5353, whose answers arrive on the shared group socket, and a one-shot query
from an ephemeral port, which RFC 6762 §6.7 requires responders to answer by unicast. -/
def browse (ms : Nat := 1500) : IO (List Dns.Service) := do
  let group ← udpOpen 5353 1
  let oneShot ← udpOpen 0 0
  try
    udpJoin group mdnsGroup
    udpSend group mdnsGroup 5353 (Dns.query oscJson Dns.typePTR (unicastResponse := false))
    udpSend oneShot mdnsGroup 5353 (Dns.query oscJson Dns.typePTR (unicastResponse := false))
    let deadline := (← IO.monoMsNow) + ms
    let mut found : List Dns.Service := []
    while (← IO.monoMsNow) < deadline do
      for fd in [group, oneShot] do
        let (pkt, from_) ← udpRecv fd 50
        if pkt.size > 0 then
          for s in Dns.services oscJson (Dns.parse pkt) from_ do
            unless found.contains s do found := s :: found
    return found.reverse
  finally
    udpClose group
    udpClose oneShot

def isVrchat (s : Dns.Service) : Bool := s.instance_.startsWith "VRChat-Client"

structure Vrchat where
  httpIp : String
  httpPort : UInt16
  oscIp : String
  oscPort : UInt16
  deriving Repr, BEq, Inhabited

def isLoopbackOrAny (ip : String) : Bool := ip.startsWith "127." || ip == "0.0.0.0" || ip == ""

/-- Read `?HOST_INFO`. VRChat reports its OSC address as it bound it, often `127.0.0.1`;
when the HTTP server answered from elsewhere, send OSC to that host instead. -/
def hostInfo (ip : String) (port : UInt16) : IO Vrchat := do
  let body ← httpGet ip port "/?HOST_INFO"
  let j ← IO.ofExcept (Json.parse body)
  let oscIp := (j.getObjValAs? String "OSC_IP").toOption.getD ip
  let oscPort := (j.getObjValAs? Nat "OSC_PORT").toOption.getD 9000
  let oscIp := if isLoopbackOrAny oscIp then ip else oscIp
  return { httpIp := ip, httpPort := port, oscIp, oscPort := oscPort.toUInt16 }

def find (ms : Nat := 1500) : IO (Option Vrchat) := do
  for s in (← browse ms) do
    if isVrchat s then
      try return some (← hostInfo s.ip s.port.toUInt16) catch _ => pure ()
  return none

/-- The current avatar id, or `none` before VRChat has loaded one. -/
def avatarId (v : Vrchat) : IO (Option String) := do
  let j ← IO.ofExcept (Json.parse (← httpGet v.httpIp v.httpPort "/avatar/change"))
  match j.getObjVal? "VALUE" with
  | .ok (.arr a) => return a[0]?.bind (·.getStr?.toOption)
  | _ => return none

/-- Every leaf under a node: `(FULL_PATH, TYPE)`. -/
partial def leaves (j : Json) : List (String × String) :=
  let here := match j.getObjValAs? String "FULL_PATH", j.getObjValAs? String "TYPE" with
    | .ok p, .ok t => [(p, t)]
    | _, _ => []
  let kids := match j.getObjVal? "CONTENTS" with
    | .ok (.obj kv) => kv.toList.flatMap (fun (_, c) => leaves c)
    | _ => []
  here ++ kids

def avatarParameters (v : Vrchat) : IO (List (String × String)) := do
  let j ← IO.ofExcept (Json.parse (← httpGet v.httpIp v.httpPort "/avatar/parameters" 3000))
  return leaves j

end FrameEyeOsc.Discovery
