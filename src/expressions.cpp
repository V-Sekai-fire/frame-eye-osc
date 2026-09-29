// SPDX-License-Identifier: MIT
#include "expressions.hpp"

#include <algorithm>
#include <fstream>
#include <sstream>

namespace frameeyeosc {

float clamp01(float v) { return std::clamp(v, 0.0f, 1.0f); }

float clamp_signed(float v) { return std::clamp(v, -1.0f, 1.0f); }

static const float kMinGap = 0.0001f;

Calib normalized(const Calib &c) {
  Calib n = c;
  n.closed = std::min(c.closed, c.neutral - kMinGap);
  n.wide = std::max(c.wide, c.neutral + kMinGap);
  return n;
}

Calib calib_step(const Calib &c, float o) {
  Calib n = c;
  if (o > c.neutral - 0.2f) {
    n.neutral = c.neutral + (o - c.neutral) / 512.0f;
  }
  if (o > c.wide) {
    n.wide = o;
    return n;
  }
  n.wide = std::max(n.neutral + 0.05f, c.wide - kMinGap);
  return n;
}

FrameCalib calib_step(const FrameCalib &c, const FrameIn &f) {
  FrameCalib n;
  n.left = calib_step(c.left, f.left.openness);
  n.right = calib_step(c.right, f.right.openness);
  return n;
}

bool calib_load(const std::string &path, FrameCalib &out) {
  std::ifstream in(path);
  if (!in) {
    return false;
  }
  FrameCalib c;
  std::string side;
  for (int k = 0; k < 2; ++k) {
    Calib e;
    if (!(in >> side >> e.closed >> e.neutral >> e.wide)) {
      return false;
    }
    if (side == "left") {
      c.left = e;
    } else if (side == "right") {
      c.right = e;
    } else {
      return false;
    }
  }
  out = c;
  return true;
}

bool calib_save(const std::string &path, const FrameCalib &c) {
  std::ofstream out(path);
  if (!out) {
    return false;
  }
  out << "left " << c.left.closed << ' ' << c.left.neutral << ' ' << c.left.wide << '\n';
  out << "right " << c.right.closed << ' ' << c.right.neutral << ' ' << c.right.wide << '\n';
  return static_cast<bool>(out);
}

bool gains_load(const std::string &path, Gains &out, std::string &error) {
  std::ifstream in(path);
  if (!in) {
    error = path + ": cannot open";
    return false;
  }
  Gains g = out;
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty() || line[0] == '#') {
      continue;
    }
    std::istringstream words(line);
    std::string name;
    float value = 0.0f;
    if (!(words >> name >> value)) {
      error = path + ": bad line: " + line;
      return false;
    }
    if (name == "squint") {
      g.squint = value;
    } else if (name == "cheek_from_squint") {
      g.cheek_from_squint = value;
    } else if (name == "brow_down_from_squint") {
      g.brow_down_from_squint = value;
    } else if (name == "brow_pinch_from_squint") {
      g.brow_pinch_from_squint = value;
    } else if (name == "brow_inner_from_wide") {
      g.brow_inner_from_wide = value;
    } else if (name == "brow_outer_from_wide") {
      g.brow_outer_from_wide = value;
    } else {
      error = path + ": unknown gain " + name;
      return false;
    }
  }
  out = g;
  return true;
}

float blink_of(const Calib &c, float o) {
  Calib n = normalized(c);
  if (o >= n.neutral) {
    return 0.0f;
  }
  return clamp01((n.neutral - o) / (n.neutral - n.closed));
}

float wide_of(const Calib &c, float o) {
  Calib n = normalized(c);
  if (o <= n.neutral) {
    return 0.0f;
  }
  return clamp01((o - n.neutral) / (n.wide - n.neutral));
}

// Peaks at half closure, zero when fully open or fully shut.
static float tent(float blink) { return 2.0f * std::min(blink, 1.0f - blink); }

EyeOut eye(Side side, const Gains &g, bool heuristics, const Calib &c, const EyeIn &e) {
  EyeOut o;
  o.x = clamp_signed(e.x);
  o.y = clamp_signed(e.y);
  float nasal = side == Side::Left ? o.x : -o.x;
  o.look_up = clamp01(o.y);
  o.look_down = clamp01(-o.y);
  o.look_in = clamp01(nasal);
  o.look_out = clamp01(-nasal);
  o.blink = blink_of(c, e.openness);
  o.wide = wide_of(c, e.openness);
  o.openness = clamp01(1.0f - o.blink);
  o.lid = clamp01(o.openness * 0.75f + o.wide * 0.25f);
  if (!heuristics) {
    o.squint = 0.0f;
    return o;
  }
  o.squint = clamp01(g.squint * tent(o.blink));
  o.cheek_squint = clamp01(g.cheek_from_squint * o.squint);
  o.brow_lowerer = clamp01(g.brow_down_from_squint * o.squint);
  o.brow_pinch = clamp01(g.brow_pinch_from_squint * o.squint);
  o.brow_inner_up = clamp01(g.brow_inner_from_wide * o.wide);
  o.brow_outer_up = clamp01(g.brow_outer_from_wide * o.wide);
  return o;
}

FrameOut frame(const Gains &g, bool heuristics, const FrameCalib &c, const FrameIn &f) {
  FrameOut o;
  o.left = eye(Side::Left, g, heuristics, c.left, f.left);
  o.right = eye(Side::Right, g, heuristics, c.right, f.right);
  o.x = (o.left.x + o.right.x) / 2.0f;
  o.y = (o.left.y + o.right.y) / 2.0f;
  return o;
}

FrameIn parallel(const FrameIn &f) {
  FrameIn p = f;
  float x = (f.left.x + f.right.x) / 2.0f;
  float y = (f.left.y + f.right.y) / 2.0f;
  p.left.x = x;
  p.left.y = y;
  p.right.x = x;
  p.right.y = y;
  return p;
}

FrameIn mirror(const FrameIn &f) {
  FrameIn m;
  m.left = f.right;
  m.left.x = -f.right.x;
  m.right = f.left;
  m.right.x = -f.left.x;
  return m;
}

} // namespace frameeyeosc
