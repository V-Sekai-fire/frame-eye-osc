// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Everything but main, exported with C names so the witness-cpp tests can call it.
module core;

import bridge;
import config;
import eye_server;
import kernels;
import osc;
import params;
import text;

public export __extern_cpp int fe_osc_encode(Message p_message, uint8_t* r_out, int p_cap)
{
    return osc_encode(p_message, r_out, p_cap);
}

public export __extern_cpp bool fe_osc_decode(uint8_t* p_data, int p_size, out Message r_message)
{
    return osc_decode(p_data, p_size, r_message);
}

public export __extern_cpp int fe_osc_decode_packet(uint8_t* p_data, int p_size, Message* r_messages, int p_max)
{
    return osc_decode_packet(p_data, p_size, r_messages, p_max);
}

public export __extern_cpp int fe_osc_bundle(Message* p_messages, int p_count, uint8_t* r_out, int p_cap)
{
    return osc_bundle(p_messages, p_count, r_out, p_cap);
}

public export __extern_cpp bool fe_osc_equal(Message p_a, Message p_b)
{
    return osc_equal(p_a, p_b);
}

public export __extern_cpp int fe_fallback_plan(Text p_prefix, Entry* r_entries, int p_max)
{
    return fallback_plan(p_prefix, r_entries, p_max);
}

public export __extern_cpp int fe_v2_count()
{
    return v2_count();
}

public export __extern_cpp Message fe_message_for(Entry p_entry, FrameOut p_out)
{
    return message_for(p_entry, p_out);
}

public export __extern_cpp bool fe_observe(inout Learned r_state, Message p_message)
{
    return observe(r_state, p_message);
}

public export __extern_cpp void fe_learned_clear(inout Learned r_state)
{
    learned_clear(r_state);
}

public export __extern_cpp bool fe_calib_save(Text p_path, FrameCalib p_calib)
{
    return calib_save(p_path, p_calib);
}

public export __extern_cpp bool fe_calib_load(Text p_path, inout FrameCalib r_calib)
{
    return calib_load(p_path, r_calib);
}

public export __extern_cpp bool fe_gains_load(Text p_path, inout Gains r_gains, out Text r_error)
{
    return gains_load(p_path, r_gains, r_error);
}

public export __extern_cpp bool fe_eye_open(Text p_path, out Source r_source, out Text r_error)
{
    return eye_open(p_path, r_source, r_error);
}

public export __extern_cpp int fe_eye_next(Source p_source, int p_timeout_ms, out Sample r_sample, out Text r_error)
{
    return eye_next(p_source, p_timeout_ms, r_sample, r_error);
}

public export __extern_cpp void fe_eye_close(inout Source r_source)
{
    eye_close(r_source);
}
