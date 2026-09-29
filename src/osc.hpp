// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_OSC_HPP
#define FRAMEEYEOSC_OSC_HPP

#include <cstddef>
#include <cstdint>
#include <string>
#include <vector>

namespace frameeyeosc::osc {

// tag is one of 'f', 'i', 'T', 'F', 's'.
struct Arg {
  char tag = 'f';
  float f = 0.0f;
  int32_t i = 0;
  std::string s;
};

struct Message {
  std::string address;
  std::vector<Arg> args;
};

Arg float_arg(float value);
Arg int_arg(int32_t value);
Arg bool_arg(bool value);
Arg string_arg(const std::string &value);

bool operator==(const Arg &a, const Arg &b);
bool operator==(const Message &a, const Message &b);

std::vector<uint8_t> encode(const Message &message);
// False when the bytes are not one well-formed message.
bool decode(const uint8_t *data, size_t size, Message &out);
// A message or a #bundle, nested bundles flattened; malformed elements are skipped.
std::vector<Message> decode_packet(const uint8_t *data, size_t size);
std::vector<uint8_t> bundle(const std::vector<Message> &messages);

} // namespace frameeyeosc::osc

#endif
