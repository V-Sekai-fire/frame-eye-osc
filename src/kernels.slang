// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Every per-sample calculation, exported with C names for the tests.
module kernels;

public struct Vec3 {
  public float x;
  public float y;
  public float z;
};

public struct EyeIn {
  public float openness;
  public float x;
  public float y;
};

public struct FrameIn {
  public EyeIn left;
  public EyeIn right;
};

public struct Calib {
  public float closed;
  public float neutral;
  public float wide;
};

public struct FrameCalib {
  public Calib left;
  public Calib right;
};

public struct Gains {
  public float squint;
  public float cheek_from_squint;
  public float brow_down_from_squint;
  public float brow_pinch_from_squint;
  public float brow_inner_from_wide;
  public float brow_outer_from_wide;
};

public struct EyeOut {
  public float x;
  public float y;
  public float look_up;
  public float look_down;
  public float look_in;
  public float look_out;
  public float blink;
  public float openness;
  public float wide;
  public float squint;
  public float lid;
  public float cheek_squint;
  public float brow_lowerer;
  public float brow_pinch;
  public float brow_inner_up;
  public float brow_outer_up;
};

public struct FrameOut {
  public EyeOut left;
  public EyeOut right;
  public float x;
  public float y;
};

public struct Tuning {
  public float close_at;
  public float open_at;
  public float close_ms;
  public float open_ms;
  public float squint_at;
  public float squint_after_ms;
  public float squint_full_ms;
  public float wide_dead_zone;
  public float lid_follow;
};

public static const int OPENED = 0;
public static const int CLOSING = 1;
public static const int CLOSED = 2;
public static const int OPENING = 3;

public struct EyeState {
  public int phase;
  public float t_ms;
  public float from;
  public float partial_ms;
};

public struct StyleState {
  public EyeState left;
  public EyeState right;
};

public struct OneEuro {
  public float x;
  public float dx;
  public bool primed;
};

static const float PI = 3.14159265358979;
static const float MIN_GAP = 0.0001;

public export __extern_cpp float fe_clamp01(float p_v) { return clamp(p_v, 0.0, 1.0); }

public export __extern_cpp float fe_clamp_signed(float p_v) { return clamp(p_v, -1.0, 1.0); }

// Forces closed < neutral < wide so no division below can be by zero.
public export __extern_cpp Calib fe_calib_normalized(Calib p_c) {
  Calib n = p_c;
  n.closed = min(p_c.closed, p_c.neutral - MIN_GAP);
  n.wide = max(p_c.wide, p_c.neutral + MIN_GAP);
  return n;
}

// Neutral follows a slow average that ignores blinks; wide is the highest openness seen,
// decaying toward neutral.
public export __extern_cpp Calib fe_calib_step(Calib p_c, float p_openness) {
  Calib n = p_c;
  if (p_openness > p_c.neutral - 0.2) {
    n.neutral = p_c.neutral + (p_openness - p_c.neutral) / 512.0;
  }
  if (p_openness > p_c.wide) {
    n.wide = p_openness;
    return n;
  }
  n.wide = max(n.neutral + 0.05, p_c.wide - MIN_GAP);
  return n;
}

public export __extern_cpp FrameCalib fe_frame_calib_step(FrameCalib p_c, FrameIn p_f) {
  FrameCalib n;
  n.left = fe_calib_step(p_c.left, p_f.left.openness);
  n.right = fe_calib_step(p_c.right, p_f.right.openness);
  return n;
}

public export __extern_cpp float fe_blink_of(Calib p_c, float p_openness) {
  Calib n = fe_calib_normalized(p_c);
  if (p_openness >= n.neutral) {
    return 0.0;
  }
  return fe_clamp01((n.neutral - p_openness) / (n.neutral - n.closed));
}

public export __extern_cpp float fe_wide_of(Calib p_c, float p_openness) {
  Calib n = fe_calib_normalized(p_c);
  if (p_openness <= n.neutral) {
    return 0.0;
  }
  return fe_clamp01((p_openness - n.neutral) / (n.wide - n.neutral));
}

