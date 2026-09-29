// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_EXPRESSIONS_HPP
#define FRAMEEYEOSC_EXPRESSIONS_HPP

#include <string>

namespace frameeyeosc {

float clamp01(float v);
float clamp_signed(float v);

// Raw openness, gaze angles in -1..1.
struct EyeIn {
  float openness = 0.75f;
  float x = 0.0f;
  float y = 0.0f;
};

struct FrameIn {
  EyeIn left;
  EyeIn right;
};

// Per-eye openness levels: fully closed, relaxed open, wide open.
struct Calib {
  float closed = 0.0f;
  float neutral = 0.75f;
  float wide = 1.0f;
};

struct FrameCalib {
  Calib left;
  Calib right;
};

// Forces closed < neutral < wide so no division below can be by zero.
Calib normalized(const Calib &c);
// One sample's update: neutral follows a slow average that ignores blinks; wide is the
// highest openness seen, decaying toward neutral.
Calib calib_step(const Calib &c, float openness);
FrameCalib calib_step(const FrameCalib &c, const FrameIn &f);
bool calib_load(const std::string &path, FrameCalib &out);
bool calib_save(const std::string &path, const FrameCalib &c);

// Co-activation gains: what squint and wide pull along on the cheeks and brows.
struct Gains {
  float squint = 1.0f;
  float cheek_from_squint = 0.6f;
  float brow_down_from_squint = 0.5f;
  float brow_pinch_from_squint = 0.3f;
  float brow_inner_from_wide = 0.7f;
  float brow_outer_from_wide = 0.8f;
};

// Reads "name value" lines; unknown names are an error, missing ones keep their default.
bool gains_load(const std::string &path, Gains &out, std::string &error);

enum class Side { Left, Right };

struct EyeOut {
  float x = 0.0f;
  float y = 0.0f;
  float look_up = 0.0f;
  float look_down = 0.0f;
  float look_in = 0.0f;
  float look_out = 0.0f;
  float blink = 0.0f;
  float openness = 1.0f;
  float wide = 0.0f;
  float squint = 0.0f;
  float lid = 0.75f;  // 0 closed, 0.75 relaxed, 1 wide
  float cheek_squint = 0.0f;
  float brow_lowerer = 0.0f;
  float brow_pinch = 0.0f;
  float brow_inner_up = 0.0f;
  float brow_outer_up = 0.0f;
};

struct FrameOut {
  EyeOut left;
  EyeOut right;
  float x = 0.0f;
  float y = 0.0f;
};

float blink_of(const Calib &c, float openness);
float wide_of(const Calib &c, float openness);
EyeOut eye(Side side, const Gains &g, bool heuristics, const Calib &c, const EyeIn &e);
FrameOut frame(const Gains &g, bool heuristics, const FrameCalib &c, const FrameIn &f);
// Both eyes take the combined gaze, so large stylised eyes never cross.
FrameIn parallel(const FrameIn &f);
// Reflects the head through its midplane: eyes swap, horizontal gaze flips.
FrameIn mirror(const FrameIn &f);

} // namespace frameeyeosc

#endif
