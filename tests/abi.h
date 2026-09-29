// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// The structs and exported functions of core.slang as the tests see them. Each struct mirrors
// its Slang declaration field for field; struct arguments cross by pointer, results by value.
#ifndef FRAMEEYEOSC_ABI_H
#define FRAMEEYEOSC_ABI_H

#include <cstdint>
#include <cstring>

extern "C" {

struct fe_text {
  uint8_t bytes[256];
  int32_t size;
};

struct fe_arg {
  uint8_t tag;
  float f;
  int32_t i;
  fe_text s;
};

struct fe_message {
  fe_text address;
  int32_t argc;
  fe_arg args[4];
};

struct fe_vec3 {
  float x;
  float y;
  float z;
};

struct fe_eye_in {
  float openness;
  float x;
  float y;
};

struct fe_frame_in {
  fe_eye_in left;
  fe_eye_in right;
};

struct fe_calib {
  float closed;
  float neutral;
  float wide;
};

struct fe_frame_calib {
  fe_calib left;
  fe_calib right;
};

struct fe_gains {
  float squint;
  float cheek_from_squint;
  float brow_down_from_squint;
  float brow_pinch_from_squint;
  float brow_inner_from_wide;
  float brow_outer_from_wide;
};

struct fe_eye_out {
  float x;
  float y;
  float look_up;
  float look_down;
  float look_in;
  float look_out;
  float blink;
  float openness;
  float wide;
  float squint;
  float lid;
  float cheek_squint;
  float brow_lowerer;
  float brow_pinch;
  float brow_inner_up;
  float brow_outer_up;
};

struct fe_frame_out {
  fe_eye_out left;
  fe_eye_out right;
  float x;
  float y;
};

struct fe_tuning {
  float close_at;
  float open_at;
  float close_ms;
  float open_ms;
  float squint_at;
  float squint_after_ms;
  float squint_full_ms;
  float wide_dead_zone;
  float lid_follow;
};

enum { FE_OPENED = 0, FE_CLOSING = 1, FE_CLOSED = 2, FE_OPENING = 3 };

struct fe_eye_state {
  int32_t phase;
  float t_ms;
  float from;
  float partial_ms;
};

struct fe_style_state {
  fe_eye_state left;
  fe_eye_state right;
};

struct fe_one_euro {
  float x;
  float dx;
  bool primed;
};

struct fe_sample {
  uint32_t producer_state;
  double sample_time;
  fe_vec3 gaze[2];
  fe_vec3 gaze_covariance[2];
  fe_vec3 fixation_point;
  float openness[2];
};

struct fe_source {
  uint8_t *map;
};

struct fe_entry {
  fe_text address;
  int32_t feed;
  int32_t table;
  int32_t id;
  int32_t bit;
  int32_t width;
};

struct fe_avatar_param {
  fe_text address;
  uint8_t type;
};

struct fe_learned {
  fe_text avatar;
  int32_t count;
  fe_avatar_param params[512];
};

float fe_clamp01(float p_v);
float fe_clamp_signed(float p_v);
fe_calib fe_calib_normalized(const fe_calib *p_c);
fe_calib fe_calib_step(const fe_calib *p_c, float p_openness);
fe_frame_calib fe_frame_calib_step(const fe_frame_calib *p_c, const fe_frame_in *p_f);
float fe_blink_of(const fe_calib *p_c, float p_openness);
float fe_wide_of(const fe_calib *p_c, float p_openness);
fe_eye_out fe_eye(int32_t p_side, const fe_gains *p_g, bool p_heuristics, const fe_calib *p_c, const fe_eye_in *p_e);
fe_frame_out fe_frame(const fe_gains *p_g, bool p_heuristics, const fe_frame_calib *p_c, const fe_frame_in *p_f);
fe_frame_in fe_parallel(const fe_frame_in *p_f);
fe_frame_in fe_mirror(const fe_frame_in *p_f);
float fe_relative(const fe_calib *p_c, float p_openness);
float fe_level(const fe_tuning *p_k, const fe_eye_state *p_s);
fe_eye_state fe_step_eye(const fe_tuning *p_k, float p_dt_ms, const fe_eye_state *p_s, float p_rel);
fe_style_state fe_style_step(const fe_tuning *p_k, float p_dt_ms, const fe_style_state *p_s, float p_rel_left,
                             float p_rel_right);
fe_eye_out fe_style_eye(const fe_tuning *p_k, const fe_gains *p_g, bool p_heuristics, const fe_calib *p_c, float p_raw,
                        const fe_eye_state *p_s, const fe_eye_out *p_base);
void fe_wink_gate(bool p_lost_left, bool p_lost_right, float *r_rel_left, float *r_rel_right);
bool fe_eye_lost(const fe_vec3 *p_covariance, float p_threshold);
float fe_expressive(float p_gain, float p_limit, float p_dead, float p_degrees);
fe_one_euro fe_one_euro_step(const fe_one_euro *p_f, float p_value, float p_dt_s);
void fe_pitch_yaw_degrees(const fe_vec3 *p_direction, float *r_pitch, float *r_yaw);
fe_vec3 fe_center_direction(const fe_vec3 *p_left, const fe_vec3 *p_right);
void fe_gaze_angles(const fe_vec3 *p_direction, float *r_x, float *r_y);
int32_t fe_quantize(int32_t p_width, float p_value);

int32_t fe_osc_encode(const fe_message *p_message, uint8_t *r_out, int32_t p_cap);
bool fe_osc_decode(const uint8_t *p_data, int32_t p_size, fe_message *r_message);
int32_t fe_osc_decode_packet(const uint8_t *p_data, int32_t p_size, fe_message *r_messages, int32_t p_max);
int32_t fe_osc_bundle(const fe_message *p_messages, int32_t p_count, uint8_t *r_out, int32_t p_cap);
bool fe_osc_equal(const fe_message *p_a, const fe_message *p_b);

int32_t fe_plan(const fe_avatar_param *p_avatar, int32_t p_count, fe_entry *r_entries, int32_t p_max);
int32_t fe_fallback_plan(const fe_text *p_prefix, fe_entry *r_entries, int32_t p_max);
int32_t fe_v2_count();
fe_message fe_message_for(const fe_entry *p_entry, const fe_frame_out *p_out);
bool fe_observe(fe_learned *r_state, const fe_message *p_message);
void fe_learned_clear(fe_learned *r_state);

bool fe_calib_save(const fe_text *p_path, const fe_frame_calib *p_calib);
bool fe_calib_load(const fe_text *p_path, fe_frame_calib *r_calib);
bool fe_gains_load(const fe_text *p_path, fe_gains *r_gains, fe_text *r_error);

fe_sample fe_decode(const uint8_t *p_record);
bool fe_eye_open(const fe_text *p_path, fe_source *r_source, fe_text *r_error);
int32_t fe_eye_next(const fe_source *p_source, int32_t p_timeout_ms, fe_sample *r_sample, fe_text *r_error);
void fe_eye_close(fe_source *r_source);
bool fe_sample_valid(const fe_sample *p_sample);
fe_message fe_tracking_active(const fe_text *p_prefix, bool p_active);
void fe_reference_messages(const fe_sample *p_sample, const fe_text *p_prefix, fe_message *r_messages);
}

