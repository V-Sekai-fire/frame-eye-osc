# frame-eye-osc

Reads the headset's eye-tracking shared memory and sends gaze, blinks and squints to a social VR client as OSC avatar parameters.

## What it is for

It runs on the headset and drives the avatar's eyes directly, with no desktop bridge in between. RFD66606-2271 owns the design. An unrecognised flag such as `--help` prints the usage line, which names every option. It began as [konsti219's frameeyeosc](https://github.com/konsti219/frameeyeosc), with thanks for the original code.

## Build and run

```sh
cmake -S . -B build
cmake --build build
```

The build needs `slangc` on the `PATH`; run the `frameeyeosc` it writes on the headset.

## Eye cameras

`tools/eyecam` is the sasaken1102r eye-camera recorder and live processor (MIT, with the NOTICE of the code it ports). `src/eyecam.slang` reads the page it publishes at `/run/user/1000/eyecam/live` and lets its lid, widen, squint and pupil replace the eye server's openness. `tests/Main.lean` holds the golden page and the invariants; `tests/planted_eyecam.py` plants one defect at a time and requires the named check to fail. `--eyecam PATH|off` (default `/run/user/1000/eyecam/live`) turns the reader on in the anime style: the cameras' lid, widen and squint replace the eye server's, and `FT/v2/PupilDiameterLeft` and `Right` are sent. The reference style does not read it yet. Frames for training are captured with `tools/eyeframes/capture.py` (on the Frame, PGM) and stored as lossless WebP with `tools/eyeframes/to_webp.py`, which deletes a PGM only after the WebP decodes to the same pixels. The tests build on Linux only.

## Licence

MIT; see `LICENSE`.
