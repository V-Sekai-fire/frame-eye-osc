// SPDX-License-Identifier: MIT
#include "bridge.hpp"

#include "witness/doctest.h"

#include <cmath>
#include <cstring>
#include <functional>

using frameeyeosc::osc::Message;

static fe_sample open_eyes() {
  fe_sample s{};
  s.producer_state = 1;
  s.sample_time = 1.0;
  for (int e = 0; e < 2; ++e) {
    s.gaze[e][2] = -1.0f;
    s.openness[e] = 0.8f;
  }
  s.fixation_point[2] = -1.0f;
  return s;
}

static float lid(const std::vector<Message> &ms, const std::string &name) {
  for (const Message &m : ms) {
    if (m.address == "/avatar/parameters/FT/v2/" + name) {
      return m.args[0].f;
    }
  }
  return NAN;
}

TEST_CASE("straight ahead is zero gaze") {
  const float ahead[3] = {0.0f, 0.0f, -1.0f};
  std::array<float, 2> a = frameeyeosc::gaze_angles(ahead);
  CHECK(a[0] == doctest::Approx(0.0f));
  CHECK(a[1] == doctest::Approx(0.0f));
}

TEST_CASE("45 degrees right and up map to +1") {
  const float corner[3] = {1.0f, 1.0f, -1.0f};
  std::array<float, 2> a = frameeyeosc::gaze_angles(corner);
  CHECK(a[0] == doctest::Approx(1.0f));
  CHECK(a[1] == doctest::Approx(1.0f));
}

TEST_CASE("each lid follows its own eye's openness") {
  fe_sample s = open_eyes();
  s.openness[0] = 0.05f;
  std::vector<Message> ms = frameeyeosc::eye_messages(s, "/FT");
  CHECK(lid(ms, "EyeLidLeft") == doctest::Approx(0.05f));
  CHECK(lid(ms, "EyeLidRight") == doctest::Approx(0.8f));
}

TEST_CASE("lids are clamped to 0..1") {
  fe_sample s = open_eyes();
  s.openness[0] = -0.2f;
  s.openness[1] = 1.4f;
  std::vector<Message> ms = frameeyeosc::eye_messages(s, "/FT/");
  CHECK(lid(ms, "EyeLidLeft") == 0.0f);
  CHECK(lid(ms, "EyeLidRight") == 1.0f);
}

TEST_CASE("the first message marks eye tracking active") {
  std::vector<Message> ms = frameeyeosc::eye_messages(open_eyes(), "/FT");
  REQUIRE(ms.size() == 9);
  CHECK(ms[0].address == "/avatar/parameters/FT/EyeTrackingActive");
  CHECK(ms[0].args[0].tag == 'T');
}

TEST_CASE("invalid samples are rejected") {
  fe_sample s = open_eyes();
  CHECK(frameeyeosc::sample_valid(s));
  s.openness[1] = NAN;
  CHECK_FALSE(frameeyeosc::sample_valid(s));
  s = open_eyes();
  s.producer_state = 0;
  CHECK_FALSE(frameeyeosc::sample_valid(s));
}

static std::array<float, 3> gen_direction(witness::RNG &rng, const witness::Level &) {
  return {static_cast<float>(rng.int_range(-1000, 1000)) / 100.0f, static_cast<float>(rng.int_range(-1000, 1000)) / 100.0f,
          static_cast<float>(rng.int_range(-1000, -1)) / 100.0f};
}

TEST_CASE("[witness] gaze stays in -1..1 and mirrors with the direction") {
  witness::Generator<std::array<float, 3>> gen = &gen_direction;
  std::function<bool(const std::array<float, 3> &)> pred = [](const std::array<float, 3> &d) {
    const float mirrored[3] = {-d[0], -d[1], d[2]};
    std::array<float, 2> a = frameeyeosc::gaze_angles(d.data());
    std::array<float, 2> m = frameeyeosc::gaze_angles(mirrored);
    return std::fabs(a[0]) <= 1.0f && std::fabs(a[1]) <= 1.0f && a[0] == -m[0] && a[1] == -m[1];
  };
  witness::Trial t = witness::resolve<std::array<float, 3>>("gaze bounded and odd", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

TEST_CASE("[witness] control: an unclamped gaze is caught") {
  witness::Generator<std::array<float, 3>> gen = &gen_direction;
  std::function<bool(const std::array<float, 3> &)> pred = [](const std::array<float, 3> &d) {
    return std::fabs(std::atan2(d[0], -d[2]) * 4.0f / static_cast<float>(M_PI)) <= 1.0f;
  };
  witness::Trial t = witness::resolve<std::array<float, 3>>("unclamped gaze bounded", gen, pred);
  CHECK(t.outcome == witness::Outcome::FOUND);
}
