# 0001: Rewrite in Lean 4, drive VRChat without VRCFaceTracking

## Decision

The Rust bridge is replaced by a Lean 4 program. The code that runs is also the code
the theorems are about. It finds VRChat over mDNS/OSCQuery, on the PC or on the Frame,
and sends VRCFaceTracking-named avatar parameters straight to it, so VRCFaceTracking
does not need to run anywhere.

## What is proved, and what is only tested

| Claim | How | Where |
|---|---|---|
| shm fields tile their extents, are disjoint, fit the mapping | `decide` | `FrameEyeOsc/Layout.lean` |
| C struct offsets match that table | `_Static_assert`, header generated from the table, `layout_header --check` | `ffi/shm.c` |
| every libc call in `abi/eye_server.sigs` matches glibc | compiled as redeclarations (`conflicting types` otherwise) | `lakefile.lean`, `ffi/eye_server_decls.h` |
| every weight in [0,1], every axis in [-1,1], for any input, calibration or gains | theorem | `Expressions.eye_valid` |
| blink and wide never both nonzero | theorem | `Expressions.blink_wide_exclusive` |
| mirroring the face mirrors every output | theorem | `Expressions.frame_mirror` |
| binary level fits its bits; truncation error under one step; bits round-trip (1–6 bits) | theorems | `Params.level_lt`, `level_error`, `bits_roundtrip_*` |
| OSC packets are whole 32-bit words | theorem | `Osc.encode_len_mod4` |
| OSC decode ∘ encode, shm decode, `ofFloat`, DNS, parameter matching | plausible properties | `Proptest.lean` |
| each claim above, searched for counter-examples, with a planted broken control that must be caught | plausible-witness-dag | `Falsify.lean` |

The mapping runs in integer 1/10000 units so that `omega` can decide it. `Float` appears
only when a sample is decoded and when an OSC float is encoded. Those two edges are
covered by the property tests.

## Why `.sigs` does not generate a dispatch table here

`iceoryx2.sigs` and `nvenc.sigs` feed `generate_stubs.py` because those libraries are
`dlopen`ed. The eye server is a shared-memory object, and the calls against it are libc
calls. A dlsym table would define `mmap` and friends in our own object and interpose on
them for the Lean runtime too. So the `.sigs` file is checked instead: its lines are
compiled as redeclarations next to glibc's own headers.

## What the Frame cannot give

It has eye cameras only. Mouth, jaw, cheek-puff, nose and tongue expressions are never
sent. Squint, brow and cheek-squint values are co-activation heuristics from eyelid
openness (`data/eye_facial_action.json`, off with `--no-heuristics`) until the Phase 2
eye-camera keypoint work can measure them.
