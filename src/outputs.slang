// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 sasaken1102r
// SPDX-License-Identifier: MIT
// The other outputs: the parameter names Steam Link's own OSC sends, VRChat's own eye-tracking
// input, VRCFaceTracking's ETVR module and Live Link Face packets for VRCFaceTracking's LiveLink
// module. Behaviour and constants follow sasaken1102r's frameeyeosc fork, which measured Steam
// Link's names against SteamVR 2.18.2. Eyelids are on the VRCFT scale: 0 closed, 0.75 relaxed
// open, 1 widened.
module outputs;

import kernels;
import osc;
import text;

public static const float LID_RELAXED = 0.75;
static const float QUARTER_TURN = 0.785398163397448;
public static const int STEAMLINK_MESSAGES = 12;
public static const int NATIVE_MESSAGES = 2;
public static const int ETVR_MESSAGES = 6;
public static const int LIVELINK_SHAPES = 61;
public static const int LIVELINK_PACKET = 291;
// Where the eyes go: VRChat's avatar parameters, VRCFaceTracking's ETVR module, or Live Link
// Face packets for VRCFaceTracking's LiveLink module.
public static const int OUTPUT_VRCHAT = 0;
public static const int OUTPUT_ETVR = 1;
public static const int OUTPUT_LIVELINK = 2;
// How EyeTrackingActive goes out.
public static const int ACTIVE_BOOL = 0;
public static const int ACTIVE_FLOAT = 1;
public static const int ACTIVE_OFF = 2;

// Gaze (left x, y, right x, y, combined x, y; 1 = 45 degrees, +x right, +y up) and both eyelids,
// as one output sends them.
public struct Eyes
{
    public float gaze[6];
    public float lid[2];
};

Message float_message(Text p_address, float p_value)
{
    Message m = osc_message(p_address);
    osc_add_float(m, p_value);
    return m;
}

Message int_message(Text p_address, int p_value)
{
    Message m = osc_message(p_address);
    osc_add_int(m, p_value);
    return m;
}

Text parameter(NativeString p_name)
{
    Text t = text_of("/avatar/parameters/");
    text_add(t, p_name);
    return t;
}

// "/avatar/parameters" followed by the prefix without its trailing slashes.
Text prefixed(Text p_prefix)
{
    int n = p_prefix.size;
    while (n > 0 && p_prefix.bytes[n - 1] == 47)
    {
        n -= 1;
    }
    Text t = text_of("/avatar/parameters");
    text_add_text(t, text_slice(p_prefix, 0, n));
    return t;
}

// How closed an eye is the way Steam Link sends it (0 open, 1 shut): relaxed open and anything
// widened above it are 0, and 0.75..0 closes it evenly to 1.
public export __extern_cpp float fe_steamlink_closed(float p_lid)
{
    return clamp(1.0 - p_lid / LID_RELAXED, 0.0, 1.0);
}

void steamlink_eye(Message* r_messages, int p_at, NativeString p_lid, NativeString p_squeeze, NativeString p_toggle,
                   NativeString p_widen, float p_closed)
{
    bool shut = p_closed > 0.5;
    r_messages[p_at] = float_message(parameter(p_lid), p_closed);
    r_messages[p_at + 1] = float_message(parameter(p_squeeze), shut ? 0.0 : 0.8);
    r_messages[p_at + 2] = int_message(parameter(p_toggle), shut ? 1 : 0);
    r_messages[p_at + 3] = int_message(parameter(p_widen), 1);
}

// The avatar parameters Steam Link's own OSC sends, in its order and without a prefix, for avatars
// made for it. Its X is ours; its Y is ours turned over (+ is down). Writes STEAMLINK_MESSAGES.
public export __extern_cpp int fe_steamlink_messages(Eyes p_eyes, Message* r_messages)
{
    r_messages[0] = float_message(parameter("LeftEyeX"), p_eyes.gaze[0]);
    r_messages[1] = float_message(parameter("LeftEyeY"), -p_eyes.gaze[1]);
    r_messages[2] = float_message(parameter("RightEyeX"), p_eyes.gaze[2]);
    r_messages[3] = float_message(parameter("RightEyeY"), -p_eyes.gaze[3]);
    steamlink_eye(r_messages, 4, "RightEyeLid", "RightEyeLidExpandedSqueeze", "RightEyeSqueezeToggle",
                  "RightEyeWidenToggle", fe_steamlink_closed(p_eyes.lid[1]));
    steamlink_eye(r_messages, 8, "LeftEyeLid", "LeftEyeLidExpandedSqueeze", "LeftEyeSqueezeToggle",
                  "LeftEyeWidenToggle", fe_steamlink_closed(p_eyes.lid[0]));
    return STEAMLINK_MESSAGES;
}

