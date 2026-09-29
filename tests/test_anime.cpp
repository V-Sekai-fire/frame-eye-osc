// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
#include "abi.h"

#include "check.hpp"
#include "witness_check.hpp"

#include <algorithm>
#include <utility>

// Half a second of steps at 90 Hz with a fixed relative openness per eye.
static fe_style_state hold(float p_rel_left, float p_rel_right) {
  fe_tuning k = fe_tuning_default();
  fe_style_state s = fe_style_state_default();
  for (int i = 0; i < 45; ++i) {
    s = fe_style_step(&k, 11.0f, &s, p_rel_left, p_rel_right);
  }
  return s;
}

TEST(wink_leaves_a_half_open_eye_open) {
  fe_style_state s = hold(0.0f, 0.4f);
  CHECK(s.left.phase == FE_CLOSED);
  CHECK(s.right.phase == FE_OPENED);
}

TEST(control_both_eyes_shut_close_both) {
  fe_style_state s = hold(0.0f, 0.0f);
  CHECK(s.left.phase == FE_CLOSED);
  CHECK(s.right.phase == FE_CLOSED);
}

TEST(shut_shows_shut_and_open_shows_open) {
  fe_tuning k = fe_tuning_default();
  fe_eye_state open = fe_eye_state_default();
  fe_eye_state closed = fe_eye_state_default();
  closed.phase = FE_CLOSED;
  CHECK(fe_level(&k, &closed) == 0.0f);
  CHECK(fe_level(&k, &open) == 1.0f);
}

TEST(an_eye_reopens_after_its_reading_rises) {
  fe_tuning k = fe_tuning_default();
  fe_style_state s = hold(0.0f, 1.0f);
  for (int i = 0; i < 45; ++i) {
    s = fe_style_step(&k, 11.0f, &s, 1.0f, 1.0f);
  }
  CHECK(s.left.phase == FE_OPENED);
}

TEST(wink_gate_holds_open_only_the_seen_eye) {
  float l = 0.1f;
  float r = 0.2f;
  fe_wink_gate(true, false, &l, &r);
  CHECK(l == 0.1f);
  CHECK(r == 1.0f);
  l = 0.1f;
  r = 0.2f;
  fe_wink_gate(false, true, &l, &r);
  CHECK(l == 1.0f);
  CHECK(r == 0.2f);
  l = 0.1f;
  r = 0.2f;
  fe_wink_gate(true, true, &l, &r);
  CHECK(l == 0.1f);
  CHECK(r == 0.2f);
}

struct StyleCase {
  fe_eye_state state;
  float raw;
  float look_down;
  fe_calib calib;
};

static StyleCase gen_style(witness::RNG &p_rng, const witness::Level &) {
  StyleCase c;
  c.state.phase = (int32_t)p_rng.uint_range(0, 3);
  c.state.t_ms = (float)p_rng.uint_range(0, 500);
  c.state.from = (float)p_rng.int_range(-50, 150) / 100.0f;
  c.state.partial_ms = (float)p_rng.uint_range(0, 2000);
  c.raw = (float)p_rng.int_range(-100, 300) / 100.0f;
  c.look_down = (float)p_rng.int_range(0, 100) / 100.0f;
  c.calib = fe_calib{(float)p_rng.int_range(-50, 100) / 100.0f, (float)p_rng.int_range(-50, 150) / 100.0f,
                     (float)p_rng.int_range(-50, 200) / 100.0f};
  return c;
}

TEST(anime_layer_keeps_every_channel_in_range) {
  CHECK(holds<StyleCase>("style in range", &gen_style, [](const StyleCase &p_c) {
    fe_tuning k = fe_tuning_default();
    fe_gains g = fe_gains_default();
    fe_calib c = fe_calib_default();
    fe_eye_in e = {0.75f, 0.0f, 0.0f};
    fe_eye_out base = fe_eye(0, &g, true, &c, &e);
    base.look_down = p_c.look_down;
    fe_eye_out o = fe_style_eye(&k, &g, true, &p_c.calib, p_c.raw, &p_c.state, &base);
    const float vs[] = {o.blink, o.openness, o.wide, o.squint, o.lid, o.cheek_squint, o.brow_lowerer,
                        o.brow_pinch, o.brow_inner_up, o.brow_outer_up};
    for (float v : vs) {
      if (!(v >= 0.0f && v <= 1.0f)) {
        return false;
      }
    }
    return true;
  }));
}

static std::pair<int, int> gen_pair(witness::RNG &p_rng, const witness::Level &) {
  return {p_rng.int_range(-900, 900), p_rng.int_range(-900, 900)};
}

TEST(expressive_gaze_is_odd_bounded_and_monotone) {
  CHECK(holds<std::pair<int, int>>("expressive gaze", &gen_pair, [](const std::pair<int, int> &p_p) {
    float a = (float)std::min(p_p.first, p_p.second) / 10.0f;
    float b = (float)std::max(p_p.first, p_p.second) / 10.0f;
    float ea = fe_expressive(1.8f, 30.0f, 1.5f, a);
    float eb = fe_expressive(1.8f, 30.0f, 1.5f, b);
    return ea == -fe_expressive(1.8f, 30.0f, 1.5f, -a) && std::fabs(ea) <= 30.0f && ea <= eb;
  }));
}

TEST(control_gain_without_limit_is_caught) {
  CHECK(caught<std::pair<int, int>>("unlimited gaze bounded", &gen_pair, [](const std::pair<int, int> &p_p) {
    return std::fabs(1.8f * (float)p_p.first / 10.0f) <= 30.0f;
  }));
}

TEST(one_euro_holds_still_and_reaches_a_saccade) {
  fe_one_euro f = {0.0f, 0.0f, false};
  for (int k = 0; k < 90; ++k) {
    f = fe_one_euro_step(&f, 0.0f, 0.011f);
  }
  CHECK(f.x == 0.0f);
  for (int k = 0; k < 9; ++k) {
    f = fe_one_euro_step(&f, 20.0f, 0.011f);
  }
  CHECK(f.x > 15.0f);
}

TEST(pitch_positive_down_yaw_positive_right) {
  const fe_vec3 down_right = {0.3f, -0.3f, -1.0f};
  float pitch = 0.0f;
  float yaw = 0.0f;
  fe_pitch_yaw_degrees(&down_right, &pitch, &yaw);
  CHECK(pitch > 0.0f);
  CHECK(yaw > 0.0f);
}
