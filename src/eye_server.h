// SPDX-License-Identifier: MIT
#ifndef FRAMEEYEOSC_EYE_SERVER_H
#define FRAMEEYEOSC_EYE_SERVER_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define FE_SHM_VERSION 4u
#define FE_SHM_SIZE 0x4f21au
#define FE_RECORD_OFFSET 0x152u
#define FE_RECORD_SIZE 0xebcu

typedef struct fe_sample {
  uint32_t producer_state;
  double sample_time;
  float gaze[2][3];
  float gaze_covariance[2][3];
  float fixation_point[3];
  float openness[2];
} fe_sample;

typedef struct fe_source fe_source;

// Maps the eye server's shared memory; NULL with a message in err on failure.
fe_source *fe_open(const char *path, char *err, size_t err_len);
// 1 when a new record was copied into out, 0 on timeout, -1 on error (message in err).
int fe_next(fe_source *source, int timeout_ms, fe_sample *out, char *err, size_t err_len);
void fe_close(fe_source *source);
// Decodes a raw record of FE_RECORD_SIZE bytes, as it sits at FE_RECORD_OFFSET.
void fe_decode(const uint8_t *record, fe_sample *out);

#ifdef __cplusplus
}
#endif

#endif