// Peaks at half closure, zero when fully open or fully shut.
float tent(float p_blink) { return 2.0 * min(p_blink, 1.0 - p_blink); }

// p_side is 0 for the left eye, 1 for the right.
public export __extern_cpp EyeOut fe_eye(int p_side, Gains p_g, bool p_heuristics, Calib p_c, EyeIn p_e) {
  EyeOut o;
  o.x = fe_clamp_signed(p_e.x);
  o.y = fe_clamp_signed(p_e.y);
  float nasal = p_side == 0 ? o.x : -o.x;
  o.look_up = fe_clamp01(o.y);
  o.look_down = fe_clamp01(-o.y);
  o.look_in = fe_clamp01(nasal);
  o.look_out = fe_clamp01(-nasal);
  o.blink = fe_blink_of(p_c, p_e.openness);
  o.wide = fe_wide_of(p_c, p_e.openness);
  o.openness = fe_clamp01(1.0 - o.blink);
  o.lid = fe_clamp01(o.openness * 0.75 + o.wide * 0.25);
  o.squint = 0.0;
  o.cheek_squint = 0.0;
  o.brow_lowerer = 0.0;
  o.brow_pinch = 0.0;
  o.brow_inner_up = 0.0;
  o.brow_outer_up = 0.0;
  if (!p_heuristics) {
    return o;
  }
  o.squint = fe_clamp01(p_g.squint * tent(o.blink));
  o.cheek_squint = fe_clamp01(p_g.cheek_from_squint * o.squint);
  o.brow_lowerer = fe_clamp01(p_g.brow_down_from_squint * o.squint);
  o.brow_pinch = fe_clamp01(p_g.brow_pinch_from_squint * o.squint);
  o.brow_inner_up = fe_clamp01(p_g.brow_inner_from_wide * o.wide);
  o.brow_outer_up = fe_clamp01(p_g.brow_outer_from_wide * o.wide);
  return o;
}

public export __extern_cpp FrameOut fe_frame(Gains p_g, bool p_heuristics, FrameCalib p_c, FrameIn p_f) {
  FrameOut o;
  o.left = fe_eye(0, p_g, p_heuristics, p_c.left, p_f.left);
  o.right = fe_eye(1, p_g, p_heuristics, p_c.right, p_f.right);
  o.x = (o.left.x + o.right.x) / 2.0;
  o.y = (o.left.y + o.right.y) / 2.0;
  return o;
}

// Both eyes take the combined gaze, so large stylised eyes never cross.
public export __extern_cpp FrameIn fe_parallel(FrameIn p_f) {
  float x = (p_f.left.x + p_f.right.x) / 2.0;
  float y = (p_f.left.y + p_f.right.y) / 2.0;
  FrameIn p = p_f;
  p.left.x = x;
  p.left.y = y;
  p.right.x = x;
  p.right.y = y;
  return p;
}

// Reflects the head through its midplane: eyes swap, horizontal gaze flips.
public export __extern_cpp FrameIn fe_mirror(FrameIn p_f) {
  FrameIn m;
  m.left = p_f.right;
  m.left.x = -p_f.right.x;
  m.right = p_f.left;
  m.right.x = -p_f.left.x;
  return m;
}

public export __extern_cpp float fe_relative(Calib p_c, float p_openness) {
  Calib n = fe_calib_normalized(p_c);
  return (p_openness - n.closed) / (n.neutral - n.closed);
}

// The lid a phase shows: 1 open, 0 shut, linear close, ease-out open.
public export __extern_cpp float fe_level(Tuning p_k, EyeState p_s) {
  if (p_s.phase == OPENED) {
    return 1.0;
  }
  if (p_s.phase == CLOSED) {
    return 0.0;
  }
  if (p_s.phase == CLOSING) {
    if (p_k.close_ms <= 0.0) {
      return 0.0;
    }
    return fe_clamp01(p_s.from * (1.0 - min(p_s.t_ms, p_k.close_ms) / p_k.close_ms));
  }
  if (p_k.open_ms <= 0.0) {
    return 1.0;
  }
  float remaining = p_k.open_ms - min(p_s.t_ms, p_k.open_ms);
  return fe_clamp01(1.0 - remaining * remaining / (p_k.open_ms * p_k.open_ms));
}

