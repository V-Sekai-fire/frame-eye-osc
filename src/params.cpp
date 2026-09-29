// SPDX-License-Identifier: MIT
#include "params.hpp"

#include <algorithm>
#include <cmath>

namespace frameeyeosc::params {

static float avg(float a, float b) { return (a + b) / 2.0f; }

const std::vector<Param> &v2() {
  static const std::vector<Param> table = {
      {"EyeLeftX", true, [](const FrameOut &o) { return o.left.x; }},
      {"EyeLeftY", true, [](const FrameOut &o) { return o.left.y; }},
      {"EyeRightX", true, [](const FrameOut &o) { return o.right.x; }},
      {"EyeRightY", true, [](const FrameOut &o) { return o.right.y; }},
      {"EyeX", true, [](const FrameOut &o) { return o.x; }},
      {"EyeY", true, [](const FrameOut &o) { return o.y; }},
      {"EyeLidLeft", false, [](const FrameOut &o) { return o.left.lid; }},
      {"EyeLidRight", false, [](const FrameOut &o) { return o.right.lid; }},
      {"EyeLid", false, [](const FrameOut &o) { return avg(o.left.lid, o.right.lid); }},
      {"EyeOpennessLeft", false, [](const FrameOut &o) { return o.left.openness; }},
      {"EyeOpennessRight", false, [](const FrameOut &o) { return o.right.openness; }},
      {"EyeWideLeft", false, [](const FrameOut &o) { return o.left.wide; }},
      {"EyeWideRight", false, [](const FrameOut &o) { return o.right.wide; }},
      {"EyeWide", false, [](const FrameOut &o) { return avg(o.left.wide, o.right.wide); }},
      {"EyeSquintLeft", false, [](const FrameOut &o) { return o.left.squint; }},
      {"EyeSquintRight", false, [](const FrameOut &o) { return o.right.squint; }},
      {"EyeSquint", false, [](const FrameOut &o) { return avg(o.left.squint, o.right.squint); }},
      {"CheekSquintLeft", false, [](const FrameOut &o) { return o.left.cheek_squint; }},
      {"CheekSquintRight", false, [](const FrameOut &o) { return o.right.cheek_squint; }},
      {"CheekSquint", false, [](const FrameOut &o) { return avg(o.left.cheek_squint, o.right.cheek_squint); }},
      {"BrowLowererLeft", false, [](const FrameOut &o) { return o.left.brow_lowerer; }},
      {"BrowLowererRight", false, [](const FrameOut &o) { return o.right.brow_lowerer; }},
      {"BrowPinchLeft", false, [](const FrameOut &o) { return o.left.brow_pinch; }},
      {"BrowPinchRight", false, [](const FrameOut &o) { return o.right.brow_pinch; }},
      {"BrowInnerUpLeft", false, [](const FrameOut &o) { return o.left.brow_inner_up; }},
      {"BrowInnerUpRight", false, [](const FrameOut &o) { return o.right.brow_inner_up; }},
      {"BrowInnerUp", false, [](const FrameOut &o) { return avg(o.left.brow_inner_up, o.right.brow_inner_up); }},
      {"BrowOuterUpLeft", false, [](const FrameOut &o) { return o.left.brow_outer_up; }},
      {"BrowOuterUpRight", false, [](const FrameOut &o) { return o.right.brow_outer_up; }},
      {"BrowOuterUp", false, [](const FrameOut &o) { return avg(o.left.brow_outer_up, o.right.brow_outer_up); }},
      {"BrowUpLeft", false, [](const FrameOut &o) { return avg(o.left.brow_inner_up, o.left.brow_outer_up); }},
      {"BrowUpRight", false, [](const FrameOut &o) { return avg(o.right.brow_inner_up, o.right.brow_outer_up); }},
      {"BrowUp", false,
       [](const FrameOut &o) {
         return avg(avg(o.left.brow_inner_up, o.left.brow_outer_up), avg(o.right.brow_inner_up, o.right.brow_outer_up));
       }},
      {"BrowDownLeft", false, [](const FrameOut &o) { return o.left.brow_lowerer; }},
      {"BrowDownRight", false, [](const FrameOut &o) { return o.right.brow_lowerer; }},
      {"BrowDown", false, [](const FrameOut &o) { return avg(o.left.brow_lowerer, o.right.brow_lowerer); }},
      {"BrowExpressionLeft", true,
       [](const FrameOut &o) { return avg(o.left.brow_inner_up, o.left.brow_outer_up) - o.left.brow_lowerer; }},
      {"BrowExpressionRight", true,
       [](const FrameOut &o) { return avg(o.right.brow_inner_up, o.right.brow_outer_up) - o.right.brow_lowerer; }},
  };
  return table;
}

const std::vector<Param> &v1() {
  static const std::vector<Param> table = {
      {"LeftEyeX", true, [](const FrameOut &o) { return o.left.x; }},
      {"RightEyeX", true, [](const FrameOut &o) { return o.right.x; }},
      {"EyesX", true, [](const FrameOut &o) { return o.x; }},
      {"EyesY", true, [](const FrameOut &o) { return o.y; }},
      {"LeftEyeLid", false, [](const FrameOut &o) { return o.left.openness; }},
      {"RightEyeLid", false, [](const FrameOut &o) { return o.right.openness; }},
      {"CombinedEyeLid", false, [](const FrameOut &o) { return avg(o.left.openness, o.right.openness); }},
      {"LeftEyeWiden", false, [](const FrameOut &o) { return o.left.wide; }},
      {"RightEyeWiden", false, [](const FrameOut &o) { return o.right.wide; }},
      {"EyesWiden", false, [](const FrameOut &o) { return avg(o.left.wide, o.right.wide); }},
      {"LeftEyeSqueeze", false, [](const FrameOut &o) { return o.left.squint; }},
      {"RightEyeSqueeze", false, [](const FrameOut &o) { return o.right.squint; }},
      {"EyesSqueeze", false, [](const FrameOut &o) { return avg(o.left.squint, o.right.squint); }},
      {"LeftEyeLidExpandedSqueeze", true, [](const FrameOut &o) { return o.left.lid - o.left.squint; }},
      {"RightEyeLidExpandedSqueeze", true, [](const FrameOut &o) { return o.right.lid - o.right.squint; }},
  };
  return table;
}

int quantize(int width, float value) {
  float magnitude = std::min(std::fabs(value), 1.0f);
  int steps = (1 << width) - 1;
  return static_cast<int>(std::floor(magnitude * static_cast<float>(steps)));
}

static const std::string kParams = "/avatar/parameters/";

static bool strip(const std::string &prefix, std::string &s) {
  if (s.compare(0, prefix.size(), prefix) != 0) {
    return false;
  }
  s = s.substr(prefix.size());
  return true;
}

static bool ends_with(const std::string &s, const std::string &suffix) {
  return s.size() >= suffix.size() && s.compare(s.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// "/avatar/parameters/FT/v2/EyeLid" -> v2 "EyeLid"; "/avatar/parameters/LeftEyeLid" -> v1.
static bool split_name(const std::string &address, bool &is_v2, std::string &name) {
  std::string n = address;
  if (!strip(kParams, n)) {
    return false;
  }
  strip("FT/", n);
  if (strip("v2/", n)) {
    is_v2 = true;
    name = n;
    return true;
  }
  if (n.find('/') != std::string::npos) {
    return false;
  }
  is_v2 = false;
  name = n;
  return true;
}

static const Param *lookup(bool is_v2, const std::string &name) {
  const std::vector<Param> &table = is_v2 ? v2() : v1();
  for (const Param &p : table) {
    if (name == p.name) {
      return &p;
    }
  }
  return nullptr;
}

static const std::pair<const char *, int> kBitSuffixes[] = {{"128", 7}, {"64", 6}, {"32", 5}, {"16", 4},
                                                           {"8", 3},   {"4", 2},  {"2", 1},  {"1", 0}};

struct Parsed {
  std::string address;
  std::string type;
  bool is_v2;
  std::string name;
};

static int width_of(const std::vector<Parsed> &all, bool is_v2, const std::string &base) {
  int n = 0;
  for (const Parsed &p : all) {
    if (p.is_v2 != is_v2 || p.type == "f") {
      continue;
    }
    for (const std::pair<const char *, int> &s : kBitSuffixes) {
      if (p.name == base + s.first) {
        ++n;
      }
    }
  }
  return n;
}

static bool bit_entry(const std::vector<Parsed> &all, const Parsed &p, Entry &e) {
  for (const std::pair<const char *, int> &s : kBitSuffixes) {
    if (!ends_with(p.name, s.first)) {
      continue;
    }
    std::string base = p.name.substr(0, p.name.size() - std::string(s.first).size());
    const Param *param = lookup(p.is_v2, base);
    if (param == nullptr) {
      return false;
    }
    e = Entry{p.address, Feed::Bit, param, s.second, width_of(all, p.is_v2, base)};
    return true;
  }
  return false;
}

std::vector<Entry> plan(const std::vector<std::pair<std::string, std::string>> &avatar) {
  std::vector<Parsed> all;
  for (const std::pair<std::string, std::string> &a : avatar) {
    Parsed p{a.first, a.second, false, ""};
    if (split_name(a.first, p.is_v2, p.name)) {
      all.push_back(p);
    }
  }
  std::vector<Entry> out;
  for (const Parsed &p : all) {
    if (p.type == "f") {
      const Param *param = lookup(p.is_v2, p.name);
      if (param != nullptr) {
        out.push_back(Entry{p.address, Feed::Float, param, 0, 0});
      }
      continue;
    }
    if (ends_with(p.name, "Negative")) {
      const Param *param = lookup(p.is_v2, p.name.substr(0, p.name.size() - 8));
      if (param != nullptr) {
        out.push_back(Entry{p.address, Feed::Negative, param, 0, 0});
      }
      continue;
    }
    Entry e;
    if (bit_entry(all, p, e)) {
      out.push_back(e);
    }
  }
  return out;
}

std::vector<Entry> fallback_plan(const std::string &prefix) {
  std::vector<Entry> out;
  for (const Param &p : v2()) {
    out.push_back(Entry{kParams + prefix + "v2/" + p.name, Feed::Float, &p, 0, 0});
  }
  return out;
}

osc::Message message_for(const Entry &e, const FrameOut &o) {
  float raw = e.param->get(o);
  float v = e.param->is_signed ? clamp_signed(raw) : clamp01(raw);
  osc::Message m{e.address, {}};
  if (e.feed == Feed::Float) {
    m.args.push_back(osc::float_arg(v));
    return m;
  }
  if (e.feed == Feed::Negative) {
    m.args.push_back(osc::bool_arg(v < 0.0f));
    return m;
  }
  m.args.push_back(osc::bool_arg(((quantize(e.width, v) >> e.bit) & 1) != 0));
  return m;
}

bool observe(Learned &state, const osc::Message &m) {
  if (m.address == "/avatar/change") {
    state.avatar = m.args.size() == 1 && m.args[0].tag == 's' ? m.args[0].s : "";
    state.types.clear();
    return true;
  }
  if (m.address.compare(0, kParams.size(), kParams) != 0 || m.args.empty()) {
    return false;
  }
  char tag = m.args[0].tag;
  if (tag == 's') {
    return false;
  }
  if (state.types.count(m.address) != 0) {
    return false;
  }
  state.types[m.address] = tag == 'f' ? "f" : tag == 'i' ? "i" : "T";
  return true;
}

std::vector<std::pair<std::string, std::string>> list(const Learned &state) {
  return std::vector<std::pair<std::string, std::string>>(state.types.begin(), state.types.end());
}

} // namespace frameeyeosc::params
