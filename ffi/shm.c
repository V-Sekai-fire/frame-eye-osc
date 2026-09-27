// SPDX-License-Identifier: MIT
// The eye-server reader. Every libc call it makes is listed in abi/eye_server.sigs and
// checked against glibc through eye_server_api.h. The byte layout comes from
// abi/eye_server_layout.h, which is generated from FrameEyeOsc/Layout.lean.
#include "eye_server_api.h"
#include "eye_server_layout.h"

#include <errno.h>
#include <signal.h>
#include <linux/futex.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>

#include <lean/lean.h>

// The same layout, written as C structs, and checked against the Lean table.
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
  uint8_t reserved[FE_RECORD_RESERVED_SIZE];
};

struct __attribute__((packed)) fe_eye_server {
  uint32_t version;
  uint32_t initialized;
  uint8_t metadata_mutex[FE_OUTER_METADATA_MUTEX_SIZE];
  uint32_t sequence;
  uint32_t metadata_requested;
  uint8_t other_control[FE_OUTER_OTHER_CONTROL_SIZE];
  struct fe_eye_data eye_data;
};

#define FE_CHECK(t, f, F) \
  _Static_assert(offsetof(struct t, f) == F##_OFF, #t "." #f " offset disagrees with Layout.lean"); \
  _Static_assert(sizeof(((struct t *)0)->f) == F##_SIZE, #t "." #f " size disagrees with Layout.lean")
FE_CHECK(fe_eye_server, version, FE_OUTER_VERSION);
FE_CHECK(fe_eye_server, initialized, FE_OUTER_INITIALIZED);
FE_CHECK(fe_eye_server, metadata_mutex, FE_OUTER_METADATA_MUTEX);
FE_CHECK(fe_eye_server, sequence, FE_OUTER_SEQUENCE);
FE_CHECK(fe_eye_server, metadata_requested, FE_OUTER_METADATA_REQUESTED);
FE_CHECK(fe_eye_server, other_control, FE_OUTER_OTHER_CONTROL);
FE_CHECK(fe_eye_server, eye_data, FE_OUTER_EYE_DATA);
FE_CHECK(fe_eye_data, producer_state, FE_RECORD_PRODUCER_STATE);
FE_CHECK(fe_eye_data, sample_flag, FE_RECORD_SAMPLE_FLAG);
FE_CHECK(fe_eye_data, sample_time, FE_RECORD_SAMPLE_TIME);
FE_CHECK(fe_eye_data, gaze_direction, FE_RECORD_GAZE_DIRECTION);
FE_CHECK(fe_eye_data, gaze_covariance_diag, FE_RECORD_GAZE_COVARIANCE_DIAG);
FE_CHECK(fe_eye_data, fixation_point, FE_RECORD_FIXATION_POINT);
FE_CHECK(fe_eye_data, pre_fusion_gaze, FE_RECORD_PRE_FUSION_GAZE);
FE_CHECK(fe_eye_data, pre_fusion_cov_diag, FE_RECORD_PRE_FUSION_COV_DIAG);
FE_CHECK(fe_eye_data, openness, FE_RECORD_OPENNESS);
FE_CHECK(fe_eye_data, estimate_extra, FE_RECORD_ESTIMATE_EXTRA);
FE_CHECK(fe_eye_data, reserved, FE_RECORD_RESERVED);
_Static_assert(sizeof(struct fe_eye_data) == FE_RECORD_SIZE, "record size");
_Static_assert(sizeof(struct fe_eye_server) <= FE_SHM_SIZE, "record must fit the mapping");
_Static_assert(sizeof(pthread_mutex_t) <= FE_OUTER_METADATA_MUTEX_SIZE, "host mutex larger than the slot");
_Static_assert(FE_OUTER_METADATA_MUTEX_OFF % _Alignof(pthread_mutex_t) == 0, "mutex slot misaligned");

static struct fe_eye_server *g_shm = NULL;
static char g_path[256];
static ino_t g_ino;
static dev_t g_dev;

static lean_obj_res fe_err(const char *fmt, ...) __attribute__((format(printf, 1, 2)));
#include <stdarg.h>
static lean_obj_res fe_err(const char *fmt, ...) {
  char buf[512];
  va_list ap;
  va_start(ap, fmt);
  vsnprintf(buf, sizeof buf, fmt, ap);
  va_end(ap);
  return lean_io_result_mk_error(lean_mk_io_user_error(lean_mk_string(buf)));
}

static pthread_mutex_t *fe_mutex(void) { return (pthread_mutex_t *)g_shm->metadata_mutex; }

// While we hold Valve's mutex, SIGINT/SIGTERM/SIGHUP/SIGQUIT are held back, so an
// ordinary kill can only land between critical sections. A process that died holding
// the lock would leave eyetracking to recover it (EOWNERDEAD), and it may not.
static sigset_t g_saved;

static void fe_block_signals(void) {
  sigset_t s;
  sigemptyset(&s);
  sigaddset(&s, SIGINT);
  sigaddset(&s, SIGTERM);
  sigaddset(&s, SIGHUP);
  sigaddset(&s, SIGQUIT);
  pthread_sigmask(SIG_BLOCK, &s, &g_saved);
}

static void fe_unlock(void) {
  pthread_mutex_unlock(fe_mutex());
  pthread_sigmask(SIG_SETMASK, &g_saved, NULL);
}

static int fe_lock(void) {
  fe_block_signals();
  struct timespec until;
  clock_gettime(CLOCK_REALTIME, &until);
  until.tv_sec += 1;
  int rc = pthread_mutex_timedlock(fe_mutex(), &until);
  if (rc == EOWNERDEAD) {
    int c = pthread_mutex_consistent(fe_mutex());
    if (c != 0) {
      fe_unlock();
      return c;
    }
    return 0;
  }
  if (rc != 0) {
    pthread_sigmask(SIG_SETMASK, &g_saved, NULL);
  }
  return rc;
}

// open : String → IO Unit
LEAN_EXPORT lean_obj_res fe_shm_open(b_lean_obj_arg path, lean_obj_arg w) {
  (void)w;
  if (g_shm) {
    return lean_io_result_mk_ok(lean_box(0));
  }
  const char *p = lean_string_cstr(path);
  int fd = open(p, O_RDWR | O_CLOEXEC);
  if (fd < 0) {
    return fe_err("%s: %s", p, strerror(errno));
  }
  struct stat st;
  if (fstat(fd, &st) != 0) {
    int e = errno;
    close(fd);
    return fe_err("%s: fstat: %s", p, strerror(e));
  }
  if ((size_t)st.st_size < FE_SHM_SIZE) {
    close(fd);
    return fe_err("%s: %lld bytes, expected at least %d", p, (long long)st.st_size, FE_SHM_SIZE);
  }
  void *m = mmap(NULL, FE_SHM_SIZE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  int e = errno;
  close(fd);
  if (m == MAP_FAILED) {
    return fe_err("%s: mmap: %s", p, strerror(e));
  }
  struct fe_eye_server *s = m;
  uint32_t version = __atomic_load_n(&s->version, __ATOMIC_ACQUIRE);
  uint32_t init = __atomic_load_n(&s->initialized, __ATOMIC_ACQUIRE);
  if (version != FE_SHM_VERSION) {
    munmap(m, FE_SHM_SIZE);
    return fe_err("eye shared memory is version %u; this build reads version %d (Frame 0.5.0)",
                  version, FE_SHM_VERSION);
  }
  if (init != 1) {
    munmap(m, FE_SHM_SIZE);
    return fe_err("eye shared memory is not initialized yet");
  }
  g_shm = s;
  snprintf(g_path, sizeof g_path, "%s", p);
  g_ino = st.st_ino;
  g_dev = st.st_dev;
  return lean_io_result_mk_ok(lean_box(0));
}

// next : UInt32 → IO ByteArray. Empty when no new sample arrived within the timeout.
LEAN_EXPORT lean_obj_res fe_shm_next(uint32_t timeout_ms, lean_obj_arg w) {
  (void)w;
  if (!g_shm) {
    return fe_err("eye shared memory is not open");
  }
  struct stat now;
  if (stat(g_path, &now) != 0 || now.st_ino != g_ino || now.st_dev != g_dev) {
    return fe_err("eye server restarted (%s was re-created)", g_path);
  }
  int rc = fe_lock();
  if (rc != 0) {
    return fe_err("eye mutex: %s", strerror(rc));
  }
  uint32_t seq = __atomic_load_n(&g_shm->sequence, __ATOMIC_ACQUIRE);
  __atomic_store_n(&g_shm->metadata_requested, 1, __ATOMIC_RELEASE);
  fe_unlock();

  struct timespec ts = {.tv_sec = timeout_ms / 1000, .tv_nsec = (long)(timeout_ms % 1000) * 1000000L};
  long r = syscall(SYS_futex, &g_shm->sequence, FUTEX_WAIT, seq, &ts, NULL, 0);
  if (r == -1 && errno != EAGAIN && errno != EINTR && errno != ETIMEDOUT) {
    return fe_err("futex wait: %s", strerror(errno));
  }

  rc = fe_lock();
  if (rc != 0) {
    return fe_err("eye mutex: %s", strerror(rc));
  }
  lean_object *out;
  if (__atomic_load_n(&g_shm->sequence, __ATOMIC_ACQUIRE) != seq) {
    out = lean_alloc_sarray(1, FE_RECORD_SIZE, FE_RECORD_SIZE);
    memcpy(lean_sarray_cptr(out), &g_shm->eye_data, FE_RECORD_SIZE);
  } else {
    out = lean_alloc_sarray(1, 0, 0);
  }
  fe_unlock();
  return lean_io_result_mk_ok(out);
}

LEAN_EXPORT lean_obj_res fe_shm_close(lean_obj_arg w) {
  (void)w;
  if (g_shm) {
    munmap(g_shm, FE_SHM_SIZE);
  }
  g_shm = NULL;
  return lean_io_result_mk_ok(lean_box(0));
}
