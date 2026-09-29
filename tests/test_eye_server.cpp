// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 konsti219
// SPDX-License-Identifier: MIT
#include "abi.h"

#include "check.hpp"

#include <fcntl.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <chrono>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

static void put(std::vector<uint8_t> &r_bytes, size_t p_offset, const void *p_value, size_t p_size) {
  std::memcpy(r_bytes.data() + p_offset, p_value, p_size);
}

TEST(record_decodes_at_reference_offsets) {
  std::vector<uint8_t> r(FE_RECORD_SIZE, 0);
  const uint32_t state = 1;
  const double t = 12.5;
  const float gaze[6] = {0.1f, 0.2f, -1.0f, -0.1f, 0.2f, -1.0f};
  const float cov[6] = {0.01f, 0.02f, 0.03f, 0.04f, 0.05f, 0.06f};
  const float fix[3] = {0.0f, 0.0f, -2.0f};
  const float open[2] = {0.25f, 0.75f};
  put(r, 0x00, &state, 4);
  put(r, 0x05, &t, 8);
  put(r, 0x0d, gaze, sizeof gaze);
  put(r, 0x25, cov, sizeof cov);
  put(r, 0x3d, fix, sizeof fix);
  put(r, 0x79, open, sizeof open);
  fe_sample s = fe_decode(r.data());
  CHECK(s.producer_state == 1);
  CHECK(s.sample_time == 12.5);
  CHECK(s.gaze[1].x == -0.1f);
  CHECK(s.gaze_covariance[1].z == 0.06f);
  CHECK(s.fixation_point.z == -2.0f);
  CHECK(s.openness[0] == 0.25f);
  CHECK(s.openness[1] == 0.75f);
}

// A mapping laid out like the eye server's, with a process-shared robust mutex.
static std::string shm_file(uint32_t p_version, uint32_t p_initialized) {
  std::string path = "/dev/shm/frameeyeosc-test-" + std::to_string(getpid());
  int fd = open(path.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0600);
  if (fd < 0 || ftruncate(fd, FE_SHM_SIZE) != 0) {
    return "";
  }
  uint8_t *m = (uint8_t *)mmap(nullptr, FE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  const uint32_t head[2] = {p_version, p_initialized};
  std::memcpy(m, head, sizeof head);
  pthread_mutexattr_t attr;
  pthread_mutexattr_init(&attr);
  pthread_mutexattr_setpshared(&attr, PTHREAD_PROCESS_SHARED);
  pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST);
  pthread_mutex_init((pthread_mutex_t *)(m + 0x08), &attr);
  munmap(m, FE_SHM_SIZE);
  return path;
}

TEST(new_record_is_read_once_then_times_out) {
  std::string path = shm_file(FE_SHM_VERSION, 1);
  REQUIRE(!path.empty());
  fe_text p = fe_text_of(path.c_str());
  fe_text err;
  fe_source src;
  REQUIRE(fe_eye_open(&p, &src, &err));
  int fd = open(path.c_str(), O_RDWR);
  uint8_t *m = (uint8_t *)mmap(nullptr, FE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  std::thread producer([m]() {
    std::this_thread::sleep_for(std::chrono::milliseconds(20));
    pthread_mutex_lock((pthread_mutex_t *)(m + 0x08));
    const float open_[2] = {0.1f, 0.9f};
    std::memcpy(m + FE_RECORD_OFFSET + 0x79, open_, sizeof open_);
    const uint32_t seq = 1;
    std::memcpy(m + 0x38, &seq, sizeof seq);
    pthread_mutex_unlock((pthread_mutex_t *)(m + 0x08));
  });
  fe_sample s;
  CHECK(fe_eye_next(&src, 1000, &s, &err) == 1);
  producer.join();
  CHECK(s.openness[0] == 0.1f);
  CHECK(s.openness[1] == 0.9f);
  CHECK(fe_eye_next(&src, 20, &s, &err) == 0);
  munmap(m, FE_SHM_SIZE);
  fe_eye_close(&src);
  unlink(path.c_str());
}

TEST(control_wrong_version_is_refused) {
  std::string path = shm_file(3, 1);
  REQUIRE(!path.empty());
  fe_text p = fe_text_of(path.c_str());
  fe_text err;
  fe_source src;
  CHECK(!fe_eye_open(&p, &src, &err));
  CHECK(std::string((const char *)err.bytes, (size_t)err.size).find("version 3") != std::string::npos);
  unlink(path.c_str());
}
