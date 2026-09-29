// SPDX-License-Identifier: MIT
#include "params.hpp"

#include <doctest/doctest.h>

#include <algorithm>

using namespace frameeyeosc;
using namespace frameeyeosc::params;

static const std::vector<std::pair<std::string, std::string>> kAvatar = {
    {"/avatar/parameters/FT/v2/EyeLidLeft", "f"},
    {"/avatar/parameters/FT/v2/EyeLeftX", "f"},
    {"/avatar/parameters/FT/v2/EyeSquintRight1", "T"},
    {"/avatar/parameters/FT/v2/EyeSquintRight2", "T"},
    {"/avatar/parameters/FT/v2/EyeSquintRight4", "T"},
    {"/avatar/parameters/FT/v2/BrowExpressionLeft1", "T"},
    {"/avatar/parameters/FT/v2/BrowExpressionLeftNegative", "T"},
    {"/avatar/parameters/v2/EyeX", "f"},
    {"/avatar/parameters/LeftEyeLid", "f"},
    {"/avatar/parameters/FT/v2/JawOpen", "f"},
    {"/avatar/parameters/VRCEmote", "i"},
};

static const Entry *find(const std::vector<Entry> &es, const std::string &address) {
  for (const Entry &e : es) {
    if (e.address == address) {
      return &e;
    }
  }
  return nullptr;
}

TEST_CASE("the plan drives the 9 eye parameters and skips what the tracker cannot") {
  std::vector<Entry> es = plan(kAvatar);
  CHECK(es.size() == 9);
  CHECK(find(es, "/avatar/parameters/FT/v2/JawOpen") == nullptr);
  CHECK(find(es, "/avatar/parameters/VRCEmote") == nullptr);
}

TEST_CASE("a bit parameter knows how many bits the avatar has") {
  std::vector<Entry> es = plan(kAvatar);
  const Entry *e = find(es, "/avatar/parameters/FT/v2/EyeSquintRight1");
  REQUIRE(e != nullptr);
  CHECK(e->width == 3);
  CHECK(e->bit == 0);
}

TEST_CASE("packed bits decode back to every level, for every width in use") {
  for (int width = 1; width <= 6; ++width) {
    int steps = (1 << width) - 1;
    for (int level = 0; level <= steps; ++level) {
      float v = static_cast<float>(level) / static_cast<float>(steps);
      int got = quantize(width, v + 1e-6f);
      CHECK(got == level);
      CHECK(got < (1 << width));
    }
  }
}

TEST_CASE("quantizing truncates by less than one step") {
  for (int k = 0; k <= 1000; ++k) {
    float v = static_cast<float>(k) / 1000.0f;
    float step = 1.0f / 7.0f;
    float back = static_cast<float>(quantize(3, v)) * step;
    CHECK(back <= v + 1e-6f);
    CHECK(v - back < step);
  }
}

TEST_CASE("a negative expression sets the sign bit and the magnitude bits") {
  std::vector<Entry> es = plan(kAvatar);
  FrameOut o;
  o.left.brow_lowerer = 1.0f;
  const Entry *neg = find(es, "/avatar/parameters/FT/v2/BrowExpressionLeftNegative");
  const Entry *bit = find(es, "/avatar/parameters/FT/v2/BrowExpressionLeft1");
  REQUIRE(neg != nullptr);
  REQUIRE(bit != nullptr);
  CHECK(message_for(*neg, o).args[0].tag == 'T');
  CHECK(message_for(*bit, o).args[0].tag == 'T');
}

TEST_CASE("learning from the client's output builds the same plan as a parameter list") {
  std::vector<osc::Message> out = {osc::Message{"/avatar/change", {osc::string_arg("avtr_test")}}};
  for (const std::pair<std::string, std::string> &p : kAvatar) {
    osc::Arg a = p.second == "f" ? osc::float_arg(0.25f) : p.second == "i" ? osc::int_arg(3) : osc::bool_arg(false);
    out.push_back(osc::Message{p.first, {a}});
  }
  std::vector<uint8_t> packet = osc::bundle(out);
  Learned st;
  for (const osc::Message &m : osc::decode_packet(packet.data(), packet.size())) {
    observe(st, m);
  }
  CHECK(st.avatar == "avtr_test");
  std::vector<Entry> a = plan(list(st));
  std::vector<Entry> b = plan(kAvatar);
  std::vector<std::string> na;
  std::vector<std::string> nb;
  for (const Entry &e : a) {
    na.push_back(e.address);
  }
  for (const Entry &e : b) {
    nb.push_back(e.address);
  }
  std::sort(na.begin(), na.end());
  std::sort(nb.begin(), nb.end());
  CHECK(na == nb);
}

TEST_CASE("a new avatar clears what was learned") {
  Learned st;
  observe(st, osc::Message{"/avatar/parameters/FT/v2/EyeLidLeft", {osc::float_arg(0.5f)}});
  CHECK(list(st).size() == 1);
  CHECK(observe(st, osc::Message{"/avatar/change", {osc::string_arg("other")}}));
  CHECK(list(st).empty());
}

TEST_CASE("the fallback plan sends every v2 float under the prefix") {
  std::vector<Entry> es = fallback_plan("FT/");
  CHECK(es.size() == v2().size());
  CHECK(find(es, "/avatar/parameters/FT/v2/EyeLidRight") != nullptr);
}
