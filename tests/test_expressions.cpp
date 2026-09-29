// SPDX-License-Identifier: MIT
#include "expressions.hpp"

#include "witness/doctest.h"

#include <cmath>
#include <functional>

using namespace frameeyeosc;

static bool in01(float v) { return v >= 0.0f && v <= 1.0f; }
static bool in_signed(float v) { return v >= -1.0f && v <= 1.0f; }

static bool valid(const EyeOut &o) {
  return in_signed(o.x) && in_signed(o.y) && in01(o.look_up) && in01(o.look_down) && in01(o.look_in) &&
         in01(o.look_out) && in01(o.blink) && in01(o.openness) && in01(o.wide) && in01(o.squint) && in01(o.lid) &&
         in01(o.cheek_squint) && in01(o.brow_lowerer) && in01(o.brow_pinch) && in01(o.brow_inner_up) &&
         in01(o.brow_outer_up);
}

struct Case {
  FrameIn in;
  FrameCalib calib;
  Gains gains;
};

static float value(witness::RNG &rng, int lo, int hi) { return static_cast<float>(rng.int_range(lo, hi)) / 100.0f; }

static Case gen_case(witness::RNG &rng, const witness::Level &) {
  Case c;
  c.in.left = EyeIn{value(rng, -50, 250), value(rng, -300, 300), value(rng, -300, 300)};
  c.in.right = EyeIn{value(rng, -50, 250), value(rng, -300, 300), value(rng, -300, 300)};
  c.calib.left = Calib{value(rng, -50, 100), value(rng, -50, 150), value(rng, -50, 200)};
  c.calib.right = Calib{value(rng, -50, 100), value(rng, -50, 150), value(rng, -50, 200)};
  c.gains = Gains{value(rng, -300, 300), value(rng, -300, 300), value(rng, -300, 300),
                  value(rng, -300, 300), value(rng, -300, 300), value(rng, -300, 300)};
  return c;
}

TEST_CASE("[witness] every weight is in range for any input, calibration and gains") {
  witness::Generator<Case> gen = &gen_case;
  std::function<bool(const Case &)> pred = [](const Case &c) {
    FrameOut o = frame(c.gains, true, c.calib, c.in);
    return valid(o.left) && valid(o.right);
  };
  witness::Trial t = witness::resolve<Case>("weights in range", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

TEST_CASE("[witness] an eye is never both closing and wide") {
  witness::Generator<Case> gen = &gen_case;
  std::function<bool(const Case &)> pred = [](const Case &c) {
    return blink_of(c.calib.left, c.in.left.openness) == 0.0f || wide_of(c.calib.left, c.in.left.openness) == 0.0f;
  };
  witness::Trial t = witness::resolve<Case>("blink and wide exclusive", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

TEST_CASE("[witness] mirroring the face mirrors every output") {
  witness::Generator<Case> gen = &gen_case;
  std::function<bool(const Case &)> pred = [](const Case &c) {
    FrameCalib swapped{c.calib.right, c.calib.left};
    FrameOut a = frame(c.gains, true, swapped, mirror(c.in));
    FrameOut b = frame(c.gains, true, c.calib, c.in);
    return a.left.lid == b.right.lid && a.right.lid == b.left.lid && a.left.x == -b.right.x &&
           a.left.look_in == b.right.look_in && a.y == b.y;
  };
  witness::Trial t = witness::resolve<Case>("mirror symmetry", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

TEST_CASE("[witness] control: an unmirrored face is caught") {
  witness::Generator<Case> gen = &gen_case;
  std::function<bool(const Case &)> pred = [](const Case &c) {
    FrameOut a = frame(c.gains, true, c.calib, c.in);
    return a.left.lid == a.right.lid;
  };
  witness::Trial t = witness::resolve<Case>("both lids always equal", gen, pred);
  CHECK(t.outcome == witness::Outcome::FOUND);
}

TEST_CASE("parallel gaze gives both eyes the same direction") {
  FrameIn f;
  f.left = EyeIn{0.8f, 0.3f, -0.1f};
  f.right = EyeIn{0.8f, -0.2f, 0.4f};
  FrameOut o = frame(Gains{}, true, FrameCalib{}, parallel(f));
  CHECK(o.left.x == o.right.x);
  CHECK(o.left.y == o.right.y);
}

TEST_CASE("a normalized calibration is strictly ordered") {
  Calib c = normalized(Calib{0.9f, 0.5f, 0.1f});
  CHECK(c.closed < c.neutral);
  CHECK(c.neutral < c.wide);
}

TEST_CASE("neutral follows open samples and ignores blinks") {
  Calib c;
  for (int k = 0; k < 5000; ++k) {
    c = calib_step(c, k % 50 == 0 ? 0.0f : 0.9f);
  }
  CHECK(c.neutral == doctest::Approx(0.9f).epsilon(0.01));
}

TEST_CASE("relaxed open reads 0.75 on the lid, shut reads 0") {
  Calib c;
  CHECK(eye(Side::Left, Gains{}, true, c, EyeIn{0.75f, 0.0f, 0.0f}).lid == doctest::Approx(0.75f));
  CHECK(eye(Side::Left, Gains{}, true, c, EyeIn{0.0f, 0.0f, 0.0f}).lid == 0.0f);
}
