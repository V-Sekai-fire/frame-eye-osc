// SPDX-License-Identifier: MIT
#include "osc.hpp"

#include "witness/doctest.h"

#include <cstring>
#include <functional>

using frameeyeosc::osc::Message;
namespace osc = frameeyeosc::osc;

TEST_CASE("a float message encodes as padded address, tag and big-endian value") {
  std::vector<uint8_t> b = osc::encode(Message{"/a", {osc::float_arg(1.0f)}});
  const uint8_t want[] = {'/', 'a', 0, 0, ',', 'f', 0, 0, 0x3f, 0x80, 0, 0};
  REQUIRE(b.size() == sizeof want);
  CHECK(std::memcmp(b.data(), want, sizeof want) == 0);
}

TEST_CASE("an address of four characters still gets a terminator") {
  std::vector<uint8_t> b = osc::encode(Message{"/abc", {osc::bool_arg(true)}});
  const uint8_t want[] = {'/', 'a', 'b', 'c', 0, 0, 0, 0, ',', 'T', 0, 0};
  REQUIRE(b.size() == sizeof want);
  CHECK(std::memcmp(b.data(), want, sizeof want) == 0);
}

TEST_CASE("a bundle of three messages decodes to all three") {
  std::vector<Message> ms = {Message{"/a", {osc::float_arg(0.5f)}}, Message{"/b", {osc::bool_arg(true)}},
                             Message{"/c", {osc::int_arg(7)}}};
  std::vector<uint8_t> b = osc::bundle(ms);
  std::vector<Message> got = osc::decode_packet(b.data(), b.size());
  REQUIRE(got.size() == 3);
  CHECK(got[0] == ms[0]);
  CHECK(got[1] == ms[1]);
  CHECK(got[2] == ms[2]);
}

TEST_CASE("a truncated message does not decode (control)") {
  std::vector<uint8_t> b = osc::encode(Message{"/abc", {osc::float_arg(0.5f)}});
  Message m;
  CHECK(osc::decode(b.data(), b.size(), m));
  CHECK_FALSE(osc::decode(b.data(), b.size() - 1, m));
}

static Message gen_message(witness::RNG &rng, const witness::Level &) {
  Message m;
  m.address = "/avatar/parameters/";
  uint32_t n = rng.uint_range(0, 30);
  for (uint32_t k = 0; k < n; ++k) {
    m.address.push_back(static_cast<char>('a' + rng.uint_range(0, 25)));
  }
  uint32_t args = rng.uint_range(0, 4);
  for (uint32_t k = 0; k < args; ++k) {
    uint32_t kind = rng.uint_range(0, 3);
    if (kind == 0) {
      m.args.push_back(osc::float_arg(static_cast<float>(rng.int_range(-100000, 100000)) / 97.0f));
    } else if (kind == 1) {
      m.args.push_back(osc::int_arg(rng.int_range(-100000, 100000)));
    } else if (kind == 2) {
      m.args.push_back(osc::bool_arg(rng.uint_range(0, 1) == 1));
    } else {
      m.args.push_back(osc::string_arg(m.address));
    }
  }
  return m;
}

TEST_CASE("[witness] every message round-trips and is word-aligned") {
  witness::Generator<Message> gen = &gen_message;
  std::function<bool(const Message &)> pred = [](const Message &m) {
    std::vector<uint8_t> b = osc::encode(m);
    Message back;
    return b.size() % 4 == 0 && osc::decode(b.data(), b.size(), back) && back == m;
  };
  witness::Trial t = witness::resolve<Message>("osc round trip", gen, pred);
  CHECK(t.outcome != witness::Outcome::FOUND);
}

TEST_CASE("[witness] control: dropping the last byte is caught") {
  witness::Generator<Message> gen = &gen_message;
  std::function<bool(const Message &)> pred = [](const Message &m) {
    std::vector<uint8_t> b = osc::encode(m);
    Message back;
    return osc::decode(b.data(), b.size() - 1, back) && back == m;
  };
  witness::Trial t = witness::resolve<Message>("truncated round trip", gen, pred);
  CHECK(t.outcome == witness::Outcome::FOUND);
}
