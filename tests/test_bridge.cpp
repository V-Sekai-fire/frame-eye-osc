// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 konsti219
// SPDX-License-Identifier: MIT
#include "abi.h"

#include "check.hpp"
#include "witness_check.hpp"

#include <array>
#include <cmath>
#include <cstring>

static fe_sample open_eyes() {
  fe_sample s;
  std::memset(&s, 0, sizeof s);
  s.producer_state = 1;
  s.sample_time = 1.0;
  for (int e = 0; e < 2; ++e) {
    s.gaze[e].z = -1.0f;
    s.openness[e] = 0.8f;
  }
  s.fixation_point.z = -1.0f;
  return s;
}

static float value_of(const fe_message *p_messages, const char *p_name) {
  char want[128] = "/avatar/parameters/FT/v2/";
  std::strcat(want, p_name);
  for (int k = 0; k < FE_REFERENCE_MESSAGES; ++k) {
    if (fe_text_is(p_messages[k].address, want)) {
      return p_messages[k].args[0].f;
    }
  }
  return NAN;
}

TEST(straight_ahead_is_zero_gaze) {
  const fe_vec3 ahead = {0.0f, 0.0f, -1.0f};
  float x = 1.0f;
  float y = 1.0f;
  fe_gaze_angles(&ahead, &x, &y);
  CHECK(x == 0.0f);
  CHECK(y == 0.0f);
}

TEST(forty_five_degrees_right_and_up_map_to_one) {
  const fe_vec3 corner = {1.0f, 1.0f, -1.0f};
  float x = 0.0f;
  float y = 0.0f;
  fe_gaze_angles(&corner, &x, &y);
  CHECK(check::near(x, 1.0, 1e-6));
  CHECK(check::near(y, 1.0, 1e-6));
}

TEST(each_lid_follows_its_own_eye) {
  fe_sample s = open_eyes();
  s.openness[0] = 0.05f;
  fe_text prefix = fe_text_of("/FT");
  static fe_message ms[FE_REFERENCE_MESSAGES];
  fe_reference_messages(&s, &prefix, ms);
  CHECK(value_of(ms, "EyeLidLeft") == 0.05f);
  CHECK(value_of(ms, "EyeLidRight") == 0.8f);
}

TEST(lids_are_clamped) {
  fe_sample s = open_eyes();
  s.openness[0] = -0.2f;
  s.openness[1] = 1.4f;
  fe_text prefix = fe_text_of("/FT/");
  static fe_message ms[FE_REFERENCE_MESSAGES];
  fe_reference_messages(&s, &prefix, ms);
  CHECK(value_of(ms, "EyeLidLeft") == 0.0f);
  CHECK(value_of(ms, "EyeLidRight") == 1.0f);
}

TEST(first_message_marks_tracking_active) {
  fe_sample s = open_eyes();
  fe_text prefix = fe_text_of("/FT");
  static fe_message ms[FE_REFERENCE_MESSAGES];
  fe_reference_messages(&s, &prefix, ms);
  CHECK(fe_text_is(ms[0].address, "/avatar/parameters/FT/EyeTrackingActive"));
  CHECK(ms[0].args[0].tag == 'T');
}

TEST(invalid_samples_are_rejected) {
  fe_sample s = open_eyes();
  CHECK(fe_sample_valid(&s));
  s.openness[1] = NAN;
  CHECK(!fe_sample_valid(&s));
  s = open_eyes();
  s.producer_state = 0;
  CHECK(!fe_sample_valid(&s));
}

static std::array<float, 3> gen_direction(witness::RNG &p_rng, const witness::Level &) {
  return {(float)p_rng.int_range(-1000, 1000) / 100.0f, (float)p_rng.int_range(-1000, 1000) / 100.0f,
          (float)p_rng.int_range(-1000, -1) / 100.0f};
}

TEST(gaze_is_bounded_and_mirrors) {
  CHECK(holds<std::array<float, 3>>("gaze bounded and odd", &gen_direction, [](const std::array<float, 3> &p_d) {
    const fe_vec3 d = {p_d[0], p_d[1], p_d[2]};
    const fe_vec3 mirrored = {-p_d[0], -p_d[1], p_d[2]};
    float x = 0.0f;
    float y = 0.0f;
    float mx = 0.0f;
    float my = 0.0f;
    fe_gaze_angles(&d, &x, &y);
    fe_gaze_angles(&mirrored, &mx, &my);
    return std::fabs(x) <= 1.0f && std::fabs(y) <= 1.0f && x == -mx && y == -my;
  }));
}

TEST(control_unclamped_gaze_is_caught) {
  CHECK(caught<std::array<float, 3>>("unclamped gaze bounded", &gen_direction, [](const std::array<float, 3> &p_d) {
    return std::fabs(std::atan2(p_d[0], -p_d[2]) * 4.0f / 3.14159265f) <= 1.0f;
  }));
}
