// SPDX-License-Identifier: MIT
#include "anime.hpp"

#include "witness/doctest.h"

#include <cmath>
#include <functional>

using namespace frameeyeosc;
using namespace frameeyeosc::anime;

// Half a second of steps at 90 Hz with a fixed relative openness per eye.
static State hold(float rel_left, float rel_right) {
  State s;
  for (int k = 0; k < 45; ++k) {
    s = step(Tuning{}, 11.0f, s, rel_left, rel_right);
  }
  return s;
}

TEST_CASE("a wink leaves a half-open eye open") {
  State s = hold(0.0f, 0.4f);
  CHECK(s.left.phase == Phase::Closed);
  CHECK(s.right.phase == Phase::Opened);
}

TEST_CASE("both eyes shut close both (control)") {
  State s = hold(0.0f, 0.0f);
  CHECK(s.left.phase == Phase::Closed);
  CHECK(s.right.phase == Phase::Closed);
}

TEST_CASE("a shut eye shows fully shut and an open eye fully open") {
  EyeState closed;
  closed.phase = Phase::Closed;
  CHECK(level(Tuning{}, closed) == 0.0f);
  CHECK(level(Tuning{}, EyeState{}) == 1.0f);
}

TEST_CASE("an eye reopens after its reading rises past open_at") {
  State s = hold(0.0f, 1.0f);
  s = hold(1.0f, 1.0f);
  CHECK(s.left.phase == Phase::Opened);
}

TEST_CASE("the wink gate holds open only the eye the tracker still sees") {
  std::array<float, 2> g = wink_gate(true, false, 0.1f, 0.2f);
  CHECK(g[0] == 0.1f);
  CHECK(g[1] == 1.0f);
  g = wink_gate(false, true, 0.1f, 0.2f);
  CHECK(g[0] == 1.0f);
  CHECK(g[1] == 0.2f);
  g = wink_gate(true, true, 0.1f, 0.2f);
  CHECK(g[0] == 0.1f);
  CHECK(g[1] == 0.2f);
}

struct StyleCase {
  EyeState state;
  float raw;
  float look_down;
  Calib calib;
};

static StyleCase gen_style(witness::RNG &rng, const witness::Level &) {
  StyleCase c;
  c.state.phase = static_cast<Phase>(rng.uint_range(0, 3));
  c.state.t_ms = static_cast<float>(rng.uint_range(0, 500));
  c.state.from = static_cast<float>(rng.int_range(-50, 150)) / 100.0f;
  c.state.partial_ms = static_cast<float>(rng.uint_range(0, 2000));
  c.raw = static_cast<float>(rng.int_range(-100, 300)) / 100.0f;
  c.look_down = static_cast<float>(rng.int_range(0, 100)) / 100.0f;
  c.calib = Calib{static_cast<float>(rng.int_range(-50, 100)) / 100.0f, static_cast<float>(rng.int_range(-50, 150)) / 100.0f,
                  static_cast<float>(rng.int_range(-50, 200)) / 100.0f};
  return c;
}

TEST_CASE("[witness] the anime layer keeps every channel in 0..1") {
  witness::Generator<StyleCase> gen = &gen_style;
  std::function<bool(const StyleCase &)> pred = [](const StyleCase &c) {
    EyeOut base;
    base.look_down = c.look_down;
    EyeOut o = style_eye(Tuning{}, Gains{}, true, c.calib, c.raw, c.state, base);
    const float vs[] = {o.blink, o.openness, o.wide, o.squint, o.lid, o.cheek_squint, o.brow_lowerer,
                        o.brow_pinch, o.brow_inner_up, o.brow_outer_up};
    for (float v : vs) {
      if (!(v >= 0.0f && v <= 1.0f)) {
        return false;
      }
    }
    return true;
  };
  witness::Trial t = witness::resolve<StyleCase>("style in range", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

static std::pair<int, int> gen_pair(witness::RNG &rng, const witness::Level &) {
  return {rng.int_range(-900, 900), rng.int_range(-900, 900)};
}

TEST_CASE("[witness] expressive gaze is odd, bounded and never reverses") {
  witness::Generator<std::pair<int, int>> gen = &gen_pair;
  std::function<bool(const std::pair<int, int> &)> pred = [](const std::pair<int, int> &p) {
    float a = static_cast<float>(std::min(p.first, p.second)) / 10.0f;
    float b = static_cast<float>(std::max(p.first, p.second)) / 10.0f;
    float ea = expressive(1.8f, 30.0f, 1.5f, a);
    float eb = expressive(1.8f, 30.0f, 1.5f, b);
    return ea == -expressive(1.8f, 30.0f, 1.5f, -a) && std::fabs(ea) <= 30.0f && ea <= eb;
  };
  witness::Trial t = witness::resolve<std::pair<int, int>>("expressive gaze", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

TEST_CASE("[witness] control: a gain without the tanh limit is caught") {
  witness::Generator<std::pair<int, int>> gen = &gen_pair;
  std::function<bool(const std::pair<int, int> &)> pred = [](const std::pair<int, int> &p) {
    return std::fabs(1.8f * static_cast<float>(p.first) / 10.0f) <= 30.0f;
  };
  witness::Trial t = witness::resolve<std::pair<int, int>>("unlimited gaze bounded", gen, pred);
  CHECK(t.outcome == witness::Outcome::FOUND);
}

TEST_CASE("the One Euro filter holds still at rest and reaches a saccade") {
  OneEuro f;
  for (int k = 0; k < 90; ++k) {
    f = one_euro_step(f, 0.0f, 0.011f);
  }
  CHECK(f.x == 0.0f);
  for (int k = 0; k < 9; ++k) {
    f = one_euro_step(f, 20.0f, 0.011f);
  }
  CHECK(f.x > 15.0f);
}

TEST_CASE("pitch is positive looking down, yaw positive looking right") {
  const float down_right[3] = {0.3f, -0.3f, -1.0f};
  std::array<float, 2> py = pitch_yaw_degrees(down_right);
  CHECK(py[0] > 0.0f);
  CHECK(py[1] > 0.0f);
}