static const int FE_REFERENCE_MESSAGES = 9;
static const int FE_RECORD_OFFSET = 0x152;
static const int FE_RECORD_SIZE = 0xebc;
static const int FE_SHM_SIZE = 0x4f21a;
static const uint32_t FE_SHM_VERSION = 4;

inline fe_text fe_text_of(const char *p_text) {
  fe_text t;
  std::memset(&t, 0, sizeof t);
  t.size = (int32_t)std::strlen(p_text);
  std::memcpy(t.bytes, p_text, (size_t)t.size);
  return t;
}

inline bool fe_text_is(const fe_text &p_text, const char *p_literal) {
  return p_text.size == (int32_t)std::strlen(p_literal) && std::memcmp(p_text.bytes, p_literal, (size_t)p_text.size) == 0;
}

inline fe_message fe_message_of(const char *p_address) {
  fe_message m;
  std::memset(&m, 0, sizeof m);
  m.address = fe_text_of(p_address);
  return m;
}

inline void fe_add_float(fe_message &r_message, float p_value) {
  r_message.args[r_message.argc].tag = 'f';
  r_message.args[r_message.argc].f = p_value;
  r_message.argc += 1;
}

inline void fe_add_int(fe_message &r_message, int32_t p_value) {
  r_message.args[r_message.argc].tag = 'i';
  r_message.args[r_message.argc].i = p_value;
  r_message.argc += 1;
}

inline void fe_add_bool(fe_message &r_message, bool p_value) {
  r_message.args[r_message.argc].tag = p_value ? 'T' : 'F';
  r_message.argc += 1;
}

inline void fe_add_string(fe_message &r_message, const char *p_value) {
  r_message.args[r_message.argc].tag = 's';
  r_message.args[r_message.argc].s = fe_text_of(p_value);
  r_message.argc += 1;
}

inline fe_calib fe_calib_default() { return fe_calib{0.0f, 0.75f, 1.0f}; }
inline fe_frame_calib fe_frame_calib_default() { return fe_frame_calib{fe_calib_default(), fe_calib_default()}; }
inline fe_gains fe_gains_default() { return fe_gains{1.0f, 0.6f, 0.5f, 0.3f, 0.7f, 0.8f}; }
inline fe_tuning fe_tuning_default() { return fe_tuning{0.35f, 0.55f, 60.0f, 140.0f, 0.8f, 250.0f, 400.0f, 0.2f, 0.25f}; }
inline fe_eye_state fe_eye_state_default() { return fe_eye_state{FE_OPENED, 0.0f, 1.0f, 0.0f}; }
inline fe_style_state fe_style_state_default() { return fe_style_state{fe_eye_state_default(), fe_eye_state_default()}; }

#endif
