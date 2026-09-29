// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// A minimal test runner: TEST registers a function, CHECK records a failure and goes on,
// REQUIRE records a failure and leaves the test.
#ifndef FRAMEEYEOSC_CHECK_HPP
#define FRAMEEYEOSC_CHECK_HPP

#include <cmath>
#include <cstdio>
#include <vector>

namespace check {

struct Test {
  const char *name;
  void (*run)();
};

inline std::vector<Test> &tests() {
  static std::vector<Test> all;
  return all;
}

inline int &failures() {
  static int n = 0;
  return n;
}

inline int &checks() {
  static int n = 0;
  return n;
}

struct Register {
  Register(const char *p_name, void (*p_run)()) { tests().push_back(Test{p_name, p_run}); }
};

inline bool fail(const char *p_file, int p_line, const char *p_expr) {
  std::fprintf(stderr, "%s:%d: failed: %s\n", p_file, p_line, p_expr);
  failures() += 1;
  return false;
}

inline bool near(double p_a, double p_b, double p_eps) { return std::fabs(p_a - p_b) <= p_eps; }

} // namespace check

#define TEST(m_name)                                              \
  static void m_name();                                           \
  static check::Register m_name##_registered(#m_name, &m_name);   \
  static void m_name()

#define CHECK(...)                                             \
  do {                                                            \
    check::checks() += 1;                                         \
    if (!(__VA_ARGS__)) {                                         \
      check::fail(__FILE__, __LINE__, #__VA_ARGS__);              \
    }                                                             \
  } while (0)

#define REQUIRE(...)                                           \
  do {                                                            \
    check::checks() += 1;                                         \
    if (!(__VA_ARGS__)) {                                         \
      check::fail(__FILE__, __LINE__, #__VA_ARGS__);              \
      return;                                                     \
    }                                                             \
  } while (0)

#endif
