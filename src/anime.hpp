// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_ANIME_HPP
#define FRAMEEYEOSC_ANIME_HPP

#include "expressions.hpp"

#include <array>

namespace frameeyeosc::anime {

// Openness thresholds are relative: 0 shut, 1 relaxed open.
struct Tuning {
  float close_at = 0.35f;
  float open_at = 0.55f;
  float close_ms = 60.0f;
  float open_ms = 140.0f;
  float squint_at = 0.8f;
  float squint_after_ms = 250.0f;
  float squint_full_ms = 400.0f;
  float wide_dead_zone = 0.2f;
  float lid_follow = 0.25f;  // how far the lid drops per unit of downward gaze
};

enum class Phase { Opened, Closing, Closed, Opening };

struct EyeState {
  Phase phase = Phase::Opened;
  float t_ms = 0.0f;
  float from = 1.0f;  // lid level when the phase began
  float partial_ms = 0.0f;
};

struct State {
  EyeState left;
  EyeState right;
};

float relative(const Calib &c, float openness);
// The lid a phase shows: 1 open, 0 shut, linear close, ease-out open.
float level(const Tuning &k, const EyeState &s);
EyeState step_eye(const Tuning &k, float dt_ms, const EyeState &s, float rel);
// Each eye steps on its own reading; one eye closing never pulls the other along.
State step(const Tuning &k, float dt_ms, const State &s, float rel_left, float rel_right);
// Rebuilds one eye's lid, wide and squint from its blink state; gaze is kept.
EyeOut style_eye(const Tuning &k, const Gains &g, bool heuristics, const Calib &c, float raw,
                 const EyeState &s, const EyeOut &base);

// When the tracker loses exactly one eye, the eye it still sees is held open.
std::array<float, 2> wink_gate(bool lost_left, bool lost_right, float rel_left, float rel_right);
bool eye_lost(const float covariance[3], float threshold);

// Dead-zone, then a gain on small glances easing into limit along tanh. Odd and monotone.
float expressive(float gain, float limit, float dead, float degrees);

// One Euro filter: steady at rest, fast on a saccade.
struct OneEuro {
  float x = 0.0f;
  float dx = 0.0f;
  bool primed = false;
};
OneEuro one_euro_step(const OneEuro &f, float value, float dt_s);

// Pitch (positive looks down) and yaw (positive looks right) in degrees, clamped to ±45.
std::array<float, 2> pitch_yaw_degrees(const float direction[3]);
// The mean of both eyes' directions, normalized.
std::array<float, 3> center_direction(const float left[3], const float right[3]);

} // namespace frameeyeosc::anime

#endif
