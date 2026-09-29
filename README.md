# frameeyeosc

Reading Steam Frame eye-tracking data (gaze and eye openness) and sending it via OSC.

Against what was suspected early on, the Steam Frame does also track eye openness (lid position) in addition to gaze.
However, this data is only exposed in an internal shared-memory object (`/dev/shm/eye-server.mmap`), and not via any public APIs.
This small headless program reads data sends it out via OSC as teh standard VRCFT parameters, with a configurable prefix.

This is a C/C++ port of [konsti219/frameeyeosc](https://github.com/konsti219/frameeyeosc): the same shared-memory reader and the same per-eye OSC output. The Lean driver with calibration and anime-style eyes lives in [frame-eye-osc-lean](https://github.com/V-Sekai-fire/frame-eye-osc-lean).

On the headset, build with CMake and run:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DFRAMEEYEOSC_BUILD_TESTS=OFF
cmake --build build
./build/frameeyeosc --target 127.0.0.1:9000
```

Tests use doctest and witness-cpp, fetched at configure time:

```sh
cmake -S . -B build && cmake --build build && ./build/frameeyeosc_tests
```

`contrib/frameeyeosc.service` runs it as a user service.

## Command-line arguments

`--target HOST:PORT` sets the OSC destination (default `127.0.0.1:9000`).
`--prefix PATH` sets the avatar-parameter prefix (default `/FT`).
`--source PATH` reads another shared-memory file (default `/dev/shm/eye-server.mmap`), for replaying recordings.
`--style anime` replaces the reference output with calibrated, stylised eyes: blinks become clean close-hold-open events per eye, squint appears only when partial closure is held, the lid dips on downward gaze, and gaze is smoothed with a One Euro filter and exaggerated on a bounded curve. Parameters are matched to the avatar, including bit-packed ones, when `--learn-port PORT` receives the client's OSC output; otherwise every v2 float is sent.
`--no-heuristics` turns off the cheek and brow co-activations; `--gains FILE` reads `name value` lines to tune them.
`--native` also sends the combined gaze to `/tracking/eye/CenterPitchYaw`.
`--lost-at COV` is the gaze covariance above which an eye counts as lost, which holds the other eye open during a wink.
