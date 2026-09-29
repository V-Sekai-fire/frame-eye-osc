// SPDX-License-Identifier: MIT
#include "eye_server.h"

#include <errno.h>
#include <fcntl.h>
#include <linux/futex.h>
#include <pthread.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

struct __attribute__((packed)) fe_eye_data {
  uint32_t producer_state;
  uint8_t sample_flag;
  double sample_time;
  float gaze_direction[2][3];
  float gaze_covariance_diag[2][3];
  float fixation_point[3];
  float pre_fusion_gaze[2][3];
  float pre_fusion_cov_diag[2][3];
  float openness[2];
  float estimate_extra[8];
  uint8_t reserved[0xe1b];
};

struct __attribute__((packed)) fe_eye_server {
  uint32_t version;
  uint32_t initialized;
  uint8_t metadata_mutex[0x30];
  uint32_t sequence;
  uint32_t metadata_requested;
  uint8_t other_control[0x112];
  struct fe_eye_data eye_data;
};

_Static_assert(offsetof(struct fe_eye_server, sequence) == 0x38, "sequence offset");
_Static_assert(offsetof(struct fe_eye_server, metadata_requested) == 0x3c, "metadata_requested offset");
_Static_assert(offsetof(struct fe_eye_server, eye_data) == FE_RECORD_OFFSET, "record offset");
_Static_assert(offsetof(struct fe_eye_data, sample_time) == 0x05, "sample_time offset");
_Static_assert(offsetof(struct fe_eye_data, gaze_direction) == 0x0d, "gaze offset");
_Static_assert(offsetof(struct fe_eye_data, fixation_point) == 0x3d, "fixation offset");
_Static_assert(offsetof(struct fe_eye_data, openness) == 0x79, "openness offset");
_Static_assert(sizeof(struct fe_eye_data) == FE_RECORD_SIZE, "record size");
_Static_assert(sizeof(struct fe_eye_server) <= FE_SHM_SIZE, "record must fit the mapping");
_Static_assert(sizeof(pthread_mutex_t) <= 0x30, "host mutex larger than the slot");

struct fe_source {
  struct fe_eye_server *shm;
};

static void fe_error(char *err, size_t err_len, const char *fmt, ...) {
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(err, err_len, fmt, ap);
  va_end(ap);
}

static pthread_mutex_t *fe_mutex(fe_source *s) { return (pthread_mutex_t *)s->shm->metadata_mutex; }

static int fe_lock(fe_source *s) {
  int rc = pthread_mutex_lock(fe_mutex(s));
  if (rc != EOWNERDEAD) {
    return rc;
  }
  rc = pthread_mutex_consistent(fe_mutex(s));
  if (rc != 0) {
    pthread_mutex_unlock(fe_mutex(s));
  }
  return rc;
}

fe_source *fe_open(const char *path, char *err, size_t err_len) {
  int fd = open(path, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    fe_error(err, err_len, "%s: %s", path, strerror(errno));
    return NULL;
  }
  struct stat st;
  if (fstat(fd, &st) != 0 || (size_t)st.st_size < FE_SHM_SIZE) {
    fe_error(err, err_len, "%s: shared memory is too small", path);
    close(fd);
    return NULL;
  }
  void *m = mmap(NULL, FE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  if (m == MAP_FAILED) {
    fe_error(err, err_len, "%s: mmap: %s", path, strerror(errno));
    return NULL;
  }
  struct fe_eye_server *shm = (struct fe_eye_server *)m;
  uint32_t version = __atomic_load_n(&shm->version, __ATOMIC_ACQUIRE);
  if (version != FE_SHM_VERSION) {
    fe_error(err, err_len, "unsupported eye shared-memory version %u; expected %u", version, FE_SHM_VERSION);
    munmap(m, FE_SHM_SIZE);
    return NULL;
  }
  if (__atomic_load_n(&shm->initialized, __ATOMIC_ACQUIRE) != 1) {
    fe_error(err, err_len, "eye shared memory is not initialized");
    munmap(m, FE_SHM_SIZE);
    return NULL;
  }
  fe_source *s = (fe_source *)malloc(sizeof *s);
  s->shm = shm;
  return s;
}

void fe_decode(const uint8_t *record, fe_sample *out) {
  struct fe_eye_data d;
  memcpy(&d, record, sizeof d);
  out->producer_state = d.producer_state;
  out->sample_time = d.sample_time;
  memcpy(out->gaze, d.gaze_direction, sizeof out->gaze);
  memcpy(out->fixation_point, d.fixation_point, sizeof out->fixation_point);
  memcpy(out->openness, d.openness, sizeof out->openness);
}

int fe_next(fe_source *s, int timeout_ms, fe_sample *out, char *err, size_t err_len) {
  int rc = fe_lock(s);
  if (rc != 0) {
    fe_error(err, err_len, "eye mutex: %s", strerror(rc));
    return -1;
  }
  uint32_t seq = __atomic_load_n(&s->shm->sequence, __ATOMIC_ACQUIRE);
  __atomic_store_n(&s->shm->metadata_requested, 1, __ATOMIC_RELEASE);
  pthread_mutex_unlock(fe_mutex(s));

  struct timespec ts = {.tv_sec = timeout_ms / 1000, .tv_nsec = (long)(timeout_ms % 1000) * 1000000L};
  long r = syscall(SYS_futex, &s->shm->sequence, FUTEX_WAIT, seq, &ts, NULL, 0);
  if (r == -1 && errno != EAGAIN && errno != EINTR && errno != ETIMEDOUT) {
    fe_error(err, err_len, "futex wait: %s", strerror(errno));
    return -1;
  }

  rc = fe_lock(s);
  if (rc != 0) {
    fe_error(err, err_len, "eye mutex: %s", strerror(rc));
    return -1;
  }
  if (__atomic_load_n(&s->shm->sequence, __ATOMIC_ACQUIRE) == seq) {
    pthread_mutex_unlock(fe_mutex(s));
    return 0;
  }
  fe_decode((const uint8_t *)&s->shm->eye_data, out);
  pthread_mutex_unlock(fe_mutex(s));
  return 1;
}

void fe_close(fe_source *s) {
  if (!s) {
    return;
  }
  munmap(s->shm, FE_SHM_SIZE);
  free(s);
}
