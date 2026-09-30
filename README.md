# frame-eye-osc

Special thanks to https://github.com/konsti219/frameeyeosc for writing the original code.

## Command-line arguments

- `--target HOST:PORT` sets the OSC destination (default `127.0.0.1:9000`).
- `--prefix PATH` sets the avatar-parameter prefix (default `/FT`).
- `--source PATH` reads another shared-memory file (default `/dev/shm/eye-server.mmap`), for replaying recordings.
- `--style anime` replaces the reference output with calibrated, stylised eyes: blinks become clean close-hold-open events per eye, squint appears only when partial closure is held, the lid dips on downward gaze, and gaze is smoothed with a One Euro filter and exaggerated on a bounded curve. Parameters are matched to the avatar, including bit-packed ones, when `--learn-port PORT` receives the client's OSC output; otherwise every v2 float is sent.
- `--no-heuristics` turns off the cheek and brow co-activations; `--gains FILE` reads `name value` lines to tune them.
- `--native` also sends the combined gaze to `/tracking/eye/CenterPitchYaw`.
- `--lost-at COV` is the gaze covariance above which an eye counts as lost, which holds the other eye open during a wink.
