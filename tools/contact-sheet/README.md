<!-- SPDX-License-Identifier: MIT -->
# Contact sheets

These are Windows-side tools. They check frameeyeosc against what the avatar actually shows in
VRChat. A spoken cue tells the wearer to close or open their eyes. A ring capture records the
VRChat window at the same time. A sheet then puts each cue next to the frame captured just
after it. Every file names frames and cues by Unix epoch seconds, so they line up with
each other and with the service's `--trace`.

Run the tools with a Windows Python that has PIL and numpy, e.g.
`C:\Users\ernest.lee\scoop\apps\python\current\python.exe`. `cue_sheet.py` must run in the
matting-hr pixi env instead (torch, OpenCV, BiRefNet weights).

| file | does |
|---|---|
| `vrc_ring.py HWND SECONDS OUTDIR` | Captures the window's client area with `PrintWindow`, stores it at half resolution in a 90 s RAM ring, writes `OUTDIR/CAPTURED` (the end epoch) when capture stops, then writes each frame as `OUTDIR/<epoch>.png`. |
| `vrc_cues_voice.py [SECONDS] [--look]` | Speaks random "close your eyes" / "open your eyes" cues (3–9 s apart) through Windows SAPI and prints `<epoch> CLOSE\|OPEN` for each one, then `<epoch> end`. `--look` also adds look left / right / straight (`LEFT`, `RIGHT`, `OPEN`). |
| `cue_sheet.py ANNY_RENDER_CORPUS FRAMES CUES OUT.png` | Cue-aligned face sheet: 2 tiles per cue, 1.5 s and 3.5 s after it, 4 columns. Imports `matte_refine.py` from a checkout of `6-datasource/anny-render-corpus` (the first argument). BiRefNet_HR-matting cuts out the avatar, and the tile is the band 28–52 % down its largest blob. |
| `trace_sheet.py FRAMES CUES TRACE OUT.png [X0 Y0 X1 Y1]` | Fixed-box sheet with the trace: 2 tiles per cue (45 % and 85 % into it), each labelled with the nearest `--trace` sample. The box is in half-res pixels; the default `1000 330 1480 690` is the mirror face at 4K. |
| `prep_rfdetr.py FRAMES OUTDIR` | Takes one frame every 3 s and writes it as a 312×312, ImageNet-normalised CHW float32 tensor (`<epoch>.f32`), plus `frames.txt` listing them, for an RF-DETR detector run. |

## Workflow

1. **Find the VRChat window handle.** In PowerShell:
   `(Get-Process VRChat).MainWindowHandle`. Or call cua `list_windows` and take the VRChat
   `window_id`. Either gives a decimal HWND.
2. **Start the cues and the ring capture together**, from two shells, in the same second:

   ```
   python vrc_cues_voice.py 70 > cues.txt
   python vrc_ring.py <HWND> 75 <outdir>
   ```

   The capture runs 5 s longer than the cues, so the last cue has frames after it. Steam
   Link streams the PC audio to the headset, so the wearer hears the cues.
3. **Optional: fetch the trace.** Run the service with `--trace <file>`. It rewrites that
   file every second with its last `--trace-cap` samples (default 16384, about 3 min).
   Each line has 12 columns: epoch, gaze, gaze, closed, sample time, raw openness L/R,
   calibrated L/R, blink phases, shut score, shut. When `<outdir>/CAPTURED` appears, copy the
   trace file off the headset. The ring still covers the capture then.
4. **Build the sheet**:

   ```
   pixi run --manifest-path C:\Users\ernest.lee\AppData\Local\matting-hr\pixi.toml python cue_sheet.py <anny-render-corpus> <outdir> cues.txt out.png
   ```

   With a trace: `python trace_sheet.py <outdir> cues.txt trace.txt trace_sheet.png`.

## Labels

- `cue_sheet.py`: `HH:MM:SS.d  expect CLOSED|OPEN` is the frame's local time and the cue it
  follows. Red means the eyes should be shut, green means open. A tile matches when the
  avatar's eyes agree with it.
- `trace_sheet.py`: line 1 is the frame's timecode (`HH:MM:SS:ff`, 30 fps) and the current
  cue (blue for CLOSE). Line 2 is the nearest trace sample's yaw, pitch, `closed` (the sent
  closure) and `shut` (0/1). Line 3 is that sample's timecode and its distance from the
  frame in 30 fps frames. A large offset means the trace does not cover that tile.

## Result (2026-09-27)

In the 08:23 run of `cue_sheet.py`, 8 of 9 closed tiles and 9 of 9 open tiles matched,
counting only tiles where the face was visible.

## Known limits

- At 4K, `PrintWindow` captures about 6 fps (about 170 ms between frames), so a tile can be
  up to about 85 ms away from its target time. A blink shorter than one frame gap can be missed.
- `cue_sheet.py` crops around the matte, so when the camera leaves the avatar (looking away
  from the mirror, a menu, another player in front), the crop lands on the wrong thing. Only
  count tiles where the face is visible.
- `trace_sheet.py` uses a fixed box, so the camera and the mirror must not move during the
  capture.
- Only the last 90 s of frames are kept, and PNG encoding starts after `CAPTURED`. Wait for
  the `frames N fps F` line before building a sheet.