// A unit vector in VRChat's head space (+x right, +y up, +z forward) for a gaze pair; the inverse
// of fe_gaze_angles.
public export __extern_cpp Vec3 fe_gaze_vector(float p_x, float p_y)
{
    float quarter = QUARTER_TURN;
    float right = tan(p_x * quarter);
    float up = tan(p_y * quarter);
    float n = sqrt(right * right + up * up + 1.0);
    Vec3 v;
    v.x = right / n;
    v.y = up / n;
    v.z = 1.0 / n;
    return v;
}

void add_vector(inout Message r_message, Vec3 p_v)
{
    osc_add_float(r_message, p_v.x);
    osc_add_float(r_message, p_v.y);
    osc_add_float(r_message, p_v.z);
}

// VRChat's own eye-tracking input, which drives the avatar descriptor's Eye Look on any avatar:
// one look address (each eye's own with p_independent) and one closed amount for both eyes.
// Writes NATIVE_MESSAGES.
public export __extern_cpp int fe_native_messages(Eyes p_eyes, bool p_independent, Message* r_messages)
{
    if (p_independent)
    {
        Message look = osc_message(text_of("/tracking/eye/LeftRightVec"));
        add_vector(look, fe_gaze_vector(p_eyes.gaze[0], p_eyes.gaze[1]));
        add_vector(look, fe_gaze_vector(p_eyes.gaze[2], p_eyes.gaze[3]));
        r_messages[0] = look;
    }
    else
    {
        Message look = osc_message(text_of("/tracking/eye/CenterVec"));
        add_vector(look, fe_gaze_vector(p_eyes.gaze[4], p_eyes.gaze[5]));
        r_messages[0] = look;
    }
    float open = (p_eyes.lid[0] + p_eyes.lid[1]) / 2.0 / LID_RELAXED;
    r_messages[1] = float_message(text_of("/tracking/eye/EyesClosedAmount"), clamp(1.0 - open, 0.0, 1.0));
    return NATIVE_MESSAGES;
}

// EyeTrackingActive as p_type wants it (ACTIVE_BOOL, ACTIVE_FLOAT); false for ACTIVE_OFF.
public export __extern_cpp bool fe_active_message(Text p_prefix, bool p_active, int p_type, out Message r_message)
{
    Text address = prefixed(p_prefix);
    text_add(address, "/EyeTrackingActive");
    r_message = osc_message(address);
    if (p_type == ACTIVE_BOOL)
    {
        osc_add_bool(r_message, p_active);
        return true;
    }
    if (p_type == ACTIVE_FLOAT)
    {
        osc_add_float(r_message, p_active ? 1.0 : 0.0);
        return true;
    }
    return false;
}

// The ETVR module reads 1 as relaxed open, so relaxed and above are 1.
public export __extern_cpp float fe_etvr_lid(float p_lid)
{
    return clamp(p_lid / LID_RELAXED, 0.0, 1.0);
}

Message v2(Text p_prefix, NativeString p_name, float p_value)
{
    Text address = prefixed(p_prefix);
    text_add(address, "/v2/");
    text_add(address, p_name);
    return float_message(address, p_value);
}

