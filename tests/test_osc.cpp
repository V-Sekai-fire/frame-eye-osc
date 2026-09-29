// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
#include "abi.h"

#include "check.hpp"
#include "witness_check.hpp"

#include <cstring>

TEST(float_message_encodes_padded) {
  fe_message m = fe_message_of("/a");
  fe_add_float(m, 1.0f);
  uint8_t b[64];
  int n = fe_osc_encode(&m, b, sizeof b);
  const uint8_t want[] = {'/', 'a', 0, 0, ',', 'f', 0, 0, 0x3f, 0x80, 0, 0};
  REQUIRE(n == (int)sizeof want);
  CHECK(std::memcmp(b, want, sizeof want) == 0);
}

TEST(four_character_address_still_gets_a_terminator) {
  fe_message m = fe_message_of("/abc");
  fe_add_bool(m, true);
  uint8_t b[64];
  int n = fe_osc_encode(&m, b, sizeof b);
  const uint8_t want[] = {'/', 'a', 'b', 'c', 0, 0, 0, 0, ',', 'T', 0, 0};
  REQUIRE(n == (int)sizeof want);
  CHECK(std::memcmp(b, want, sizeof want) == 0);
}

TEST(encode_refuses_a_small_buffer) {
  fe_message m = fe_message_of("/abc");
  fe_add_float(m, 0.5f);
  uint8_t b[8];
  CHECK(fe_osc_encode(&m, b, sizeof b) == 0);
}

TEST(bundle_of_three_decodes_to_all_three) {
  static fe_message ms[3];
  ms[0] = fe_message_of("/a");
  fe_add_float(ms[0], 0.5f);
  ms[1] = fe_message_of("/b");
  fe_add_bool(ms[1], true);
  ms[2] = fe_message_of("/c");
  fe_add_int(ms[2], 7);
  uint8_t b[256];
  int n = fe_osc_bundle(ms, 3, b, sizeof b);
  REQUIRE(n > 0);
  static fe_message got[8];
  REQUIRE(fe_osc_decode_packet(b, n, got, 8) == 3);
  CHECK(fe_osc_equal(&got[0], &ms[0]));
  CHECK(fe_osc_equal(&got[1], &ms[1]));
  CHECK(fe_osc_equal(&got[2], &ms[2]));
}

TEST(nested_bundle_is_flattened) {
  static fe_message inner[2];
  inner[0] = fe_message_of("/x");
  fe_add_int(inner[0], 1);
  inner[1] = fe_message_of("/y");
  fe_add_int(inner[1], 2);
  uint8_t in[256];
  int n_in = fe_osc_bundle(inner, 2, in, sizeof in);
  REQUIRE(n_in > 0);
  // An outer bundle whose one element is the inner bundle.
  uint8_t out[512] = {'#', 'b', 'u', 'n', 'd', 'l', 'e', 0};
  out[16] = (uint8_t)(n_in >> 24);
  out[17] = (uint8_t)(n_in >> 16);
  out[18] = (uint8_t)(n_in >> 8);
  out[19] = (uint8_t)n_in;
  std::memcpy(out + 20, in, (size_t)n_in);
  static fe_message got[8];
  REQUIRE(fe_osc_decode_packet(out, 20 + n_in, got, 8) == 2);
  CHECK(fe_osc_equal(&got[1], &inner[1]));
}

TEST(control_truncated_message_does_not_decode) {
  fe_message m = fe_message_of("/abc");
  fe_add_float(m, 0.5f);
  uint8_t b[64];
  int n = fe_osc_encode(&m, b, sizeof b);
  static fe_message back;
  CHECK(fe_osc_decode(b, n, &back));
  CHECK(!fe_osc_decode(b, n - 1, &back));
}

static fe_message gen_message(witness::RNG &p_rng, const witness::Level &) {
  char address[64] = "/avatar/parameters/";
  size_t n = p_rng.uint_range(0, 30);
  for (size_t k = 0; k < n; ++k) {
    address[19 + k] = (char)('a' + p_rng.uint_range(0, 25));
  }
  address[19 + n] = 0;
  fe_message m = fe_message_of(address);
  uint32_t args = p_rng.uint_range(0, 4);
  for (uint32_t k = 0; k < args; ++k) {
    uint32_t kind = p_rng.uint_range(0, 3);
    if (kind == 0) {
      fe_add_float(m, (float)p_rng.int_range(-100000, 100000) / 97.0f);
    } else if (kind == 1) {
      fe_add_int(m, p_rng.int_range(-100000, 100000));
    } else if (kind == 2) {
      fe_add_bool(m, p_rng.uint_range(0, 1) == 1);
    } else {
      fe_add_string(m, address);
    }
  }
  return m;
}

TEST(every_message_round_trips_word_aligned) {
  CHECK(holds<fe_message>("osc round trip", &gen_message, [](const fe_message &p_m) {
    uint8_t b[2048];
    int n = fe_osc_encode(&p_m, b, sizeof b);
    fe_message back;
    return n > 0 && n % 4 == 0 && fe_osc_decode(b, n, &back) && fe_osc_equal(&back, &p_m);
  }));
}

TEST(control_dropping_the_last_byte_is_caught) {
  CHECK(caught<fe_message>("truncated round trip", &gen_message, [](const fe_message &p_m) {
    uint8_t b[2048];
    int n = fe_osc_encode(&p_m, b, sizeof b);
    fe_message back;
    return fe_osc_decode(b, n - 1, &back) && fe_osc_equal(&back, &p_m);
  }));
}
