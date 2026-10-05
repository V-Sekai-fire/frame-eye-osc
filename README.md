# frame-eye-osc

Reads the headset's eye-tracking shared memory and sends gaze, blinks and squints to a social VR client as OSC avatar parameters.

## What it is for

It runs on the headset and drives the avatar's eyes directly, with no desktop bridge in between. RFD 2271 owns the design. An unrecognised flag such as `--help` prints the usage line, which names every option. It began as [konsti219's frameeyeosc](https://github.com/konsti219/frameeyeosc), with thanks for the original code.

## Build and run

```sh
cmake -S . -B build
cmake --build build
```

The build needs `slangc` on the `PATH`; run the `frameeyeosc` it writes on the headset.

## Licence

MIT; see `LICENSE`.