EyeState start(Tuning p_k, EyeState p_s, int p_phase) {
  EyeState n = p_s;
  n.from = fe_level(p_k, p_s);
  n.phase = p_phase;
  n.t_ms = 0.0;
  return n;
}

public export __extern_cpp EyeState fe_step_eye(Tuning p_k, float p_dt_ms, EyeState p_s, float p_rel) {
  EyeState s = p_s;
  s.t_ms += p_dt_ms;
  bool partial = s.phase == OPENED && p_rel < p_k.squint_at && p_rel >= p_k.close_at;
  s.partial_ms = partial ? s.partial_ms + p_dt_ms : 0.0;
  if (s.phase == OPENED) {
    return p_rel < p_k.close_at ? start(p_k, s, CLOSING) : s;
  }
  if (s.phase == CLOSING) {
    return s.t_ms >= p_k.close_ms ? start(p_k, s, CLOSED) : s;
  }
  if (s.phase == CLOSED) {
    return p_rel > p_k.open_at ? start(p_k, s, OPENING) : s;
  }
  if (p_rel < p_k.close_at) {
    return start(p_k, s, CLOSING);
  }
  return s.t_ms >= p_k.open_ms ? start(p_k, s, OPENED) : s;
}

// Each eye steps on its own reading; one eye closing never pulls the other along.
public export __extern_cpp StyleState fe_style_step(Tuning p_k, float p_dt_ms, StyleState p_s, float p_rel_left,
                                                   float p_rel_right) {
  StyleState n;
  n.left = fe_step_eye(p_k, p_dt_ms, p_s.left, p_rel_left);
  n.right = fe_step_eye(p_k, p_dt_ms, p_s.right, p_rel_right);
  return n;
}

// Rebuilds one eye's lid, wide and squint from its blink state; gaze is kept.
public export __extern_cpp EyeOut fe_style_eye(Tuning p_k, Gains p_g, bool p_heuristics, Calib p_c, float p_raw,
                                              EyeState p_s, EyeOut p_base) {
  EyeOut o = p_base;
  float follow = fe_clamp01(fe_level(p_k, p_s) - p_k.lid_follow * p_base.look_down);
  float rel = fe_relative(p_c, p_raw);
  bool opened = p_s.phase == OPENED;
  o.blink = fe_clamp01(1.0 - follow);
  o.openness = follow;
  o.wide = opened ? fe_clamp01(rel - 1.0 - p_k.wide_dead_zone) : 0.0;
  o.lid = fe_clamp01(follow * 0.75 + o.wide * 0.25);
  o.squint = 0.0;
  float hold = p_s.partial_ms - p_k.squint_after_ms;
  if (p_heuristics && opened && hold > 0.0) {
    float ramp = min(1.0, hold / max(1.0, p_k.squint_full_ms));
    o.squint = fe_clamp01(ramp * (p_k.squint_at - rel) / (p_k.squint_at - p_k.close_at));
  }
  if (!p_heuristics) {
    return o;
  }
  o.cheek_squint = fe_clamp01(p_g.cheek_from_squint * o.squint);
  o.brow_lowerer = fe_clamp01(p_g.brow_down_from_squint * o.squint);
  o.brow_pinch = fe_clamp01(p_g.brow_pinch_from_squint * o.squint);
  o.brow_inner_up = fe_clamp01(p_g.brow_inner_from_wide * o.wide);
  o.brow_outer_up = fe_clamp01(p_g.brow_outer_from_wide * o.wide);
  return o;
}

