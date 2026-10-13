// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Lean bindings for the functions core.slang exports. A struct crosses as a FloatArray of
// its fields in declaration order; OSC messages and plan entries cross as their raw bytes.
#include "abi.h"

#include <lean/lean.h>

#include <fcntl.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cstring>

namespace {

void read_floats(b_lean_obj_arg p_array, float *r_out, size_t p_count) {
  const double *values = lean_float_array_cptr(p_array);
  size_t n = lean_sarray_size(p_array);
  for (size_t k = 0; k < p_count; ++k) {
    r_out[k] = k < n ? (float)values[k] : 0.0f;
  }
}

lean_obj_res float_array(const float *p_values, size_t p_count) {
  lean_object *out = lean_alloc_sarray(sizeof(double), p_count, p_count);
  double *values = lean_float_array_cptr(out);
  for (size_t k = 0; k < p_count; ++k) {
    values[k] = (double)p_values[k];
  }
  return out;
}

lean_obj_res empty_floats() { return lean_alloc_sarray(sizeof(double), 0, 0); }

template <class T> T read_struct(b_lean_obj_arg p_array) {
  T value;
  std::memset(&value, 0, sizeof value);
  read_floats(p_array, (float *)&value, sizeof(T) / sizeof(float));
  return value;
}

template <class T> lean_obj_res struct_array(const T &p_value) {
  return float_array((const float *)&p_value, sizeof(T) / sizeof(float));
}

// fe_eye_state leads with an int32 phase; the FloatArray carries it as a number.
fe_eye_state read_state(b_lean_obj_arg p_array) {
  float f[4];
  read_floats(p_array, f, 4);
  return fe_eye_state{(int32_t)f[0], f[1], f[2], f[3]};
}

fe_style_state read_style(b_lean_obj_arg p_array) {
  float f[8];
  read_floats(p_array, f, 8);
  return fe_style_state{fe_eye_state{(int32_t)f[0], f[1], f[2], f[3]}, fe_eye_state{(int32_t)f[4], f[5], f[6], f[7]}};
}

template <class T> T read_bytes(b_lean_obj_arg p_bytes) {
  T value;
  std::memset(&value, 0, sizeof value);
  size_t n = lean_sarray_size(p_bytes);
  std::memcpy(&value, lean_sarray_cptr(p_bytes), n < sizeof value ? n : sizeof value);
  return value;
}

template <class T> lean_obj_res byte_array(const T &p_value) {
  lean_object *out = lean_alloc_sarray(1, sizeof(T), sizeof(T));
  std::memcpy(lean_sarray_cptr(out), &p_value, sizeof(T));
  return out;
}

lean_obj_res bytes_of(const uint8_t *p_bytes, size_t p_size) {
  lean_object *out = lean_alloc_sarray(1, p_size, p_size);
  std::memcpy(lean_sarray_cptr(out), p_bytes, p_size);
  return out;
}

fe_text text_of(b_lean_obj_arg p_string) { return fe_text_of(lean_string_cstr(p_string)); }

lean_obj_res string_of(const fe_text &p_text) {
  return lean_mk_string_from_bytes((const char *)p_text.bytes, (size_t)p_text.size);
}

// A sample as [producer_state, time, gaze L xyz, gaze R xyz, cov L xyz, cov R xyz, fixation xyz, open L, open R].
fe_sample read_sample(b_lean_obj_arg p_array) {
  float f[19];
  read_floats(p_array, f, 19);
  fe_sample s;
  std::memset(&s, 0, sizeof s);
  s.producer_state = (uint32_t)f[0];
  s.sample_time = lean_sarray_size(p_array) > 1 ? lean_float_array_cptr(p_array)[1] : 0.0;
  s.gaze[0] = fe_vec3{f[2], f[3], f[4]};
  s.gaze[1] = fe_vec3{f[5], f[6], f[7]};
  s.gaze_covariance[0] = fe_vec3{f[8], f[9], f[10]};
  s.gaze_covariance[1] = fe_vec3{f[11], f[12], f[13]};
  s.fixation_point = fe_vec3{f[14], f[15], f[16]};
  s.openness[0] = f[17];
  s.openness[1] = f[18];
  return s;
}

lean_obj_res sample_array(const fe_sample &p_s) {
  const float rest[17] = {p_s.gaze[0].x, p_s.gaze[0].y, p_s.gaze[0].z, p_s.gaze[1].x, p_s.gaze[1].y, p_s.gaze[1].z,
                          p_s.gaze_covariance[0].x, p_s.gaze_covariance[0].y, p_s.gaze_covariance[0].z,
                          p_s.gaze_covariance[1].x, p_s.gaze_covariance[1].y, p_s.gaze_covariance[1].z,
                          p_s.fixation_point.x, p_s.fixation_point.y, p_s.fixation_point.z, p_s.openness[0],
                          p_s.openness[1]};
  lean_object *out = lean_alloc_sarray(sizeof(double), 19, 19);
  double *v = lean_float_array_cptr(out);
  v[0] = (double)p_s.producer_state;
  v[1] = p_s.sample_time;
  for (int k = 0; k < 17; ++k) {
    v[k + 2] = (double)rest[k];
  }
  return out;
}

lean_obj_res entries_of(const fe_entry *p_entries, int32_t p_count) {
  lean_object *out = lean_mk_empty_array();
  for (int32_t k = 0; k < p_count; ++k) {
    out = lean_array_push(out, byte_array(p_entries[k]));
  }
  return out;
}

} // namespace

