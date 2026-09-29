// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
#include "abi.h"

#include "check.hpp"
#include "witness_check.hpp"

static bool in01(float p_v) { return p_v >= 0.0f && p_v <= 1.0f; }
static bool in_signed(float p_v) { return p_v >= -1.0f && p_v <= 1.0f; }

static bool valid(const fe_eye_out &p_o) {
  return in_signed(p_o.x) && in_signed(p_o.y) && in01(p_o.look_up) && in01(p_o.look_down) && in01(p_o.look_in) &&
         in01(p_o.look_out) && in01(p_o.blink) && in01(p_o.openness) && in01(p_o.wide) && in01(p_o.squint) &&
         in01(p_o.lid) && in01(p_o.cheek_squint) && in01(p_o.brow_lowerer) && in01(p_o.brow_pinch) &&
         in01(p_o.brow_inner_up) && in01(p_o.brow_outer_up);
}

struct Case {
  fe_frame_in in;
  fe_frame_calib calib;
  fe_gains gains;
};

static float value(witness::RNG &p_rng, int p_lo, int p_hi) { return (float)p_rng.int_range(p_lo, p_hi) / 100.0f; }

static Case gen_case(witness::RNG &p_rng, const witness::Level &) {
  Case c;
  c.in.left = fe_eye_in{value(p_rng, -50, 250), value(p_rng, -300, 300), value(p_rng, -300, 300)};
  c.in.right = fe_eye_in{value(p_rng, -50, 250), value(p_rng, -300, 300), value(p_rng, -300, 300)};
  c.calib.left = fe_calib{value(p_rng, -50, 100), value(p_rng, -50, 150), value(p_rng, -50, 200)};
  c.calib.right = fe_calib{value(p_rng, -50, 100), value(p_rng, -50, 150), value(p_rng, -50, 200)};
  c.gains = fe_gains{value(p_rng, -300, 300), value(p_rng, -300, 300), value(p_rng, -300, 300),
                     value(p_rng, -300, 300), value(p_rng, -300, 300), value(p_rng, -300, 300)};
  return c;
}

TEST(every_weight_is_in_range) {
  CHECK(holds<Case>("weights in range", &gen_case, [](const Case &p_c) {
    fe_frame_out o = fe_frame(&p_c.gains, true, &p_c.calib, &p_c.in);
    return valid(o.left) && valid(o.right);
  }));
}

TEST(an_eye_is_never_both_closing_and_wide) {
  CHECK(holds<Case>("blink and wide exclusive", &gen_case, [](const Case &p_c) {
    return fe_blink_of(&p_c.calib.left, p_c.in.left.openness) == 0.0f ||
           fe_wide_of(&p_c.calib.left, p_c.in.left.openness) == 0.0f;
  }));
}

TEST(mirroring_the_face_mirrors_every_output) {
  CHECK(holds<Case>("mirror symmetry", &gen_case, [](const Case &p_c) {
    fe_frame_calib swapped = {p_c.calib.right, p_c.calib.left};
    fe_frame_in mirrored = fe_mirror(&p_c.in);
    fe_frame_out a = fe_frame(&p_c.gains, true, &swapped, &mirrored);
    fe_frame_out b = fe_frame(&p_c.gains, true, &p_c.calib, &p_c.in);
    return a.left.lid == b.right.lid && a.right.lid == b.left.lid && a.left.x == -b.right.x &&
           a.left.look_in == b.right.look_in && a.y == b.y;
  }));
}

TEST(control_unequal_lids_are_caught) {
  CHECK(caught<Case>("both lids always equal", &gen_case, [](const Case &p_c) {
    fe_frame_out a = fe_frame(&p_c.gains, true, &p_c.calib, &p_c.in);
    return a.left.lid == a.right.lid;
  }));
}

TEST(parallel_gaze_gives_both_eyes_the_same_direction) {
  fe_frame_in f = {{0.8f, 0.3f, -0.1f}, {0.8f, -0.2f, 0.4f}};
  fe_gains g = fe_gains_default();
  fe_frame_calib c = fe_frame_calib_default();
  fe_frame_in p = fe_parallel(&f);
  fe_frame_out o = fe_frame(&g, true, &c, &p);
  CHECK(o.left.x == o.right.x);
  CHECK(o.left.y == o.right.y);
}

TEST(normalized_calibration_is_strictly_ordered) {
  fe_calib raw = {0.9f, 0.5f, 0.1f};
  fe_calib c = fe_calib_normalized(&raw);
  CHECK(c.closed < c.neutral);
  CHECK(c.neutral < c.wide);
}

TEST(neutral_follows_open_samples_and_ignores_blinks) {
  fe_calib c = fe_calib_default();
  for (int k = 0; k < 5000; ++k) {
    c = fe_calib_step(&c, k % 50 == 0 ? 0.0f : 0.9f);
  }
  CHECK(check::near(c.neutral, 0.9, 0.01));
}

TEST(relaxed_open_reads_three_quarters_on_the_lid) {
  fe_calib c = fe_calib_default();
  fe_gains g = fe_gains_default();
  fe_eye_in relaxed = {0.75f, 0.0f, 0.0f};
  fe_eye_in shut = {0.0f, 0.0f, 0.0f};
  CHECK(check::near(fe_eye(0, &g, true, &c, &relaxed).lid, 0.75, 1e-6));
  CHECK(fe_eye(0, &g, true, &c, &shut).lid == 0.0f);
}

TEST(calibration_saves_and_loads) {
  fe_frame_calib c = {{0.1f, 0.7f, 0.95f}, {0.05f, 0.8f, 1.1f}};
  fe_text path = fe_text_of("/tmp/frameeyeosc-calib-test.txt");
  REQUIRE(fe_calib_save(&path, &c));
  fe_frame_calib back = fe_frame_calib_default();
  REQUIRE(fe_calib_load(&path, &back));
  CHECK(check::near(back.right.wide, 1.1, 1e-5));
  CHECK(check::near(back.left.neutral, 0.7, 1e-5));
}
