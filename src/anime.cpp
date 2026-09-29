// SPDX-License-Identifier: MIT
#include "anime.hpp"

#include <algorithm>
#include <cmath>

namespace frameeyeosc::anime {

float relative(const Calib &c, float o) {
  Calib n = normalized(c);
  return (o - n.closed) / (n.neutral - n.closed);
}

float level(const Tuning &k, const EyeState &s) {
  if (s.phase == Phase::Opened) {
    return 1.0f;
  }
  if (s.phase == Phase::Closed) {
    return 0.0f;
  }
  if (s.phase == Phase::Closing) {
    if (k.close_ms <= 0.0f) {
      return 0.0f;
    }
    return clamp01(s.from * (1.0f - std::min(s.t_ms, k.close_ms) / k.close_ms));
  }
  if (k.open_ms <= 0.0f) {
    return 1.0f;
  }
  float remaining = k.open_ms - std::min(s.t_ms, k.open_ms);
  return clamp01(1.0f - remaining * remaining / (k.open_ms * k.open_ms));
}

static EyeState start(const Tuning &k, const EyeState &s, Phase p) {
  EyeState n = s;
  n.from = level(k, s);
  n.phase = p;
  n.t_ms = 0.0f;
  return n;
}

EyeState step_eye(const Tuning &k, float dt_ms, const EyeState &prev, float rel) {
  EyeState s = prev;
  s.t_ms += dt_ms;
  bool partial = s.phase == Phase::Opened && rel < k.squint_at && rel >= k.close_at;
  s.partial_ms = partial ? s.partial_ms + dt_ms : 0.0f;
  if (s.phase == Phase::Opened) {
    return rel < k.close_at ? start(k, s, Phase::Closing) : s;
  }
  if (s.phase == Phase::Closing) {
    return s.t_ms >= k.close_ms ? start(k, s, Phase::Closed) : s;
  }
  if (s.phase == Phase::Closed) {
    return rel > k.open_at ? start(k, s, Phase::Opening) : s;
  }
  if (rel < k.close_at) {
    return start(k, s, Phase::Closing);
  }
  return s.t_ms >= k.open_ms ? start(k, s, Phase::Opened) : s;
}

State step(const Tuning &k, float dt_ms, const State &s, float rel_left, float rel_right) {
  State n;
  n.left = step_eye(k, dt_ms, s.left, rel_left);
  n.right = step_eye(k, dt_ms, s.right, rel_right);
  return n;
}

EyeOut style_eye(const Tuning &k, const Gains &g, bool heuristics, const Calib &c, float raw,
                 const EyeState &s, const EyeOut &base) {
  EyeOut o = base;
  float follow = clamp01(level(k, s) - k.lid_follow * base.look_down);
  float rel = relative(c, raw);
  bool opened = s.phase == Phase::Opened;
  o.blink = clamp01(1.0f - follow);
  o.openness = follow;
  o.wide = opened ? clamp01(rel - 1.0f - k.wide_dead_zone) : 0.0f;
  o.lid = clamp01(follow * 0.75f + o.wide * 0.25f);
  o.squint = 0.0f;
  float hold = s.partial_ms - k.squint_after_ms;
  if (heuristics && opened && hold > 0.0f) {
    float ramp = std::min(1.0f, hold / std::max(1.0f, k.squint_full_ms));
    o.squint = clamp01(ramp * (k.squint_at - rel) / (k.squint_at - k.close_at));
  }
  if (!heuristics) {
    return o;
  }
  o.cheek_squint = clamp01(g.cheek_from_squint * o.squint);
  o.brow_lowerer = clamp01(g.brow_down_from_squint * o.squint);
  o.brow_pinch = clamp01(g.brow_pinch_from_squint * o.squint);
  o.brow_inner_up = clamp01(g.brow_inner_from_wide * o.wide);
  o.brow_outer_up = clamp01(g.brow_outer_from_wide * o.wide);
  return o;
}

std::array<float, 2> wink_gate(bool lost_left, bool lost_right, float rel_left, float rel_right) {
  if (lost_left && !lost_right) {
    return {rel_left, std::max(rel_right, 1.0f)};
  }
  if (lost_right && !lost_left) {
    return {std::max(rel_left, 1.0f), rel_right};
  }
  return {rel_left, rel_right};
}

bool eye_lost(const float cov[3], float threshold) {
  return std::max(cov[0], std::max(cov[1], cov[2])) > threshold;
}

float expressive(float gain, float limit, float dead, float degrees) {
  float m = std::fabs(degrees) - dead;
  if (m <= 0.0f || limit <= 0.0f) {
    return 0.0f;
  }
  float v = limit * std::tanh(gain * m / limit);
  return degrees < 0.0f ? -v : v;
}

static float alpha(float cutoff_hz, float dt_s) {
  float tau = 1.0f / (2.0f * static_cast<float>(M_PI) * cutoff_hz);
  return 1.0f / (1.0f + tau / dt_s);
}

OneEuro one_euro_step(const OneEuro &f, float value, float dt_s) {
  const float min_cutoff = 1.2f;
  const float beta = 0.04f;
  const float d_cutoff = 1.0f;
  if (!f.primed || dt_s <= 0.0f) {
    return OneEuro{value, 0.0f, true};
  }
  float speed = (value - f.x) / dt_s;
  float dx = f.dx + alpha(d_cutoff, dt_s) * (speed - f.dx);
  float cutoff = min_cutoff + beta * std::fabs(dx);
  return OneEuro{f.x + alpha(cutoff, dt_s) * (value - f.x), dx, true};
}

std::array<float, 2> pitch_yaw_degrees(const float d[3]) {
  const float to_deg = 180.0f / static_cast<float>(M_PI);
  float pitch = -std::atan2(d[1], -d[2]) * to_deg;
  float yaw = std::atan2(d[0], -d[2]) * to_deg;
  return {std::clamp(pitch, -45.0f, 45.0f), std::clamp(yaw, -45.0f, 45.0f)};
}

std::array<float, 3> center_direction(const float l[3], const float r[3]) {
  float x = l[0] + r[0];
  float y = l[1] + r[1];
  float z = l[2] + r[2];
  float n = std::sqrt(x * x + y * y + z * z);
  if (n < 1.0e-6f) {
    return {0.0f, 0.0f, -1.0f};
  }
  return {x / n, y / n, z / n};
}

} // namespace frameeyeosc::anime