extern "C" {

// ── Kernels ──────────────────────────────────────────────────────────────────

LEAN_EXPORT double fe_lean_clamp01(double p_v) { return fe_clamp01((float)p_v); }

LEAN_EXPORT lean_obj_res fe_lean_calib_normalized(b_lean_obj_arg p_calib) {
  fe_calib c = read_struct<fe_calib>(p_calib);
  return struct_array(fe_calib_normalized(&c));
}

LEAN_EXPORT lean_obj_res fe_lean_calib_step(b_lean_obj_arg p_calib, double p_openness) {
  fe_calib c = read_struct<fe_calib>(p_calib);
  return struct_array(fe_calib_step(&c, (float)p_openness));
}

LEAN_EXPORT double fe_lean_blink_of(b_lean_obj_arg p_calib, double p_openness) {
  fe_calib c = read_struct<fe_calib>(p_calib);
  return fe_blink_of(&c, (float)p_openness);
}

LEAN_EXPORT double fe_lean_wide_of(b_lean_obj_arg p_calib, double p_openness) {
  fe_calib c = read_struct<fe_calib>(p_calib);
  return fe_wide_of(&c, (float)p_openness);
}

LEAN_EXPORT lean_obj_res fe_lean_eye(uint8_t p_side, b_lean_obj_arg p_gains, uint8_t p_heuristics,
                                     b_lean_obj_arg p_calib, b_lean_obj_arg p_in) {
  fe_gains g = read_struct<fe_gains>(p_gains);
  fe_calib c = read_struct<fe_calib>(p_calib);
  fe_eye_in e = read_struct<fe_eye_in>(p_in);
  return struct_array(fe_eye(p_side, &g, p_heuristics != 0, &c, &e));
}

LEAN_EXPORT lean_obj_res fe_lean_frame(b_lean_obj_arg p_gains, uint8_t p_heuristics, b_lean_obj_arg p_calib,
                                       b_lean_obj_arg p_in) {
  fe_gains g = read_struct<fe_gains>(p_gains);
  fe_frame_calib c = read_struct<fe_frame_calib>(p_calib);
  fe_frame_in f = read_struct<fe_frame_in>(p_in);
  return struct_array(fe_frame(&g, p_heuristics != 0, &c, &f));
}

LEAN_EXPORT lean_obj_res fe_lean_parallel(b_lean_obj_arg p_in) {
  fe_frame_in f = read_struct<fe_frame_in>(p_in);
  return struct_array(fe_parallel(&f));
}

LEAN_EXPORT lean_obj_res fe_lean_mirror(b_lean_obj_arg p_in) {
  fe_frame_in f = read_struct<fe_frame_in>(p_in);
  return struct_array(fe_mirror(&f));
}

LEAN_EXPORT double fe_lean_level(b_lean_obj_arg p_tuning, b_lean_obj_arg p_state) {
  fe_tuning k = read_struct<fe_tuning>(p_tuning);
  fe_eye_state s = read_state(p_state);
  return fe_level(&k, &s);
}

LEAN_EXPORT lean_obj_res fe_lean_style_step(b_lean_obj_arg p_tuning, double p_dt_ms, b_lean_obj_arg p_state,
                                            double p_rel_left, double p_rel_right) {
  fe_tuning k = read_struct<fe_tuning>(p_tuning);
  fe_style_state s = read_style(p_state);
  fe_style_state n = fe_style_step(&k, (float)p_dt_ms, &s, (float)p_rel_left, (float)p_rel_right);
  const float f[8] = {(float)n.left.phase,  n.left.t_ms,  n.left.from,  n.left.partial_ms,
                      (float)n.right.phase, n.right.t_ms, n.right.from, n.right.partial_ms};
  return float_array(f, 8);
}

LEAN_EXPORT lean_obj_res fe_lean_style_eye(b_lean_obj_arg p_tuning, b_lean_obj_arg p_gains, uint8_t p_heuristics,
                                           b_lean_obj_arg p_calib, double p_raw, b_lean_obj_arg p_state,
                                           b_lean_obj_arg p_base) {
  fe_tuning k = read_struct<fe_tuning>(p_tuning);
  fe_gains g = read_struct<fe_gains>(p_gains);
  fe_calib c = read_struct<fe_calib>(p_calib);
  fe_eye_state s = read_state(p_state);
  fe_eye_out base = read_struct<fe_eye_out>(p_base);
  return struct_array(fe_style_eye(&k, &g, p_heuristics != 0, &c, (float)p_raw, &s, &base));
}

LEAN_EXPORT lean_obj_res fe_lean_wink_gate(uint8_t p_lost_left, uint8_t p_lost_right, double p_rel_left,
                                           double p_rel_right) {
  float l = (float)p_rel_left;
  float r = (float)p_rel_right;
  fe_wink_gate(p_lost_left != 0, p_lost_right != 0, &l, &r);
  const float f[2] = {l, r};
  return float_array(f, 2);
}

LEAN_EXPORT uint8_t fe_lean_eye_lost(b_lean_obj_arg p_covariance, double p_threshold) {
  fe_vec3 c = read_struct<fe_vec3>(p_covariance);
  return fe_eye_lost(&c, (float)p_threshold) ? 1 : 0;
}

LEAN_EXPORT double fe_lean_expressive(double p_gain, double p_limit, double p_dead, double p_degrees) {
  return fe_expressive((float)p_gain, (float)p_limit, (float)p_dead, (float)p_degrees);
}

LEAN_EXPORT lean_obj_res fe_lean_one_euro_step(b_lean_obj_arg p_filter, double p_value, double p_dt_s) {
  float f[3];
  read_floats(p_filter, f, 3);
  fe_one_euro in = {f[0], f[1], f[2] != 0.0f};
  fe_one_euro out = fe_one_euro_step(&in, (float)p_value, (float)p_dt_s);
  const float g[3] = {out.x, out.dx, out.primed ? 1.0f : 0.0f};
  return float_array(g, 3);
}

LEAN_EXPORT lean_obj_res fe_lean_pitch_yaw(b_lean_obj_arg p_direction) {
  fe_vec3 d = read_struct<fe_vec3>(p_direction);
  float f[2] = {0.0f, 0.0f};
  fe_pitch_yaw_degrees(&d, &f[0], &f[1]);
  return float_array(f, 2);
}

LEAN_EXPORT lean_obj_res fe_lean_gaze_angles(b_lean_obj_arg p_direction) {
  fe_vec3 d = read_struct<fe_vec3>(p_direction);
  float f[2] = {0.0f, 0.0f};
  fe_gaze_angles(&d, &f[0], &f[1]);
  return float_array(f, 2);
}

LEAN_EXPORT uint32_t fe_lean_quantize(uint32_t p_width, double p_value) {
  return (uint32_t)fe_quantize((int32_t)p_width, (float)p_value);
}

// ── Reference output and the shared-memory record ────────────────────────────

LEAN_EXPORT uint8_t fe_lean_sample_valid(b_lean_obj_arg p_sample) {
  fe_sample s = read_sample(p_sample);
  return fe_sample_valid(&s) ? 1 : 0;
}

LEAN_EXPORT lean_obj_res fe_lean_reference_messages(b_lean_obj_arg p_sample, b_lean_obj_arg p_prefix) {
  static fe_message messages[FE_REFERENCE_MESSAGES];
  fe_sample s = read_sample(p_sample);
  fe_text prefix = text_of(p_prefix);
  fe_reference_messages(&s, &prefix, messages);
  lean_object *out = lean_mk_empty_array();
  for (int k = 0; k < FE_REFERENCE_MESSAGES; ++k) {
    out = lean_array_push(out, byte_array(messages[k]));
  }
  return out;
}

// The decoded sample, or an empty array when the record is short.
LEAN_EXPORT lean_obj_res fe_lean_decode(b_lean_obj_arg p_record) {
  if (lean_sarray_size(p_record) < (size_t)FE_RECORD_SIZE) {
    return empty_floats();
  }
  return sample_array(fe_decode(lean_sarray_cptr(p_record)));
}

// A mapping laid out like the eye server's, with a process-shared robust mutex. Versions other
// than 5 get version 4's size, so a refused version is refused by its number, not its size.
LEAN_EXPORT lean_obj_res fe_lean_shm_create(b_lean_obj_arg p_path, uint32_t p_version, lean_obj_arg) {
  const int size = fe_shm_size(p_version);
  int fd = open(lean_string_cstr(p_path), O_RDWR | O_CREAT | O_TRUNC, 0600);
  if (fd < 0 || ftruncate(fd, size) != 0) {
    return lean_io_result_mk_ok(lean_box(0));
  }
  uint8_t *m = (uint8_t *)mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  const uint32_t head[2] = {p_version, 1};
  std::memcpy(m, head, sizeof head);
  pthread_mutexattr_t attr;
  pthread_mutexattr_init(&attr);
  pthread_mutexattr_setpshared(&attr, PTHREAD_PROCESS_SHARED);
  pthread_mutexattr_setrobust(&attr, PTHREAD_MUTEX_ROBUST);
  pthread_mutex_init((pthread_mutex_t *)(m + 0x08), &attr);
  munmap(m, size);
  return lean_io_result_mk_ok(lean_box(1));
}

namespace {

// The fake server's mapping, at the size its own version says.
uint8_t *shm_map(const char *p_path, int &r_size, uint32_t &r_version) {
  int fd = open(p_path, O_RDWR);
  if (fd < 0) {
    return nullptr;
  }
  uint32_t version = 0;
  if (pread(fd, &version, sizeof version, 0) != (ssize_t)sizeof version) {
    close(fd);
    return nullptr;
  }
  r_version = version;
  r_size = fe_shm_size(version);
  uint8_t *m = (uint8_t *)mmap(nullptr, r_size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  return m == MAP_FAILED ? nullptr : m;
}

// Writes both openness values and bumps the sequence, under the mutex, as the server does. The
// server also clears the request with each sample it publishes.
bool shm_publish(const char *p_path, float p_left, float p_right) {
  int size = 0;
  uint32_t version = 0;
  uint8_t *m = shm_map(p_path, size, version);
  if (m == nullptr) {
    return false;
  }
  pthread_mutex_lock((pthread_mutex_t *)(m + 0x08));
  const uint32_t producing = 1;
  std::memcpy(m + fe_record_offset(version), &producing, sizeof producing);
  const float open_[2] = {p_left, p_right};
  std::memcpy(m + fe_record_offset(version) + 0x79, open_, sizeof open_);
  uint32_t seq = 0;
  std::memcpy(&seq, m + 0x38, sizeof seq);
  seq += 1;
  std::memcpy(m + 0x38, &seq, sizeof seq);
  const uint32_t cleared = 0;
  std::memcpy(m + 0x3c, &cleared, sizeof cleared);
  pthread_mutex_unlock((pthread_mutex_t *)(m + 0x08));
  munmap(m, size);
  return true;
}

uint32_t shm_requested(const char *p_path) {
  int size = 0;
  uint32_t version = 0;
  uint8_t *m = shm_map(p_path, size, version);
  if (m == nullptr) {
    return 0;
  }
  uint32_t requested = 0;
  std::memcpy(&requested, m + 0x3c, sizeof requested);
  munmap(m, size);
  return requested;
}

} // namespace

LEAN_EXPORT lean_obj_res fe_lean_shm_publish(b_lean_obj_arg p_path, double p_left, double p_right, lean_obj_arg) {
  return lean_io_result_mk_ok(lean_box(shm_publish(lean_string_cstr(p_path), (float)p_left, (float)p_right) ? 1 : 0));
}

// Writes version 5's 5-byte "Track Dominant Eye Only" setting: a flag, then the eye as an int32.
LEAN_EXPORT lean_obj_res fe_lean_shm_set_dominant(b_lean_obj_arg p_path, uint8_t p_flag, int32_t p_eye, lean_obj_arg) {
  int size = 0;
  uint32_t version = 0;
  uint8_t *m = shm_map(lean_string_cstr(p_path), size, version);
  if (m == nullptr) {
    return lean_io_result_mk_ok(lean_box(0));
  }
  m[0x152] = p_flag;
  std::memcpy(m + 0x153, &p_eye, sizeof p_eye);
  munmap(m, size);
  return lean_io_result_mk_ok(lean_box(1));
}

// Opens, waits once for a record, closes: [status, open L, open R]. A refused open is an IO error.
LEAN_EXPORT lean_obj_res fe_lean_eye_read_once(b_lean_obj_arg p_path, uint32_t p_timeout_ms, lean_obj_arg) {
  fe_text path = text_of(p_path);
  fe_text err;
  fe_source src;
  if (!fe_eye_open(&path, &src, &err)) {
    return lean_io_result_mk_error(lean_mk_io_user_error(string_of(err)));
  }
  fe_sample s;
  std::memset(&s, 0, sizeof s);
  int32_t r = fe_eye_next(&src, (int32_t)p_timeout_ms, &s, &err);
  fe_eye_close(&src);
  const float f[3] = {(float)r, s.openness[0], s.openness[1]};
  return lean_io_result_mk_ok(float_array(f, 3));
}

// One open source read twice, the way the daemon reads it. A server thread publishes the first
// sample 20 ms in; right after the first read returns, a second sample is published (as if it
// arrived while the first was being processed), and the second read may not wait at all.
// [first status, request flag left by the first read, second status, open L of the second,
//  samples missed, dominant eye].
LEAN_EXPORT lean_obj_res fe_lean_eye_read_busy(b_lean_obj_arg p_path, lean_obj_arg) {
  const char *path_c = lean_string_cstr(p_path);
  fe_text path = text_of(p_path);
  fe_text err;
  fe_source src;
  if (!fe_eye_open(&path, &src, &err)) {
    return lean_io_result_mk_error(lean_mk_io_user_error(string_of(err)));
  }
  pthread_t server;
  pthread_create(
      &server, nullptr,
      [](void *p) -> void * {
        usleep(20000);
        shm_publish((const char *)p, 0.2f, 0.3f);
        return nullptr;
      },
      (void *)path_c);
  fe_sample s;
  std::memset(&s, 0, sizeof s);
  int32_t first = fe_eye_next(&src, 1000, &s, &err);
  pthread_join(server, nullptr);
  const uint32_t requested = shm_requested(path_c);
  shm_publish(path_c, 0.6f, 0.7f);
  int32_t second = fe_eye_next(&src, 0, &s, &err);
  const int32_t dominant = fe_eye_dominant(&src);
  const float missed = (float)src.missed;
  fe_eye_close(&src);
  const float f[6] = {(float)first, (float)requested, (float)second, s.openness[0], missed, (float)dominant};
  return lean_io_result_mk_ok(float_array(f, 6));
}

// -2 for a setting that can't be trusted, -1 off, 0 left, 1 right.
LEAN_EXPORT int32_t fe_lean_dominant_eye(b_lean_obj_arg p_bytes) {
  if (lean_sarray_size(p_bytes) < 5) {
    return -2;
  }
  return fe_dominant_eye(lean_sarray_cptr(p_bytes));
}

// ── OSC ──────────────────────────────────────────────────────────────────────

LEAN_EXPORT lean_obj_res fe_lean_message(b_lean_obj_arg p_address) {
  return byte_array(fe_message_of(lean_string_cstr(p_address)));
}

LEAN_EXPORT lean_obj_res fe_lean_add_float(b_lean_obj_arg p_message, double p_value) {
  fe_message m = read_bytes<fe_message>(p_message);
  if (m.argc < 6) {
    fe_add_float(m, (float)p_value);
  }
  return byte_array(m);
}

LEAN_EXPORT lean_obj_res fe_lean_add_int(b_lean_obj_arg p_message, uint32_t p_value) {
  fe_message m = read_bytes<fe_message>(p_message);
  if (m.argc < 6) {
    fe_add_int(m, (int32_t)p_value);
  }
  return byte_array(m);
}

LEAN_EXPORT lean_obj_res fe_lean_add_bool(b_lean_obj_arg p_message, uint8_t p_value) {
  fe_message m = read_bytes<fe_message>(p_message);
  if (m.argc < 6) {
    fe_add_bool(m, p_value != 0);
  }
  return byte_array(m);
}

LEAN_EXPORT lean_obj_res fe_lean_add_string(b_lean_obj_arg p_message, b_lean_obj_arg p_value) {
  fe_message m = read_bytes<fe_message>(p_message);
  if (m.argc < 6) {
    fe_add_string(m, lean_string_cstr(p_value));
  }
  return byte_array(m);
}

LEAN_EXPORT lean_obj_res fe_lean_message_address(b_lean_obj_arg p_message) {
  return string_of(read_bytes<fe_message>(p_message).address);
}

LEAN_EXPORT uint8_t fe_lean_message_tag(b_lean_obj_arg p_message, uint32_t p_index) {
  fe_message m = read_bytes<fe_message>(p_message);
  return p_index < (uint32_t)m.argc ? m.args[p_index].tag : 0;
}

LEAN_EXPORT double fe_lean_message_float(b_lean_obj_arg p_message, uint32_t p_index) {
  fe_message m = read_bytes<fe_message>(p_message);
  return p_index < (uint32_t)m.argc ? m.args[p_index].f : 0.0;
}

// Wire bytes into a buffer of p_cap bytes; empty when they do not fit.
LEAN_EXPORT lean_obj_res fe_lean_encode(b_lean_obj_arg p_message, uint32_t p_cap) {
  static uint8_t buf[65536];
  fe_message m = read_bytes<fe_message>(p_message);
  int32_t n = fe_osc_encode(&m, buf, (int32_t)(p_cap < sizeof buf ? p_cap : sizeof buf));
  return bytes_of(buf, n > 0 ? (size_t)n : 0);
}

// The message's raw bytes, or an empty array when the bytes do not decode.
LEAN_EXPORT lean_obj_res fe_lean_decode_message(b_lean_obj_arg p_bytes) {
  static fe_message m;
  if (!fe_osc_decode(lean_sarray_cptr(p_bytes), (int32_t)lean_sarray_size(p_bytes), &m)) {
    return lean_alloc_sarray(1, 0, 0);
  }
  return byte_array(m);
}

LEAN_EXPORT uint8_t fe_lean_message_equal(b_lean_obj_arg p_a, b_lean_obj_arg p_b) {
  fe_message a = read_bytes<fe_message>(p_a);
  fe_message b = read_bytes<fe_message>(p_b);
  return fe_osc_equal(&a, &b) ? 1 : 0;
}

LEAN_EXPORT lean_obj_res fe_lean_bundle(b_lean_obj_arg p_messages) {
  static fe_message ms[256];
  static uint8_t buf[65536];
  size_t count = lean_array_size(p_messages);
  count = count < 256 ? count : 256;
  for (size_t k = 0; k < count; ++k) {
    ms[k] = read_bytes<fe_message>(lean_array_get_core(p_messages, k));
  }
  int32_t n = fe_osc_bundle(ms, (int32_t)count, buf, (int32_t)sizeof buf);
  return bytes_of(buf, n > 0 ? (size_t)n : 0);
}

LEAN_EXPORT lean_obj_res fe_lean_decode_packet(b_lean_obj_arg p_bytes) {
  static fe_message got[256];
  int32_t n = fe_osc_decode_packet(lean_sarray_cptr(p_bytes), (int32_t)lean_sarray_size(p_bytes), got, 256);
  lean_object *out = lean_mk_empty_array();
  for (int32_t k = 0; k < n; ++k) {
    out = lean_array_push(out, byte_array(got[k]));
  }
  return out;
}

// ── Parameters ───────────────────────────────────────────────────────────────

// p_types holds one byte per address: 'f', 'i' or 'T'.
LEAN_EXPORT lean_obj_res fe_lean_plan(b_lean_obj_arg p_addresses, b_lean_obj_arg p_types) {
  static fe_avatar_param avatar[512];
  static fe_entry entries[512];
  size_t count = lean_array_size(p_addresses);
  count = count < 512 ? count : 512;
  for (size_t k = 0; k < count; ++k) {
    avatar[k].address = text_of(lean_array_get_core(p_addresses, k));
    avatar[k].type = k < lean_sarray_size(p_types) ? lean_sarray_cptr(p_types)[k] : 'f';
  }
  return entries_of(entries, fe_plan(avatar, (int32_t)count, entries, 512));
}

LEAN_EXPORT lean_obj_res fe_lean_fallback_plan(b_lean_obj_arg p_prefix) {
  static fe_entry entries[512];
  fe_text prefix = text_of(p_prefix);
  return entries_of(entries, fe_fallback_plan(&prefix, entries, 512));
}

LEAN_EXPORT uint32_t fe_lean_v2_count(lean_obj_arg) { return (uint32_t)fe_v2_count(); }

LEAN_EXPORT lean_obj_res fe_lean_entry_address(b_lean_obj_arg p_entry) {
  return string_of(read_bytes<fe_entry>(p_entry).address);
}

LEAN_EXPORT uint32_t fe_lean_entry_width(b_lean_obj_arg p_entry) { return (uint32_t)read_bytes<fe_entry>(p_entry).width; }

LEAN_EXPORT uint32_t fe_lean_entry_bit(b_lean_obj_arg p_entry) { return (uint32_t)read_bytes<fe_entry>(p_entry).bit; }

LEAN_EXPORT lean_obj_res fe_lean_message_for(b_lean_obj_arg p_entry, b_lean_obj_arg p_out) {
  fe_entry e = read_bytes<fe_entry>(p_entry);
  fe_frame_out o = read_struct<fe_frame_out>(p_out);
  return byte_array(fe_message_for(&e, &o));
}

// Folds the messages into a fresh learned state: (avatar, plan of what was learned).
LEAN_EXPORT lean_obj_res fe_lean_learn(b_lean_obj_arg p_messages) {
  static fe_learned st;
  static fe_entry entries[512];
  fe_learned_clear(&st);
  for (size_t k = 0; k < lean_array_size(p_messages); ++k) {
    fe_message m = read_bytes<fe_message>(lean_array_get_core(p_messages, k));
    fe_observe(&st, &m);
  }
  lean_object *pair = lean_alloc_ctor(0, 2, 0);
  lean_ctor_set(pair, 0, string_of(st.avatar));
  lean_ctor_set(pair, 1, entries_of(entries, fe_plan(st.params, st.count, entries, 512)));
  return pair;
}

// How many parameters are learned after each message, in order.
LEAN_EXPORT lean_obj_res fe_lean_learned_counts(b_lean_obj_arg p_messages) {
  static fe_learned st;
  fe_learned_clear(&st);
  size_t n = lean_array_size(p_messages);
  lean_object *out = lean_alloc_sarray(sizeof(double), n, n);
  for (size_t k = 0; k < n; ++k) {
    fe_message m = read_bytes<fe_message>(lean_array_get_core(p_messages, k));
    fe_observe(&st, &m);
    lean_float_array_cptr(out)[k] = (double)st.count;
  }
  return out;
}

// ── Calibration file ─────────────────────────────────────────────────────────

LEAN_EXPORT lean_obj_res fe_lean_calib_round_trip(b_lean_obj_arg p_path, b_lean_obj_arg p_calib, lean_obj_arg) {
  fe_text path = text_of(p_path);
  fe_frame_calib c = read_struct<fe_frame_calib>(p_calib);
  fe_frame_calib back = fe_frame_calib_default();
  if (!fe_calib_save(&path, &c) || !fe_calib_load(&path, &back)) {
    return lean_io_result_mk_ok(empty_floats());
  }
  return lean_io_result_mk_ok(struct_array(back));
}

// ── Outputs ──────────────────────────────────────────────────────────────────

namespace {

lean_obj_res messages_array(const fe_message *p_messages, int32_t p_count) {
  lean_object *out = lean_mk_empty_array();
  for (int32_t k = 0; k < p_count; ++k) {
    out = lean_array_push(out, byte_array(p_messages[k]));
  }
  return out;
}

fe_eyes read_eyes(b_lean_obj_arg p_array) { return read_struct<fe_eyes>(p_array); }

} // namespace

LEAN_EXPORT uint32_t fe_lean_message_argc(b_lean_obj_arg p_message) {
  return (uint32_t)read_bytes<fe_message>(p_message).argc;
}

LEAN_EXPORT uint32_t fe_lean_message_int(b_lean_obj_arg p_message, uint32_t p_index) {
  fe_message m = read_bytes<fe_message>(p_message);
  return p_index < (uint32_t)m.argc ? (uint32_t)m.args[p_index].i : 0;
}

LEAN_EXPORT double fe_lean_steamlink_closed(double p_lid) { return fe_steamlink_closed((float)p_lid); }

LEAN_EXPORT lean_obj_res fe_lean_steamlink_messages(b_lean_obj_arg p_eyes) {
  static fe_message messages[16];
  fe_eyes e = read_eyes(p_eyes);
  return messages_array(messages, fe_steamlink_messages(&e, messages));
}

LEAN_EXPORT lean_obj_res fe_lean_gaze_vector(double p_x, double p_y) {
  fe_vec3 v = fe_gaze_vector((float)p_x, (float)p_y);
  const float f[3] = {v.x, v.y, v.z};
  return float_array(f, 3);
}

LEAN_EXPORT lean_obj_res fe_lean_native_messages(b_lean_obj_arg p_eyes, uint8_t p_independent) {
  static fe_message messages[4];
  fe_eyes e = read_eyes(p_eyes);
  return messages_array(messages, fe_native_messages(&e, p_independent != 0, messages));
}

LEAN_EXPORT lean_obj_res fe_lean_active_message(b_lean_obj_arg p_prefix, uint8_t p_active, uint32_t p_type) {
  static fe_message message;
  fe_text prefix = text_of(p_prefix);
  bool has = fe_active_message(&prefix, p_active != 0, (int32_t)p_type, &message);
  return messages_array(&message, has ? 1 : 0);
}

LEAN_EXPORT double fe_lean_etvr_lid(double p_lid) { return fe_etvr_lid((float)p_lid); }

LEAN_EXPORT lean_obj_res fe_lean_etvr_messages(b_lean_obj_arg p_eyes, b_lean_obj_arg p_prefix) {
  static fe_message messages[8];
  fe_eyes e = read_eyes(p_eyes);
  fe_text prefix = text_of(p_prefix);
  return messages_array(messages, fe_etvr_messages(&e, &prefix, messages));
}

LEAN_EXPORT lean_obj_res fe_lean_livelink_shapes(b_lean_obj_arg p_eyes) {
  float shapes[61];
  fe_eyes e = read_eyes(p_eyes);
  fe_livelink_shapes(&e, shapes);
  return float_array(shapes, 61);
}

LEAN_EXPORT lean_obj_res fe_lean_livelink_packet(double p_time, b_lean_obj_arg p_shapes) {
  float shapes[61];
  read_floats(p_shapes, shapes, 61);
  uint8_t out[512];
  int32_t n = fe_livelink_packet(p_time, shapes, out);
  return bytes_of(out, n > 0 ? (size_t)n : 0);
}


// How many packets the throttle lets through for samples every p_step_us microseconds over
// p_seconds, with a 20 ms interval; p_planted uses "20 ms since the last send" instead.
LEAN_EXPORT uint32_t fe_lean_throttle_count(uint32_t p_step_us, uint32_t p_seconds, uint8_t p_planted) {
  int64_t due = 0;
  int64_t last = -1000000;
  uint32_t sent = 0;
  for (int64_t us = 0; us < (int64_t)p_seconds * 1000000; us += p_step_us) {
    const int64_t now = us / 1000;
    if (p_planted) {
      if (now - last >= 20) {
        last = now;
        sent += 1;
      }
    } else if (fe_throttle(&due, now, 20)) {
      sent += 1;
    }
  }
  return sent;
}

}
