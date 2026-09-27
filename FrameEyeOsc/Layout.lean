-- SPDX-License-Identifier: MIT
/-!
# The eye-server shared-memory layout

`abi/eye_server.sigs` names the calls. This file places the bytes, because a `.sigs`
file cannot. Offsets are from konsti219's reverse engineering of Frame firmware 0.5.0
(shm version 4), re-read from a live object on the dev kit on 2026-09-26.

Both tables are proved to tile their extent exactly: every field starts where the
previous one ends, and the last one ends at the stated size. Tiling implies the fields
are disjoint and in bounds. `abi/eye_server_layout.h` is generated from these tables,
so the C side is checked against the same numbers.
-/

namespace FrameEyeOsc.Layout

structure Field where
  name : String
  off  : Nat
  size : Nat
  deriving Repr, DecidableEq

/-- `true` when the fields sit back to back from `start` and end exactly at `stop`. -/
def tiles : List Field → Nat → Nat → Bool
  | [],      start, stop => start == stop
  | f :: fs, start, stop => f.off == start && tiles fs (f.off + f.size) stop

/-- Pairwise disjointness, stated directly, not derived from `tiles`. -/
def disjoint (a b : Field) : Bool := a.off + a.size ≤ b.off || b.off + b.size ≤ a.off

def pairwiseDisjoint : List Field → Bool
  | []      => true
  | f :: fs => fs.all (disjoint f) && pairwiseDisjoint fs

def shmSize    : Nat := 0x4F21A
def shmVersion : Nat := 4

/-- `EyeServerMmap`, the whole object. -/
def outer : List Field := [
  ⟨"version",            0x000, 4⟩,
  ⟨"initialized",        0x004, 4⟩,
  ⟨"metadata_mutex",     0x008, 0x30⟩,
  ⟨"sequence",           0x038, 4⟩,
  ⟨"metadata_requested", 0x03c, 4⟩,
  ⟨"other_control",      0x040, 0x112⟩,
  ⟨"eye_data",           0x152, 0xebc⟩ ]

def recordOff  : Nat := 0x152
def recordSize : Nat := 0xebc

/-- `EyeDataMmap`, packed. Vectors are f32, the timestamp is f64, little-endian. -/
def record : List Field := [
  ⟨"producer_state",       0x00, 4⟩,
  ⟨"sample_flag",          0x04, 1⟩,
  ⟨"sample_time",          0x05, 8⟩,
  ⟨"gaze_direction",       0x0d, 24⟩,   -- [left, right] × xyz, after stereo fusion
  ⟨"gaze_covariance_diag", 0x25, 24⟩,
  ⟨"fixation_point",       0x3d, 12⟩,   -- head-relative metres, -Z forward
  ⟨"pre_fusion_gaze",      0x49, 24⟩,
  ⟨"pre_fusion_cov_diag",  0x61, 24⟩,
  ⟨"openness",             0x79, 8⟩,    -- [left, right]
  ⟨"estimate_extra",       0x81, 32⟩,   -- 8 × f32, meaning not yet identified
  ⟨"reserved",             0xa1, 0xe1b⟩ ]

def offsetOf (fs : List Field) (name : String) : Nat :=
  (fs.find? (·.name == name)).map (·.off) |>.getD 0

theorem outer_tiles  : tiles outer 0 (recordOff + recordSize) = true := by decide
theorem record_tiles : tiles record 0 recordSize = true := by decide
theorem outer_disjoint  : pairwiseDisjoint outer = true := by decide
theorem record_disjoint : pairwiseDisjoint record = true := by decide
/-- The record, and so every field the reader copies, lies inside the mapping. -/
theorem record_fits : recordOff + recordSize ≤ shmSize := by decide

end FrameEyeOsc.Layout
