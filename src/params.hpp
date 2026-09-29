// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_PARAMS_HPP
#define FRAMEEYEOSC_PARAMS_HPP

#include "expressions.hpp"
#include "osc.hpp"

#include <map>
#include <string>
#include <vector>

namespace frameeyeosc::params {

struct Param {
  const char *name;
  bool is_signed;
  float (*get)(const FrameOut &);
};

const std::vector<Param> &v2();
const std::vector<Param> &v1();

enum class Feed { Float, Bit, Negative };

// How one avatar parameter is fed.
struct Entry {
  std::string address;
  Feed feed = Feed::Float;
  const Param *param = nullptr;
  int bit = 0;
  int width = 0;  // how many bits the avatar has for this parameter
};

// The quantized magnitude a width-bit parameter carries, truncating.
int quantize(int width, float value);

// Builds the send list from (address, OSC type) pairs; types are "f", "i" or "T".
std::vector<Entry> plan(const std::vector<std::pair<std::string, std::string>> &avatar);
// Without a learned list: every v2 float under the prefix.
std::vector<Entry> fallback_plan(const std::string &prefix);
osc::Message message_for(const Entry &e, const FrameOut &o);

// The avatar's parameters, learned from the client's own OSC output.
struct Learned {
  std::string avatar;
  std::map<std::string, std::string> types;  // address -> "f", "i" or "T"
};
// Folds one message in; true when the parameter set changed.
bool observe(Learned &state, const osc::Message &m);
std::vector<std::pair<std::string, std::string>> list(const Learned &state);

} // namespace frameeyeosc::params

#endif