// When the tracker loses exactly one eye, the eye it still sees is held open.
public export __extern_cpp void fe_wink_gate(bool p_lost_left, bool p_lost_right, inout float r_rel_left,
                                            inout float r_rel_right) {
  if (p_lost_left && !p_lost_right) {
    r_rel_right = max(r_rel_right, 1.0);
    return;
  }
  if (p_lost_right && !p_lost_left) {
    r_rel_left = max(r_rel_left, 1.0);
  }
}

public export __extern_cpp bool fe_eye_lost(Vec3 p_covariance, float p_threshold) {
  return max(p_covariance.x, max(p_covariance.y, p_covariance.z)) > p_threshold;
}

// Dead-zone, then a gain on small glances easing into the limit along tanh. Odd and monotone.
public export __extern_cpp float fe_expressive(float p_gain, float p_limit, float p_dead, float p_degrees) {
  float m = abs(p_degrees) - p_dead;
  if (m <= 0.0 || p_limit <= 0.0) {
    return 0.0;
  }
  float v = p_limit * tanh(p_gain * m / p_limit);
  return p_degrees < 0.0 ? -v : v;
}

float alpha(float p_cutoff_hz, float p_dt_s) {
  float tau = 1.0 / (2.0 * PI * p_cutoff_hz);
  return 1.0 / (1.0 + tau / p_dt_s);
}

// One Euro filter (Casiez et al. 2012, doi 10.1145/2207676.2208639): steady at rest, fast on a saccade.
public export __extern_cpp OneEuro fe_one_euro_step(OneEuro p_f, float p_value, float p_dt_s) {
  OneEuro n;
  if (!p_f.primed || p_dt_s <= 0.0) {
    n.x = p_value;
    n.dx = 0.0;
    n.primed = true;
    return n;
  }
  float speed = (p_value - p_f.x) / p_dt_s;
  n.dx = p_f.dx + alpha(1.0, p_dt_s) * (speed - p_f.dx);
  float cutoff = 1.2 + 0.04 * abs(n.dx);
  n.x = p_f.x + alpha(cutoff, p_dt_s) * (p_value - p_f.x);
  n.primed = true;
  return n;
}

// Pitch (positive looks down) and yaw (positive looks right) in degrees, clamped to ±45.
public export __extern_cpp void fe_pitch_yaw_degrees(Vec3 p_direction, out float r_pitch, out float r_yaw) {
  float to_deg = 180.0 / PI;
  r_pitch = clamp(-atan2(p_direction.y, -p_direction.z) * to_deg, -45.0, 45.0);
  r_yaw = clamp(atan2(p_direction.x, -p_direction.z) * to_deg, -45.0, 45.0);
}

// The mean of both eyes' directions, normalized.
public export __extern_cpp Vec3 fe_center_direction(Vec3 p_left, Vec3 p_right) {
  float3 sum = float3(p_left.x + p_right.x, p_left.y + p_right.y, p_left.z + p_right.z);
  float n = length(sum);
  Vec3 d;
  d.x = 0.0;
  d.y = 0.0;
  d.z = -1.0;
  if (n < 1.0e-6) {
    return d;
  }
  d.x = sum.x / n;
  d.y = sum.y / n;
  d.z = sum.z / n;
  return d;
}

// ±45° maps to ±1 on each axis, +Y up, from a -Z-forward direction.
public export __extern_cpp void fe_gaze_angles(Vec3 p_direction, out float r_x, out float r_y) {
  float scale = 4.0 / PI;
  r_x = clamp(atan2(p_direction.x, -p_direction.z) * scale, -1.0, 1.0);
  r_y = clamp(atan2(p_direction.y, -p_direction.z) * scale, -1.0, 1.0);
}

// The quantized magnitude a p_width-bit parameter carries, truncating.
public export __extern_cpp int fe_quantize(int p_width, float p_value) {
  float magnitude = min(abs(p_value), 1.0);
  int steps = (1 << p_width) - 1;
  return int(floor(magnitude * float(steps)));
}
