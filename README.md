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
