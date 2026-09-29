// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 konsti219
// SPDX-License-Identifier: MIT
// The reference output: raw gaze and each eye's own clamped openness.
module bridge;

import eye_server;
import kernels;
import osc;
import text;

public static const int REFERENCE_MESSAGES = 9;

public export __extern_cpp bool fe_sample_valid(Sample p_sample)
{
    if (p_sample.producer_state != 1 || !isfinite(p_sample.sample_time))
    {
        return false;
    }
    for (int e = 0; e < 2; e++)
    {
        Vec3 g = p_sample.gaze[e];
        if (!isfinite(g.x) || !isfinite(g.y) || !isfinite(g.z) || !isfinite(p_sample.openness[e]))
        {
            return false;
        }
    }
    Vec3 f = p_sample.fixation_point;
    return isfinite(f.x) && isfinite(f.y) && isfinite(f.z);
}

// "/avatar/parameters" followed by the prefix without its trailing slashes.
Text base(Text p_prefix)
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

public export __extern_cpp Message fe_tracking_active(Text p_prefix, bool p_active)
{
    Text address = base(p_prefix);
    text_add(address, "/EyeTrackingActive");
    Message m = osc_message(address);
    osc_add_bool(m, p_active);
    return m;
}

static const NativeString kNames[8] = { "EyeLeftX", "EyeLeftY", "EyeRightX", "EyeRightY",
                                        "EyeLidLeft", "EyeLidRight", "EyeX", "EyeY" };

// Writes REFERENCE_MESSAGES messages to r_messages.
public export __extern_cpp void fe_reference_messages(Sample p_sample, Text p_prefix, Message* r_messages)
{
    float values[8];
    fe_gaze_angles(p_sample.gaze[0], values[0], values[1]);
    fe_gaze_angles(p_sample.gaze[1], values[2], values[3]);
    values[4] = fe_clamp01(p_sample.openness[0]);
    values[5] = fe_clamp01(p_sample.openness[1]);
    fe_gaze_angles(p_sample.fixation_point, values[6], values[7]);
    r_messages[0] = fe_tracking_active(p_prefix, true);
    for (int k = 0; k < 8; k++)
    {
        Text address = base(p_prefix);
        text_add(address, "/v2/");
        text_add(address, kNames[k]);
        Message m = osc_message(address);
        osc_add_float(m, values[k]);
        r_messages[k + 1] = m;
    }
}
