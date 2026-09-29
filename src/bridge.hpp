// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_BRIDGE_HPP
#define FRAMEEYEOSC_BRIDGE_HPP

#include "eye_server.h"
#include "osc.hpp"

#include <array>
#include <string>
#include <vector>

namespace frameeyeosc {

// ±45° maps to ±1 on each axis, +Y up, from a -Z-forward direction.
std::array<float, 2> gaze_angles(const float direction[3]);
bool sample_valid(const fe_sample &sample);
// The reference output: raw gaze and each eye's own clamped openness.
std::vector<osc::Message> eye_messages(const fe_sample &sample, const std::string &prefix);
osc::Message tracking_active(const std::string &prefix, bool active);

} // namespace frameeyeosc

#endif
