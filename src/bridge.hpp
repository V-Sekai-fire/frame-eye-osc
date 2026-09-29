// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_BRIDGE_HPP
#define FRAMEEYEOSC_BRIDGE_HPP

#include "eye_server.h"

#include <array>
#include <cstdint>
#include <string>
#include <vector>

namespace frameeyeosc {

struct Message {
  enum class Kind { Float, Bool };
  std::string address;
  Kind kind;
  float value;
  bool flag;
};

// ±45° maps to ±1 on each axis, +Y up, from a -Z-forward direction.
std::array<float, 2> gaze_angles(const float direction[3]);
bool sample_valid(const fe_sample &sample);
std::vector<Message> eye_messages(const fe_sample &sample, const std::string &prefix);
Message tracking_active(const std::string &prefix, bool active);
std::vector<uint8_t> encode(const Message &message);

} // namespace frameeyeosc

#endif
