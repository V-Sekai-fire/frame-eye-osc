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
  native : Bool := true                        -- VRChat's /tracking/eye/* gaze (any avatar with Eye Look)
  nativeBlink : Bool := false                  -- /tracking/eye/EyesClosedAmount; stops VRChat's auto-blink
  gazeGain : Float := 1.0                      -- native gaze scale; 1 = your real gaze angle
  gazeMax : Float := 45.0                      -- native gaze clamp, degrees
  vergence : Bool := false                     -- keep per-eye convergence; off = both eyes parallel (never cross-eyed)
  smooth : Float := 0.35                       -- EMA factor per sample for native gaze, 1 = off
  learnPort : UInt16 := 9001                   -- VRChat's OSC output (--osc=9000:<frame-ip>:9001); 0 = off

def usage : String := "usage: frameeyeosc [--target HOST:PORT] [--prefix FT/] [--no-heuristics] [--no-native] [--native-blink] [--vergence] [--gaze-gain PCT] [--gaze-max DEG] [--smooth PCT] [--learn-port 9001] [--dump] [--gains FILE]
  With no --target, VRChat is found over mDNS/OSCQuery and only the current avatar's
  parameters are sent. With --target, parameters are learned from VRChat's OSC output
  (launch VRChat with --osc=9000:<frame-ip>:9001); until then every v2 float is sent."

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
  | "--no-native" :: rest, c => parseCli rest { c with native := false }
  | "--native-blink" :: rest, c => parseCli rest { c with nativeBlink := true }
  | "--vergence" :: rest, c => parseCli rest { c with vergence := true }
  | "--per-eye" :: rest, c => parseCli rest { c with vergence := true }
  | "--gaze-gain" :: v :: rest, c => parseCli rest { c with gazeGain := (v.toNat?.map (·.toFloat / 100.0)).getD c.gazeGain }
  | "--gaze-max" :: v :: rest, c => parseCli rest { c with gazeMax := (v.toNat?.map (·.toFloat)).getD c.gazeMax }
  | "--smooth" :: v :: rest, c => parseCli rest { c with smooth := (v.toNat?.map (·.toFloat / 100.0)).getD c.smooth }
  | "--learn-port" :: p :: rest, c => match p.toNat? with
    | some n => parseCli rest { c with learnPort := n.toUInt16 }
    | none => .error s!"bad port {p}"
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

/-- Listen to VRChat's OSC output and keep the avatar's parameter list. -/
partial def learnLoop (fd : UInt32) (learned : IO.Ref (Learn.State × Nat)) : IO Unit := do
  let (pkt, _) ← try Ffi.udpRecv fd 500 catch _ => pure (.empty, "")
  if pkt.size > 0 then
    for m in Osc.decodePacket pkt do
      let (st, n) ← learned.get
      let (st', changed) := Learn.observe st m
      if changed then learned.set (st', n + 1)
  learnLoop fd learned

def routeFor (ip : String) (port : UInt16) (ps : List (String × String)) : Route :=
  { ip, port, entries := plan ps
    active := ps.filterMap fun (p, t) => if p.endsWith "EyeTrackingActive" && t != "f" then some p else none }

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
    log s!"sending to {ip}:{port}; every v2 float until the avatar's parameters are learned"
  | none =>
    let _ ← IO.asTask (prio := .dedicated) (discoveryLoop route none)
    log "looking for VRChat over mDNS/OSCQuery"
  let learned ← IO.mkRef ((default : Learn.State), 0)
  if cli.target.isSome && cli.learnPort != 0 then
    let fd ← Ffi.udpOpen cli.learnPort 0
    let _ ← IO.asTask (prio := .dedicated) (learnLoop fd learned)
    log s!"learning avatar parameters from VRChat's OSC output on UDP {cli.learnPort}"
  let mut seenVersion := 0
  let mut changedAt := 0
  let mut gz : Array Float := #[0.0, 0.0, 0.0, 0.0]   -- smoothed native gaze (pitch, yaw, pitch, yaw)
  let mut closedS : Float := 0.0
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
    -- adopt a learned parameter list once it has been quiet for 300 ms
    if let some (ip, port) := cli.target then
      let (st, v) ← learned.get
      let now ← IO.monoMsNow
      if v != seenVersion then
        seenVersion := v; changedAt := now
      else if changedAt != 0 && now - changedAt ≥ 300 then
        changedAt := 0
        let ps := st.list
        let fallback : Route := ⟨ip, port, fallbackPlan cli.prefix_, [s!"{paramsPrefix}{cli.prefix_}EyeTrackingActive"]⟩
        let r := if ps.isEmpty then fallback else routeFor ip port ps
        route.set (some r)
        last := {}
        log s!"avatar {st.avatar.getD "?"}: {r.entries.length} of {ps.length} parameters driven"
    let r ← route.get
    match sample, r with
    | some s, some r =>
      let input := if cli.vergence then Shm.toFrameIn s else (Shm.toFrameIn s).parallel
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
      if cli.native then
        let shape (a : Float) : Float :=
          let a := a * cli.gazeGain
          if a > cli.gazeMax then cli.gazeMax else if a < -cli.gazeMax then -cli.gazeMax else a
        let raw : Array Float :=
          if cli.vergence then
            let (lp, ly) := Shm.pitchYawDeg s.gaze[0]!
            let (rp, ry) := Shm.pitchYawDeg s.gaze[1]!
            #[shape lp, shape ly, shape rp, shape ry]
          else
            let (p, y) := Shm.pitchYawDeg (Shm.centerDir s)
            #[shape p, shape y, shape p, shape y]
        gz := (gz.zip raw).map fun (o, n) => o + cli.smooth * (n - o)
        let gazeMsg : Osc.Message :=
          if cli.vergence then ⟨"/tracking/eye/LeftRightPitchYaw", gz.toList.map Osc.Arg.f⟩
          else ⟨"/tracking/eye/CenterPitchYaw", [.f gz[0]!, .f gz[1]!]⟩
        Ffi.udpSend sock r.ip r.port (Osc.encode gazeMsg)
        if cli.nativeBlink then
          let b := toFloat (clamp01 ((out.left.blink + out.right.blink) / 2))
          -- close fast, open a little slower, and snap past half-closure
          let target := Shm.snap 0.35 0.75 b
          closedS := closedS + (if target > closedS then 0.8 else 0.4) * (target - closedS)
          let closedMsg : Osc.Message := ⟨"/tracking/eye/EyesClosedAmount", [.f closedS]⟩
          Ffi.udpSend sock r.ip r.port (Osc.encode closedMsg)
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
