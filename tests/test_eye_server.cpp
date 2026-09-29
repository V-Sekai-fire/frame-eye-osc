// SPDX-License-Identifier: MIT
#include "eye_server.h"

#include <doctest/doctest.h>

#include <fcntl.h>
#include <sys/mman.h>
#include <unistd.h>

#include <chrono>
#include <cstring>
#include <thread>
#include <string>
#include <vector>

static void put(std::vector<uint8_t> &b, size_t off, const void *v, size_t n) { std::memcpy(b.data() + off, v, n); }

TEST_CASE("a record decodes at the reference offsets") {
  std::vector<uint8_t> r(FE_RECORD_SIZE, 0);
  const uint32_t state = 1;
  const double t = 12.5;
  const float gaze[6] = {0.1f, 0.2f, -1.0f, -0.1f, 0.2f, -1.0f};
  const float fix[3] = {0.0f, 0.0f, -2.0f};
  const float open[2] = {0.25f, 0.75f};
  put(r, 0x00, &state, 4);
  put(r, 0x05, &t, 8);
  put(r, 0x0d, gaze, sizeof gaze);
  put(r, 0x3d, fix, sizeof fix);
  put(r, 0x79, open, sizeof open);
  fe_sample s;
  fe_decode(r.data(), &s);
  CHECK(s.producer_state == 1);
  CHECK(s.sample_time == 12.5);
  CHECK(s.gaze[1][0] == -0.1f);
  CHECK(s.fixation_point[2] == -2.0f);
  CHECK(s.openness[0] == 0.25f);
  CHECK(s.openness[1] == 0.75f);
}

static std::string shm_file(uint32_t version, uint32_t initialized) {
  std::string path = "/dev/shm/frameeyeosc-test-" + std::to_string(getpid());
  int fd = open(path.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0600);
  REQUIRE(fd >= 0);
  REQUIRE(ftruncate(fd, FE_SHM_SIZE) == 0);
  const uint32_t head[2] = {version, initialized};
  REQUIRE(pwrite(fd, head, sizeof head, 0) == static_cast<ssize_t>(sizeof head));
  close(fd);
  return path;
}

TEST_CASE("a new record is read once, then the source times out") {
  std::string path = shm_file(FE_SHM_VERSION, 1);
  char err[256];
  fe_source *src = fe_open(path.c_str(), err, sizeof err);
  REQUIRE(src != nullptr);
  int fd = open(path.c_str(), O_RDWR);
  uint8_t *m = static_cast<uint8_t *>(mmap(nullptr, FE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0));
  close(fd);
  std::thread producer([m]() {
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    const float open_[2] = {0.1f, 0.9f};
    std::memcpy(m + FE_RECORD_OFFSET + 0x79, open_, sizeof open_);
    __atomic_store_n(reinterpret_cast<uint32_t *>(m + 0x38), 1u, __ATOMIC_RELEASE);
  });
  fe_sample s;
  CHECK(fe_next(src, 1000, &s, err, sizeof err) == 1);
  producer.join();
  CHECK(s.openness[0] == 0.1f);
  CHECK(s.openness[1] == 0.9f);
  CHECK(fe_next(src, 20, &s, err, sizeof err) == 0);
  munmap(m, FE_SHM_SIZE);
  fe_close(src);
  unlink(path.c_str());
}

TEST_CASE("a wrong version is refused (control)") {
  std::string path = shm_file(3, 1);
  char err[256];
  CHECK(fe_open(path.c_str(), err, sizeof err) == nullptr);
  CHECK(std::string(err).find("version 3") != std::string::npos);
  unlink(path.c_str());
}
