// SPDX-License-Identifier: MIT
#include "bridge.hpp"

#include <algorithm>
#include <cmath>
#include <utility>

namespace frameeyeosc {

std::array<float, 2> gaze_angles(const float d[3]) {
  const float scale = 4.0f / static_cast<float>(M_PI);
  float x = std::atan2(d[0], -d[2]) * scale;
  float y = std::atan2(d[1], -d[2]) * scale;
  return {std::clamp(x, -1.0f, 1.0f), std::clamp(y, -1.0f, 1.0f)};
}

bool sample_valid(const fe_sample &s) {
  if (s.producer_state != 1 || !std::isfinite(s.sample_time)) {
    return false;
  }
  for (int e = 0; e < 2; ++e) {
    for (int k = 0; k < 3; ++k) {
      if (!std::isfinite(s.gaze[e][k])) {
        return false;
      }
    }
    if (!std::isfinite(s.openness[e])) {
      return false;
    }
  }
  for (int k = 0; k < 3; ++k) {
    if (!std::isfinite(s.fixation_point[k])) {
      return false;
    }
  }
  return true;
}

static std::string base(const std::string &prefix) {
  std::string p = prefix;
  while (!p.empty() && p.back() == '/') {
    p.pop_back();
  }
  return "/avatar/parameters" + p;
}

osc::Message tracking_active(const std::string &prefix, bool active) {
  return osc::Message{base(prefix) + "/EyeTrackingActive", {osc::bool_arg(active)}};
}

std::vector<osc::Message> eye_messages(const fe_sample &s, const std::string &prefix) {
  std::array<float, 2> left = gaze_angles(s.gaze[0]);
  std::array<float, 2> right = gaze_angles(s.gaze[1]);
  std::array<float, 2> both = gaze_angles(s.fixation_point);
  const std::pair<const char *, float> values[] = {
      {"EyeLeftX", left[0]},
      {"EyeLeftY", left[1]},
      {"EyeRightX", right[0]},
      {"EyeRightY", right[1]},
      {"EyeLidLeft", std::clamp(s.openness[0], 0.0f, 1.0f)},
      {"EyeLidRight", std::clamp(s.openness[1], 0.0f, 1.0f)},
      {"EyeX", both[0]},
      {"EyeY", both[1]},
  };
  std::vector<osc::Message> out;
  out.push_back(tracking_active(prefix, true));
  for (const std::pair<const char *, float> &v : values) {
    out.push_back(osc::Message{base(prefix) + "/v2/" + v.first, {osc::float_arg(v.second)}});
  }
  return out;
}

} // namespace frameeyeosc
