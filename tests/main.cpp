// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
#include "check.hpp"

#include <cstring>

int main(int argc, char **argv) {
  const char *only = argc > 1 ? argv[1] : nullptr;
  int ran = 0;
  for (const check::Test &t : check::tests()) {
    if (only != nullptr && std::strstr(t.name, only) == nullptr) {
      continue;
    }
    int before = check::failures();
    t.run();
    ran += 1;
    std::printf("%s %s\n", check::failures() == before ? "ok  " : "FAIL", t.name);
  }
  std::printf("%d tests, %d checks, %d failures\n", ran, check::checks(), check::failures());
  return check::failures() == 0 && ran > 0 ? 0 : 1;
}
