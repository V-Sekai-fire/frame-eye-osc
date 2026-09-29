// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
#include "abi.h"

#include "check.hpp"

#include <algorithm>
#include <cstring>
#include <string>
#include <vector>

static const char *const kAddresses[] = {
    "/avatar/parameters/FT/v2/EyeLidLeft",          "/avatar/parameters/FT/v2/EyeLeftX",
    "/avatar/parameters/FT/v2/EyeSquintRight1",     "/avatar/parameters/FT/v2/EyeSquintRight2",
    "/avatar/parameters/FT/v2/EyeSquintRight4",     "/avatar/parameters/FT/v2/BrowExpressionLeft1",
    "/avatar/parameters/FT/v2/BrowExpressionLeftNegative", "/avatar/parameters/v2/EyeX",
    "/avatar/parameters/LeftEyeLid",                "/avatar/parameters/FT/v2/JawOpen",
    "/avatar/parameters/VRCEmote",
};
static const char kTypes[] = {'f', 'f', 'T', 'T', 'T', 'T', 'T', 'f', 'f', 'f', 'i'};
static const int kAvatarCount = sizeof kTypes;

static std::vector<fe_avatar_param> avatar() {
  std::vector<fe_avatar_param> out(kAvatarCount);
  for (int k = 0; k < kAvatarCount; ++k) {
    out[k].address = fe_text_of(kAddresses[k]);
    out[k].type = (uint8_t)kTypes[k];
  }
  return out;
}

static const fe_entry *find(const fe_entry *p_entries, int p_count, const char *p_address) {
  for (int k = 0; k < p_count; ++k) {
    if (fe_text_is(p_entries[k].address, p_address)) {
      return &p_entries[k];
    }
  }
  return nullptr;
}

TEST(plan_drives_the_nine_eye_parameters) {
  std::vector<fe_avatar_param> a = avatar();
  static fe_entry es[64];
  int n = fe_plan(a.data(), kAvatarCount, es, 64);
  CHECK(n == 9);
  CHECK(find(es, n, "/avatar/parameters/FT/v2/JawOpen") == nullptr);
  CHECK(find(es, n, "/avatar/parameters/VRCEmote") == nullptr);
}

TEST(bit_parameter_knows_its_width) {
  std::vector<fe_avatar_param> a = avatar();
  static fe_entry es[64];
  int n = fe_plan(a.data(), kAvatarCount, es, 64);
  const fe_entry *e = find(es, n, "/avatar/parameters/FT/v2/EyeSquintRight1");
  REQUIRE(e != nullptr);
  CHECK(e->width == 3);
  CHECK(e->bit == 0);
}

TEST(every_level_fits_and_round_trips) {
  for (int width = 1; width <= 6; ++width) {
    int steps = (1 << width) - 1;
    for (int level = 0; level <= steps; ++level) {
      float v = (float)level / (float)steps;
      int got = fe_quantize(width, v + 1e-6f);
      CHECK(got == level);
      CHECK(got < (1 << width));
    }
  }
}

TEST(quantizing_truncates_by_less_than_one_step) {
  for (int k = 0; k <= 1000; ++k) {
    float v = (float)k / 1000.0f;
    float step = 1.0f / 7.0f;
    float back = (float)fe_quantize(3, v) * step;
    CHECK(back <= v + 1e-6f);
    CHECK(v - back < step);
  }
}

TEST(negative_expression_sets_sign_and_magnitude) {
  std::vector<fe_avatar_param> a = avatar();
  static fe_entry es[64];
  int n = fe_plan(a.data(), kAvatarCount, es, 64);
  fe_frame_out o;
  std::memset(&o, 0, sizeof o);
  o.left.brow_lowerer = 1.0f;
  const fe_entry *neg = find(es, n, "/avatar/parameters/FT/v2/BrowExpressionLeftNegative");
  const fe_entry *bit = find(es, n, "/avatar/parameters/FT/v2/BrowExpressionLeft1");
  REQUIRE(neg != nullptr);
  REQUIRE(bit != nullptr);
  CHECK(fe_message_for(neg, &o).args[0].tag == 'T');
  CHECK(fe_message_for(bit, &o).args[0].tag == 'T');
}

static std::vector<std::string> addresses(const fe_entry *p_entries, int p_count) {
  std::vector<std::string> out;
  for (int k = 0; k < p_count; ++k) {
    out.push_back(std::string((const char *)p_entries[k].address.bytes, (size_t)p_entries[k].address.size));
  }
  std::sort(out.begin(), out.end());
  return out;
}

TEST(learning_builds_the_same_plan_as_a_parameter_list) {
  static fe_message out[kAvatarCount + 1];
  out[0] = fe_message_of("/avatar/change");
  fe_add_string(out[0], "avtr_test");
  for (int k = 0; k < kAvatarCount; ++k) {
    out[k + 1] = fe_message_of(kAddresses[k]);
    if (kTypes[k] == 'f') {
      fe_add_float(out[k + 1], 0.25f);
    } else if (kTypes[k] == 'i') {
      fe_add_int(out[k + 1], 3);
    } else {
      fe_add_bool(out[k + 1], false);
    }
  }
  static uint8_t packet[65536];
  int size = fe_osc_bundle(out, kAvatarCount + 1, packet, sizeof packet);
  REQUIRE(size > 0);
  static fe_message got[64];
  int count = fe_osc_decode_packet(packet, size, got, 64);
  static fe_learned st;
  fe_learned_clear(&st);
  for (int k = 0; k < count; ++k) {
    fe_observe(&st, &got[k]);
  }
  CHECK(fe_text_is(st.avatar, "avtr_test"));
  std::vector<fe_avatar_param> a = avatar();
  static fe_entry learned[64];
  static fe_entry listed[64];
  int na = fe_plan(st.params, st.count, learned, 64);
  int nb = fe_plan(a.data(), kAvatarCount, listed, 64);
  CHECK(addresses(learned, na) == addresses(listed, nb));
}

TEST(new_avatar_clears_what_was_learned) {
  static fe_learned st;
  fe_learned_clear(&st);
  fe_message m = fe_message_of("/avatar/parameters/FT/v2/EyeLidLeft");
  fe_add_float(m, 0.5f);
  fe_observe(&st, &m);
  CHECK(st.count == 1);
  m = fe_message_of("/avatar/change");
  fe_add_string(m, "other");
  CHECK(fe_observe(&st, &m));
  CHECK(st.count == 0);
}

TEST(fallback_plan_sends_every_v2_float) {
  static fe_entry es[64];
  fe_text prefix = fe_text_of("FT/");
  int n = fe_fallback_plan(&prefix, es, 64);
  CHECK(n == fe_v2_count());
  CHECK(find(es, n, "/avatar/parameters/FT/v2/EyeLidRight") != nullptr);
}
