# frameeyeosc

Steam Frame eye tracking in VRChat, with no VRCFaceTracking on the PC or the headset.

It reads the Frame's internal eye-server shared memory (gaze and eyelid openness per
eye, `/dev/shm/eye-server.mmap`) and sends VRCFaceTracking-named avatar parameters
directly to VRChat over OSC. Forked from
[konsti219/frameeyeosc](https://github.com/konsti219/frameeyeosc), whose reverse
engineering of the shared-memory ABI (Frame firmware 0.5.0, shm version 4) this builds
on. It is now written in Lean 4, with its safety properties proved. See
[docs/decisions/0001-lean-rewrite.md](docs/decisions/0001-lean-rewrite.md).

## What it drives

From measurements: `EyeLeftX/Y`, `EyeRightX/Y`, `EyeX/Y`, `EyeLid*`, `EyeOpenness*`,
`EyeWide*`.

From eyelid co-activation heuristics (`--no-heuristics` turns them off, and
`data/eye_facial_action.json` sets the gains): `EyeSquint*`, `CheekSquint*`,
`BrowLowerer*`, `BrowPinch*`, `BrowInnerUp*`, `BrowOuterUp*`, `BrowUp*`, `BrowDown*`,
`BrowExpression*`.

VRChat's native OSC eye tracking (`/tracking/eye/LeftRightPitchYaw`) is also sent, so any avatar with Eye Look set up follows your gaze even without face-tracking parameters (`--no-native` turns it off). By default both eyes get the same combined gaze, on the native path and in `FT/v2/Eye{Left,Right}X/Y`, so stylised avatars never look cross-eyed. The Lean theorem `Expressions.parallel_uncrossed` proves the two eyes agree. `--vergence` restores real per-eye convergence. Native gaze is also scaled (`--gaze-gain`, default 70%), capped (`--gaze-max`, default 25°) and smoothed (`--smooth`). Native blink (`/tracking/eye/EyesClosedAmount`) is opt-in with `--native-blink`: while it is being received, VRChat stops auto-blinking, so an avatar without eyelids configured in Eye Look would never blink. Face-tracking avatars blink through `EyeLid*` either way.

Each name is sent as `FT/v2/…`, `v2/…` or the v1 names, as a float or bit-packed
(`Name1/2/4…` plus `NameNegative`), whichever the current avatar actually has. The avatar
is read from VRChat's OSCQuery. `EyeTrackingActive` is set while samples flow. The
Frame has no face cameras, so mouth, jaw and tongue shapes are never sent.

## Install (on the Frame)

```sh
curl -sSfL https://raw.githubusercontent.com/leanprover/elan/master/elan-init.sh | sh -s -- -y --default-toolchain none
git clone https://github.com/V-Sekai-fire/frameeyeosc ~/frameeyeosc && cd ~/frameeyeosc
lake build frameeyeosc
.lake/build/bin/frameeyeosc            # finds VRChat by itself
```

To start it on login, install `contrib/frameeyeosc.service` as a systemd user unit (see
the comments at the top of that file).

## VRChat

- Enable OSC in the VRChat Action Menu (Options → OSC → Enabled).
- VRChat on a PC, streamed to the Frame: the headset must reach the PC's OSC port (UDP
  9000) and OSCQuery port (TCP, shown in the log). Allow VRChat through Windows Firewall
  on private networks.
- VRChat on the Frame: nothing to configure.
- VRChat's OSCQuery HTTP server only listens on `127.0.0.1`, so from the headset use `--target PC_IP:9000`. To still send exactly the avatar's own parameters (bit-packed ones included), add the Steam launch option `--osc=9000:FRAME_IP:9001` to VRChat. VRChat then sends its OSC output to the headset, and frameeyeosc learns each avatar's parameters on UDP 9001 (`--learn-port`). This moves VRChat's OSC output off the PC, so other apps listening on the PC's 9001 stop receiving it. For the service, put it in a drop-in, and keep the quotes: `Environment="FRAMEEYEOSC_ARGS=--target 192.168.1.229:9000"`.
- Same when mDNS is blocked: use `--target PC_IP:9000`. That sends every v2 float with the
  `FT/` prefix (`--prefix` changes it) instead of the avatar's own list.

## Checks

```sh
lake build                    # includes every theorem
lake exe proptest             # plausible properties on the Float and byte-level paths
lake exe falsify              # counter-example search; each broken control must be caught
lake exe layout_header --check
```

`--dump` prints decoded samples, calibration and outputs. Calibration persists in
`~/.config/frameeyeosc/calib.json`.
