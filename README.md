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
- No mDNS on your network? Use `--target PC_IP:9000`. That sends every v2 float with the
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
