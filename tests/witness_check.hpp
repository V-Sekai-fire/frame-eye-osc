// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_WITNESS_CHECK_HPP
#define FRAMEEYEOSC_WITNESS_CHECK_HPP

#include "check.hpp"
#include "witness/ladder.h"

#include <cstdio>
#include <functional>

// A property holds when the ladder finds no counter-example; a control must find one.
template <class T>
bool holds(const char *p_query, witness::Generator<T> p_gen, std::function<bool(const T &)> p_pred) {
  witness::Trial t = witness::resolve<T>(p_query, p_gen, p_pred);
  if (t.outcome == witness::Outcome::FOUND) {
    std::fprintf(stderr, "%s\n", t.message.c_str());
  }
  return t.outcome != witness::Outcome::FOUND;
}

template <class T>
bool caught(const char *p_query, witness::Generator<T> p_gen, std::function<bool(const T &)> p_pred) {
  witness::Trial t = witness::resolve<T>(p_query, p_gen, p_pred);
  return t.outcome == witness::Outcome::FOUND;
}

#endif