// The ETVR Tracking Module's per-eye values only: EyeX/EyeY would switch it to a single-eye mode
// that reads an eyelid not sent. Writes ETVR_MESSAGES.
public export __extern_cpp int fe_etvr_messages(Eyes p_eyes, Text p_prefix, Message* r_messages)
{
    r_messages[0] = v2(p_prefix, "EyeLeftX", p_eyes.gaze[0]);
    r_messages[1] = v2(p_prefix, "EyeLeftY", p_eyes.gaze[1]);
    r_messages[2] = v2(p_prefix, "EyeRightX", p_eyes.gaze[2]);
    r_messages[3] = v2(p_prefix, "EyeRightY", p_eyes.gaze[3]);
    r_messages[4] = v2(p_prefix, "EyeLidLeft", fe_etvr_lid(p_eyes.lid[0]));
    r_messages[5] = v2(p_prefix, "EyeLidRight", fe_etvr_lid(p_eyes.lid[1]));
    return ETVR_MESSAGES;
}

// A steady beat of at most one packet per p_interval_ms that neither bursts nor drifts: the next is
// due an interval after the last one was due, or an interval after now when the samples paused
// for longer than that. True when a packet may go at p_now; r_due holds the next due time.
public export __extern_cpp bool fe_throttle(inout int64_t r_due, int64_t p_now, int64_t p_interval_ms)
{
    if (p_now < r_due)
    {
        return false;
    }
    r_due = p_now - r_due > p_interval_ms ? p_now + p_interval_ms : r_due + p_interval_ms;
    return true;
}

float blink_of(float p_lid)
{
    return clamp(1.0 - p_lid / LID_RELAXED, 0.0, 1.0);
}

float wide_of(float p_lid)
{
    return clamp((p_lid - LID_RELAXED) / (1.0 - LID_RELAXED), 0.0, 1.0);
}

// The 61 ARKit blendshapes of a Live Link Face packet: each eyelid split into blink and widen
// (VRCFT's LiveLink module puts them back together), each eye's yaw and pitch (+ is down).
public export __extern_cpp void fe_livelink_shapes(Eyes p_eyes, float* r_shapes)
{
    for (int k = 0; k < LIVELINK_SHAPES; k++)
    {
        r_shapes[k] = 0.0;
    }
    r_shapes[0] = blink_of(p_eyes.lid[0]);
    r_shapes[6] = wide_of(p_eyes.lid[0]);
    r_shapes[7] = blink_of(p_eyes.lid[1]);
    r_shapes[13] = wide_of(p_eyes.lid[1]);
    r_shapes[55] = p_eyes.gaze[0];
    r_shapes[56] = -p_eyes.gaze[1];
    r_shapes[58] = p_eyes.gaze[2];
    r_shapes[59] = -p_eyes.gaze[3];
}

void put_u32_be(uint8_t* r_out, inout int r_at, uint32_t p_value)
{
    r_out[r_at] = uint8_t(p_value >> 24);
    r_out[r_at + 1] = uint8_t(p_value >> 16);
    r_out[r_at + 2] = uint8_t(p_value >> 8);
    r_out[r_at + 3] = uint8_t(p_value);
    r_at += 4;
}

void put_text(uint8_t* r_out, inout int r_at, NativeString p_text)
{
    Text t = text_of(p_text);
    put_u32_be(r_out, r_at, uint32_t(t.size));
    for (int k = 0; k < t.size; k++)
    {
        r_out[r_at] = t.bytes[k];
        r_at += 1;
    }
}

// A Live Link Face packet (version 6, device "frameeyeosc", subject "SteamFrame", 90 frames a
// second) stamped p_time seconds into the day; returns its size, LIVELINK_PACKET. r_out must hold
// that many bytes.
public export __extern_cpp int fe_livelink_packet(double p_time, float* p_shapes, uint8_t* r_out)
{
    double frames = max(p_time, 0.0) * 90.0;
    double whole = floor(frames);
    int at = 0;
    r_out[at] = 6;
    at += 1;
    put_text(r_out, at, "frameeyeosc");
    put_text(r_out, at, "SteamFrame");
    put_u32_be(r_out, at, uint32_t(int(whole)));
    put_u32_be(r_out, at, asuint(float(frames - whole)));
    put_u32_be(r_out, at, 90);
    put_u32_be(r_out, at, 1);
    r_out[at] = uint8_t(LIVELINK_SHAPES);
    at += 1;
    for (int k = 0; k < LIVELINK_SHAPES; k++)
    {
        put_u32_be(r_out, at, asuint(p_shapes[k]));
    }
    return at;
}
