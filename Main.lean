-- SPDX-License-Identifier: MIT
import FrameEyeOsc
/-!
# frameeyeosc

Reads the Steam Frame's eye server and drives VRCFaceTracking-style avatar parameters
in VRChat directly over OSC, with no VRCFaceTracking. It finds VRChat with OSCQuery,
on the PC or on the headset, and sends only the parameters the current avatar has.
-/

open FrameEyeOsc Expressions Params

structure Cli where
  target : Option (String × UInt16) := none   -- skip discovery, send here
  prefix_ : String := "FT/"                     -- only used without discovery
  heuristics : Bool := true
  dump : Bool := false
  gains : System.FilePath := "data/eye_facial_action.json"
  source : String := "/dev/shm/eye-server.mmap"

def usage : String := "usage: frameeyeosc [--target HOST:PORT] [--prefix FT/] [--no-heuristics] [--dump] [--gains FILE]
  With no --target, VRChat is found over mDNS/OSCQuery and only the current avatar's
  parameters are sent. With --target, every v2 float is sent to HOST:PORT."

def parseCli : List String → Cli → Except String Cli
  | [], c => .ok c
  | "--target" :: hp :: rest, c =>
    match hp.splitOn ":" with
    | [h, p] => match p.toNat? with
      | some n => parseCli rest { c with target := some (h, n.toUInt16) }
      | none => .error s!"bad port in {hp}"
    | _ => .error s!"--target wants HOST:PORT, got {hp}"
  | "--prefix" :: p :: rest, c =>
    let p := (p.dropWhile (· == '/')).toString
    parseCli rest { c with prefix_ := if p.isEmpty || p.endsWith "/" then p else p ++ "/" }
  | "--no-heuristics" :: rest, c => parseCli rest { c with heuristics := false }
  | "--dump" :: rest, c => parseCli rest { c with dump := true }
  | "--gains" :: f :: rest, c => parseCli rest { c with gains := f }
  | "--source" :: f :: rest, c => parseCli rest { c with source := f }
  | a :: _, _ => .error s!"unknown argument {a}\n{usage}"

/-- Where to send and what. `active` is the avatar's EyeTrackingActive bools. -/
structure Route where
  ip : String
  port : UInt16
  entries : List Entry
  active : List String

def log (s : String) : IO Unit := do IO.eprintln s!"[frameeyeosc] {s}"

/-- Rediscover every few seconds: VRChat may start later, restart, or change avatar. -/
partial def discoveryLoop (route : IO.Ref (Option Route)) (avatar : Option String) : IO Unit := do
  let next ← try
      match ← Discovery.find with
      | none =>
        if (← route.get).isSome then log "VRChat not found; pausing"
        route.set none
        pure none
      | some v =>
        let id ← Discovery.avatarId v
        if id != avatar || (← route.get).isNone then
          let ps ← Discovery.avatarParameters v
          let entries := plan ps
          let active := ps.filterMap fun (p, t) =>
            if p.endsWith "EyeTrackingActive" && t != "f" then some p else none
          route.set (some { ip := v.oscIp, port := v.oscPort, entries, active })
          log s!"VRChat at {v.oscIp}:{v.oscPort} (OSCQuery {v.httpIp}:{v.httpPort}), avatar {id.getD "?"}: {entries.length} of {ps.length} parameters driven"
        pure id
    catch e =>
      log s!"discovery: {e}"
      pure avatar
  IO.sleep 3000
  discoveryLoop route next

def oscOf (address : String) : Value → Osc.Message
  | .float q => { address, args := [.f (toFloat q)] }
  | .bool b => { address, args := [.b b] }

partial def openSource (path : String) : IO Unit := do
  try Ffi.shmOpen path
  catch e =>
    log s!"{e}; retrying in 2 s"
    IO.sleep 2000
    openSource path

def main (args : List String) : IO UInt32 := do
  let cli ← match parseCli args {} with
    | .ok c => pure c
    | .error e => IO.eprintln e; return 2
  let gains ← Calib.loadGains cli.gains
  let route ← IO.mkRef (none : Option Route)
  match cli.target with
  | some (ip, port) =>
    route.set (some { ip, port, entries := fallbackPlan cli.prefix_,
                      active := [s!"{paramsPrefix}{cli.prefix_}EyeTrackingActive"] })
    log s!"sending every v2 parameter to {ip}:{port}"
  | none =>
    let _ ← IO.asTask (prio := .dedicated) (discoveryLoop route none)
    log "looking for VRChat over mDNS/OSCQuery"
  openSource cli.source
  log s!"reading {cli.source}"
  let sock ← Ffi.udpOpen 0 0
  let mut calib ← Calib.load
  let mut last : Std.HashMap String Value := {}
  let mut active := false
  let mut n : Nat := 0
  let mut lastSave ← IO.monoMsNow
  let mut lastRefresh ← IO.monoMsNow
  repeat
    let bytes ← try Ffi.shmNext 1000 catch e => log s!"{e}"; IO.sleep 1000; pure .empty
    let sample := (Shm.decode bytes).filter (·.valid)
    let r ← route.get
    match sample, r with
    | some s, some r =>
      let input := Shm.toFrameIn s
      calib := Calib.stepFrame calib input
      let out := frame gains cli.heuristics calib input
      let now ← IO.monoMsNow
      -- resend everything once a second so a VRChat restart or late join catches up
      let refresh := now - lastRefresh > 1000
      if refresh then lastRefresh := now
      for e in r.entries do
        let v := valueOf out e.feed
        if refresh || last[e.address]? != some v then
          Ffi.udpSend sock r.ip r.port (Osc.encode (oscOf e.address v))
          last := last.insert e.address v
      if !active || refresh then
        for a in r.active do Ffi.udpSend sock r.ip r.port (Osc.encode (oscOf a (.bool true)))
      active := true
      if now - lastSave > 60000 then
        try Calib.save calib catch e => log s!"saving calibration: {e}"
        lastSave := now
      if cli.dump && n % 24 == 0 then
        IO.println s!"t={s.time} open={s.openness} extra={s.extra}\n  calib={repr calib}\n  L={repr out.left}\n  R={repr out.right}"
      n := n + 1
    | none, some r =>
      if active then
        for a in r.active do Ffi.udpSend sock r.ip r.port (Osc.encode (oscOf a (.bool false)))
        active := false
    | some s, none =>
      if cli.dump && n % 24 == 0 then
        IO.println s!"(no VRChat yet) t={s.time} open={s.openness} gaze={s.gaze} extra={s.extra}"
      n := n + 1
    | none, none => pure ()
  return 0
