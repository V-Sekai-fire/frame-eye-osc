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

VRChat's native OSC eye tracking (`/tracking/eye/LeftRightPitchYaw`) is also sent, so any avatar with Eye Look set up follows your gaze even without face-tracking parameters (`--no-native` turns it off). **Anime style (default, `--style anime`).** Eyes are rebuilt clean from the raw values (`FrameEyeOsc/Anime.lean`). Blinks are events: a fast close, held shut, an eased open, with hysteresis, so openness wobble between blinks never shows. The eyes blink together unless one is clearly winking. Held-shut eyes come from `estimate_extra[4..7]` (shut above 0.008, open again below 0.004): in spoken-cue recordings they separate open from shut at AUC ≈ 0.98, while raw left-eye openness does not drop during a held closure (`--closure openness` falls back to openness alone). Squint appears only after about 250 ms of held partial closure. The lid dips slightly when you look down. Wide has a dead-zone. Gaze is one direction for both eyes through a One Euro filter: 4× steadier while fixating, and still reaching a 20° saccade in about 50 ms. It is then exaggerated on an expressive curve: a ±1.5° dead-zone, 1.8× on small glances, easing along a tanh into ±30°, so 5° reads as 6°, 10° as 14° and 20° as 24°, and nothing passes 30° (`--gaze-gain PCT`, `--gaze-max DEG`). `--style raw` sends the unshaped values.

By default both eyes get the same combined gaze, on the native path and in `FT/v2/Eye{Left,Right}X/Y`, so stylised avatars never look cross-eyed. The Lean theorem `Expressions.parallel_uncrossed` proves the two eyes agree. `--vergence` restores real per-eye convergence. Native gaze is sent 1:1, capped at ±45° (`--gaze-gain` and `--gaze-max` adjust both) and smoothed (`--smooth`). Native blink (`/tracking/eye/EyesClosedAmount`) is opt-in with `--native-blink`: while it is being received, VRChat stops auto-blinking, so an avatar without eyelids configured in Eye Look would never blink. Face-tracking avatars blink through `EyeLid*` either way.

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

To restart it from the headset's app list, install the "Frame Eye OSC" app:
`install -m755 contrib/frameeyeosc-restart ~/.local/bin/` and
`install -m644 contrib/frameeyeosc.desktop ~/.local/share/applications/`. It restarts
only this user service and shows its state and last log line as a notification. To
launch it from Steam, add it as a non-Steam game (Desktop Mode, Steam → Add a Game).

## VRChat

- Enable OSC in the VRChat Action Menu (Options → OSC → Enabled).
  VRChat's log prints `OSC enabled: False` at every startup, even with OSC on; ignore it.
  The saved toggle is `HKCU\Software\VRChat\VRChat` `UI.Settings.Osc_h1043380067`
  (1 = on), and the Steam launch option `--osc=...` shows in the log as `Arg: --osc=...`.
  If the avatar's eyes stop while the service is active and the journal shows no
  `avatar …` lines, VRChat's output is not reaching UDP 9001: see the watchdog note below.
- VRChat on a PC, streamed to the Frame: the headset must reach the PC's OSC port (UDP
  9000) and OSCQuery port (TCP, shown in the log). Allow VRChat through Windows Firewall
  on private networks.
- VRChat on the Frame: nothing to configure.
- VRChat's OSCQuery HTTP server only listens on `127.0.0.1`, so from the headset use `--target PC_IP:9000`. To still send exactly the avatar's own parameters (bit-packed ones included), add the Steam launch option `--osc=9000:FRAME_IP:9001` to VRChat. VRChat then sends its OSC output to the headset, and frameeyeosc learns each avatar's parameters on UDP 9001 (`--learn-port`). This moves VRChat's OSC output off the PC, so other apps listening on the PC's 9001 stop receiving it. For the service, put it in a drop-in, and keep the quotes: `Environment="FRAMEEYEOSC_ARGS=--target 192.168.1.229:9000"`.
- Same when mDNS is blocked: use `--target PC_IP:9000`. That sends every v2 float with the
  `FT/` prefix (`--prefix` changes it) instead of the avatar's own list.
- The learn listener re-opens after 15 s of VRChat OSC silence (backing off to 120 s), and
  a heartbeat logs every 5 min; check with
  `journalctl --user -u frameeyeosc | grep -E "re-open|heartbeat"`. The re-open path has
  not yet been exercised by a real reboot.

## Checks

```sh
lake build                    # includes every theorem
lake exe proptest             # plausible properties on the Float and byte-level paths
lake exe falsify              # counter-example search; each broken control must be caught
lake exe layout_header --check
```

`--dump` prints decoded samples, calibration and outputs. Calibration persists in
`~/.config/frameeyeosc/calib.json`.

To check the avatar against spoken close/open cues in VRChat, see
[tools/contact-sheet](tools/contact-sheet/README.md).

## Parked

- Shelved 2026-09-27: pupil dilation. Which `estimate_extra` float is pupil size is
  unidentified; `extra[4..7]` summed is the held-closure signal instead. Unpark when a
  `--dump` lens-light cover/uncover test identifies it.
- Shelved 2026-09-27: phase 2 eye-camera frame tap, reading the cDSP gazenet I/O dmabuf
  of Valve's eyetracking. It needs the owner to grant access (`setcap` or a permission
  rule) and is not pursued otherwise. Unpark when the owner runs it or grants the rule.
- Shelved 2026-09-27: voice-cue cloning for the cue recordings, a custom voice from the
  owner's accent video by the maskscore methodology. WavLM scoring needs torch ≥ 2.6; the
  cues use Windows SAPI now. Unpark when a torch ≥ 2.6 env exists and the cues need a
  custom voice.
- Shelved 2026-09-27: CineForm capture for contact sheets was requested and not set up;
  PNG ring capture (PrintWindow) is in use. Unpark when PNG capture is too slow or large.
- Shelved 2026-09-27: avatar-person segmentation for face crops (RF-DETR fine-tuned on VRM
  renders, the full 5k render corpus). Faces are the "Car" on RFD 2262's board, and the
  face contact sheet works today with RF-DETR (ggml-rd, dress-on gate 9), BiRefNet_HR-matting
  and MoGe-3 depth checks (anny-render-corpus PR #41, rf-detr-ggml PR #25). Unpark when a
  vehicle needs avatar-person detection.
