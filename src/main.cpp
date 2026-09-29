// SPDX-License-Identifier: MIT
#include "bridge.hpp"

#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <unistd.h>

#include <cstdio>
#include <cstring>
#include <string>

static int usage() {
  std::fprintf(stderr, "usage: frameeyeosc [--target HOST:PORT] [--prefix /FT] [--source PATH]\n");
  return 2;
}

static int connect_udp(const std::string &target) {
  size_t colon = target.rfind(':');
  if (colon == std::string::npos) {
    return -1;
  }
  std::string host = target.substr(0, colon);
  std::string port = target.substr(colon + 1);
  addrinfo hints{};
  hints.ai_socktype = SOCK_DGRAM;
  addrinfo *res = nullptr;
  if (getaddrinfo(host.c_str(), port.c_str(), &hints, &res) != 0 || res == nullptr) {
    return -1;
  }
  int fd = socket(res->ai_family, SOCK_DGRAM, 0);
  if (fd < 0) {
    freeaddrinfo(res);
    return -1;
  }
  if (connect(fd, res->ai_addr, res->ai_addrlen) != 0) {
    close(fd);
    freeaddrinfo(res);
    return -1;
  }
  freeaddrinfo(res);
  return fd;
}

static void send_message(int fd, const frameeyeosc::Message &m) {
  std::vector<uint8_t> bytes = frameeyeosc::encode(m);
  if (send(fd, bytes.data(), bytes.size(), 0) < 0) {
    std::perror("send");
  }
}

int main(int argc, char **argv) {
  std::string target = "127.0.0.1:9000";
  std::string prefix = "/FT";
  std::string source = "/dev/shm/eye-server.mmap";
  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    if (i + 1 >= argc) {
      return usage();
    }
    if (a == "--target") {
      target = argv[++i];
    } else if (a == "--prefix") {
      prefix = argv[++i];
    } else if (a == "--source") {
      source = argv[++i];
    } else {
      return usage();
    }
  }
  if (prefix.empty() || prefix[0] != '/' || prefix.find_first_not_of('/') == std::string::npos) {
    std::fprintf(stderr, "--prefix must be a nonempty OSC path starting with /\n");
    return 2;
  }
  int fd = connect_udp(target);
  if (fd < 0) {
    std::fprintf(stderr, "--target %s did not resolve to an address\n", target.c_str());
    return 1;
  }
  char err[512];
  fe_source *eyes = fe_open(source.c_str(), err, sizeof err);
  if (eyes == nullptr) {
    std::fprintf(stderr, "%s\n", err);
    return 1;
  }
  std::fprintf(stderr, "Reading %s and sending OSC to %s\n", source.c_str(), target.c_str());
  bool active = false;
  for (;;) {
    fe_sample s;
    int r = fe_next(eyes, 1000, &s, err, sizeof err);
    if (r < 0) {
      std::fprintf(stderr, "%s\n", err);
      fe_close(eyes);
      return 1;
    }
    if (r == 1 && frameeyeosc::sample_valid(s)) {
      for (const frameeyeosc::Message &m : frameeyeosc::eye_messages(s, prefix)) {
        send_message(fd, m);
      }
      active = true;
      continue;
    }
    if (!active) {
      continue;
    }
    send_message(fd, frameeyeosc::tracking_active(prefix, false));
    active = false;
  }
}
