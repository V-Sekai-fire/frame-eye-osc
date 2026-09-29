// SPDX-License-Identifier: MIT
#include "osc.hpp"

#include <cstring>

namespace frameeyeosc::osc {

Arg float_arg(float value) {
  Arg a;
  a.tag = 'f';
  a.f = value;
  return a;
}

Arg int_arg(int32_t value) {
  Arg a;
  a.tag = 'i';
  a.i = value;
  return a;
}

Arg bool_arg(bool value) {
  Arg a;
  a.tag = value ? 'T' : 'F';
  return a;
}

Arg string_arg(const std::string &value) {
  Arg a;
  a.tag = 's';
  a.s = value;
  return a;
}

bool operator==(const Arg &a, const Arg &b) {
  if (a.tag != b.tag) {
    return false;
  }
  if (a.tag == 'f') {
    return std::memcmp(&a.f, &b.f, sizeof a.f) == 0;
  }
  if (a.tag == 'i') {
    return a.i == b.i;
  }
  if (a.tag == 's') {
    return a.s == b.s;
  }
  return true;
}

bool operator==(const Message &a, const Message &b) {
  if (a.address != b.address || a.args.size() != b.args.size()) {
    return false;
  }
  for (size_t k = 0; k < a.args.size(); ++k) {
    if (!(a.args[k] == b.args[k])) {
      return false;
    }
  }
  return true;
}

static void put_string(std::vector<uint8_t> &out, const std::string &s) {
  out.insert(out.end(), s.begin(), s.end());
  size_t pad = 4 - s.size() % 4;
  out.insert(out.end(), pad, 0);
}

static void put_u32(std::vector<uint8_t> &out, uint32_t v) {
  out.push_back(static_cast<uint8_t>(v >> 24));
  out.push_back(static_cast<uint8_t>(v >> 16));
  out.push_back(static_cast<uint8_t>(v >> 8));
  out.push_back(static_cast<uint8_t>(v));
}

std::vector<uint8_t> encode(const Message &m) {
  std::vector<uint8_t> out;
  put_string(out, m.address);
  std::string tags = ",";
  for (const Arg &a : m.args) {
    tags.push_back(a.tag);
  }
  put_string(out, tags);
  for (const Arg &a : m.args) {
    if (a.tag == 'f') {
      uint32_t bits = 0;
      std::memcpy(&bits, &a.f, sizeof bits);
      put_u32(out, bits);
    } else if (a.tag == 'i') {
      put_u32(out, static_cast<uint32_t>(a.i));
    } else if (a.tag == 's') {
      put_string(out, a.s);
    }
  }
  return out;
}

static bool read_string(const uint8_t *data, size_t size, size_t &at, std::string &out) {
  size_t end = at;
  while (end < size && data[end] != 0) {
    ++end;
  }
  if (end >= size) {
    return false;
  }
  out.assign(reinterpret_cast<const char *>(data + at), end - at);
  size_t next = (end + 4) & ~static_cast<size_t>(3);
  if (next > size) {
    return false;
  }
  at = next;
  return true;
}

static bool read_u32(const uint8_t *data, size_t size, size_t &at, uint32_t &out) {
  if (at + 4 > size) {
    return false;
  }
  out = (static_cast<uint32_t>(data[at]) << 24) | (static_cast<uint32_t>(data[at + 1]) << 16) |
        (static_cast<uint32_t>(data[at + 2]) << 8) | static_cast<uint32_t>(data[at + 3]);
  at += 4;
  return true;
}

bool decode(const uint8_t *data, size_t size, Message &out) {
  size_t at = 0;
  Message m;
  if (!read_string(data, size, at, m.address) || m.address.empty() || m.address[0] != '/') {
    return false;
  }
  std::string tags;
  if (!read_string(data, size, at, tags) || tags.empty() || tags[0] != ',') {
    return false;
  }
  for (size_t k = 1; k < tags.size(); ++k) {
    char tag = tags[k];
    uint32_t word = 0;
    if (tag == 'T' || tag == 'F') {
      m.args.push_back(bool_arg(tag == 'T'));
      continue;
    }
    if (tag == 's') {
      std::string s;
      if (!read_string(data, size, at, s)) {
        return false;
      }
      m.args.push_back(string_arg(s));
      continue;
    }
    if (tag != 'f' && tag != 'i') {
      return false;
    }
    if (!read_u32(data, size, at, word)) {
      return false;
    }
    if (tag == 'i') {
      m.args.push_back(int_arg(static_cast<int32_t>(word)));
      continue;
    }
    float f = 0.0f;
    std::memcpy(&f, &word, sizeof f);
    m.args.push_back(float_arg(f));
  }
  out = m;
  return true;
}

static const char kBundle[8] = {'#', 'b', 'u', 'n', 'd', 'l', 'e', 0};

static void decode_into(const uint8_t *data, size_t size, std::vector<Message> &out) {
  if (size < 16 || std::memcmp(data, kBundle, 8) != 0) {
    Message m;
    if (decode(data, size, m)) {
      out.push_back(m);
    }
    return;
  }
  size_t at = 16;
  while (at + 4 <= size) {
    uint32_t n = 0;
    read_u32(data, size, at, n);
    if (at + n > size) {
      return;
    }
    decode_into(data + at, n, out);
    at += n;
  }
}

std::vector<Message> decode_packet(const uint8_t *data, size_t size) {
  std::vector<Message> out;
  decode_into(data, size, out);
  return out;
}

std::vector<uint8_t> bundle(const std::vector<Message> &messages) {
  std::vector<uint8_t> out(kBundle, kBundle + 8);
  out.insert(out.end(), 8, 0);
  for (const Message &m : messages) {
    std::vector<uint8_t> b = encode(m);
    put_u32(out, static_cast<uint32_t>(b.size()));
    out.insert(out.end(), b.begin(), b.end());
  }
  return out;
}

} // namespace frameeyeosc::osc
