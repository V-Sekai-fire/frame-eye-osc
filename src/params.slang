// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Unified Expressions (v2) and older v1 avatar parameters, fed from FrameOut, including the
// bit-packed ones: <Name>1, <Name>2, <Name>4 ... hold a quantized magnitude, <Name>Negative the sign.
module params;

import kernels;
import osc;
import text;

public static const int PARAMS_MAX = 512;
public static const int FEED_FLOAT = 0;
public static const int FEED_BIT = 1;
public static const int FEED_NEGATIVE = 2;
public static const int TABLE_V2 = 0;
public static const int TABLE_V1 = 1;

static const int V2_COUNT = 38;
static const NativeString kV2[V2_COUNT] = {
    "EyeLeftX", "EyeLeftY", "EyeRightX", "EyeRightY", "EyeX", "EyeY",
    "EyeLidLeft", "EyeLidRight", "EyeLid", "EyeOpennessLeft", "EyeOpennessRight",
    "EyeWideLeft", "EyeWideRight", "EyeWide", "EyeSquintLeft", "EyeSquintRight", "EyeSquint",
    "CheekSquintLeft", "CheekSquintRight", "CheekSquint", "BrowLowererLeft", "BrowLowererRight",
    "BrowPinchLeft", "BrowPinchRight", "BrowInnerUpLeft", "BrowInnerUpRight", "BrowInnerUp",
    "BrowOuterUpLeft", "BrowOuterUpRight", "BrowOuterUp", "BrowUpLeft", "BrowUpRight", "BrowUp",
    "BrowDownLeft", "BrowDownRight", "BrowDown", "BrowExpressionLeft", "BrowExpressionRight"
};

static const int V1_COUNT = 15;
static const NativeString kV1[V1_COUNT] = {
    "LeftEyeX", "RightEyeX", "EyesX", "EyesY", "LeftEyeLid", "RightEyeLid", "CombinedEyeLid",
    "LeftEyeWiden", "RightEyeWiden", "EyesWiden", "LeftEyeSqueeze", "RightEyeSqueeze", "EyesSqueeze",
    "LeftEyeLidExpandedSqueeze", "RightEyeLidExpandedSqueeze"
};

float avg(float p_a, float p_b)
{
    return (p_a + p_b) / 2.0;
}

float brow_up(EyeOut p_eye)
{
    return avg(p_eye.brow_inner_up, p_eye.brow_outer_up);
}

// The raw value of v2 parameter p_id.
float v2_value(int p_id, FrameOut p_o)
{
    switch (p_id)
    {
    case 0: return p_o.left.x;
    case 1: return p_o.left.y;
    case 2: return p_o.right.x;
    case 3: return p_o.right.y;
    case 4: return p_o.x;
    case 5: return p_o.y;
    case 6: return p_o.left.lid;
    case 7: return p_o.right.lid;
    case 8: return avg(p_o.left.lid, p_o.right.lid);
    case 9: return p_o.left.openness;
    case 10: return p_o.right.openness;
    case 11: return p_o.left.wide;
    case 12: return p_o.right.wide;
    case 13: return avg(p_o.left.wide, p_o.right.wide);
    case 14: return p_o.left.squint;
    case 15: return p_o.right.squint;
    case 16: return avg(p_o.left.squint, p_o.right.squint);
    case 17: return p_o.left.cheek_squint;
    case 18: return p_o.right.cheek_squint;
    case 19: return avg(p_o.left.cheek_squint, p_o.right.cheek_squint);
    case 20: return p_o.left.brow_lowerer;
    case 21: return p_o.right.brow_lowerer;
    case 22: return p_o.left.brow_pinch;
    case 23: return p_o.right.brow_pinch;
    case 24: return p_o.left.brow_inner_up;
    case 25: return p_o.right.brow_inner_up;
    case 26: return avg(p_o.left.brow_inner_up, p_o.right.brow_inner_up);
    case 27: return p_o.left.brow_outer_up;
    case 28: return p_o.right.brow_outer_up;
    case 29: return avg(p_o.left.brow_outer_up, p_o.right.brow_outer_up);
    case 30: return brow_up(p_o.left);
    case 31: return brow_up(p_o.right);
    case 32: return avg(brow_up(p_o.left), brow_up(p_o.right));
    case 33: return p_o.left.brow_lowerer;
    case 34: return p_o.right.brow_lowerer;
    case 35: return avg(p_o.left.brow_lowerer, p_o.right.brow_lowerer);
    case 36: return brow_up(p_o.left) - p_o.left.brow_lowerer;
    default: return brow_up(p_o.right) - p_o.right.brow_lowerer;
    }
}

float v1_value(int p_id, FrameOut p_o)
{
    switch (p_id)
    {
    case 0: return p_o.left.x;
    case 1: return p_o.right.x;
    case 2: return p_o.x;
    case 3: return p_o.y;
    case 4: return p_o.left.openness;
    case 5: return p_o.right.openness;
    case 6: return avg(p_o.left.openness, p_o.right.openness);
    case 7: return p_o.left.wide;
    case 8: return p_o.right.wide;
    case 9: return avg(p_o.left.wide, p_o.right.wide);
    case 10: return p_o.left.squint;
    case 11: return p_o.right.squint;
    case 12: return avg(p_o.left.squint, p_o.right.squint);
    case 13: return p_o.left.lid - p_o.left.squint;
    default: return p_o.right.lid - p_o.right.squint;
    }
}

// Gaze axes and the brow expressions are signed; everything else is a 0..1 weight.
bool is_signed(int p_table, int p_id)
{
    if (p_table == TABLE_V2)
    {
        return p_id <= 5 || p_id >= 36;
    }
    return p_id <= 3 || p_id >= 13;
}

public struct Entry
{
    public Text address;
    public int feed;
    public int table;
    public int id;
    public int bit;
    public int width;
};

// One avatar parameter as the client reports it: type is 'f', 'i' or 'T'.
public struct AvatarParam
{
    public Text address;
    public uint8_t type;
};

public float entry_value(Entry p_entry, FrameOut p_o)
{
    float raw = p_entry.table == TABLE_V2 ? v2_value(p_entry.id, p_o) : v1_value(p_entry.id, p_o);
    return is_signed(p_entry.table, p_entry.id) ? fe_clamp_signed(raw) : fe_clamp01(raw);
}

public Message message_for(Entry p_entry, FrameOut p_o)
{
    float v = entry_value(p_entry, p_o);
    Message m = osc_message(p_entry.address);
    if (p_entry.feed == FEED_FLOAT)
    {
        osc_add_float(m, v);
        return m;
    }
    if (p_entry.feed == FEED_NEGATIVE)
    {
        osc_add_bool(m, v < 0.0);
        return m;
    }
    osc_add_bool(m, ((fe_quantize(p_entry.width, v) >> p_entry.bit) & 1) != 0);
    return m;
}

// The id of p_name in the v2 or v1 table, or -1.
int lookup(int p_table, Text p_name)
{
    int count = p_table == TABLE_V2 ? V2_COUNT : V1_COUNT;
    for (int k = 0; k < count; k++)
    {
        NativeString name = p_table == TABLE_V2 ? kV2[k] : kV1[k];
        if (text_equals(p_name, name))
        {
            return k;
        }
    }
    return -1;
}

// "/avatar/parameters/FT/v2/EyeLid" -> v2 "EyeLid"; "/avatar/parameters/LeftEyeLid" -> v1.
bool split_name(Text p_address, out int r_table, out Text r_name)
{
    r_table = TABLE_V1;
    r_name = text_empty();
    NativeString base = "/avatar/parameters/";
    if (!text_starts_with(p_address, 0, base))
    {
        return false;
    }
    int at = base.getLength();
    if (text_starts_with(p_address, at, "FT/"))
    {
        at += 3;
    }
    if (text_starts_with(p_address, at, "v2/"))
    {
        r_table = TABLE_V2;
        r_name = text_slice(p_address, at + 3, p_address.size);
        return true;
    }
    for (int k = at; k < p_address.size; k++)
    {
        if (p_address.bytes[k] == 47)
        {
            return false;
        }
    }
    r_name = text_slice(p_address, at, p_address.size);
    return true;
}

static const int BIT_SUFFIXES = 8;
static const NativeString kBitText[BIT_SUFFIXES] = { "128", "64", "32", "16", "8", "4", "2", "1" };
static const int kBitIndex[BIT_SUFFIXES] = { 7, 6, 5, 4, 3, 2, 1, 0 };

// How many bit parameters of the same table share the base name.
int width_of(AvatarParam* p_avatar, int p_count, int p_table, Text p_base)
{
    int width = 0;
    for (int k = 0; k < p_count; k++)
    {
        int table;
        Text name;
        if (p_avatar[k].type == TAG_FLOAT || !split_name(p_avatar[k].address, table, name) || table != p_table)
        {
            continue;
        }
        for (int s = 0; s < BIT_SUFFIXES; s++)
        {
            Text candidate = p_base;
            text_add(candidate, kBitText[s]);
            if (text_same(candidate, name))
            {
                width += 1;
            }
        }
    }
    return width;
}

Entry entry(Text p_address, int p_feed, int p_table, int p_id, int p_bit, int p_width)
{
    Entry e = { p_address, p_feed, p_table, p_id, p_bit, p_width };
    return e;
}

bool entry_for(AvatarParam* p_avatar, int p_count, AvatarParam p_one, out Entry r_entry)
{
    r_entry = entry(text_empty(), FEED_FLOAT, TABLE_V2, 0, 0, 0);
    int table;
    Text name;
    if (!split_name(p_one.address, table, name))
    {
        return false;
    }
    if (p_one.type == TAG_FLOAT)
    {
        int id = lookup(table, name);
        r_entry = entry(p_one.address, FEED_FLOAT, table, id, 0, 0);
        return id >= 0;
    }
    if (text_ends_with(name, "Negative"))
    {
        int id = lookup(table, text_slice(name, 0, name.size - 8));
        r_entry = entry(p_one.address, FEED_NEGATIVE, table, id, 0, 0);
        return id >= 0;
    }
    for (int s = 0; s < BIT_SUFFIXES; s++)
    {
        if (!text_ends_with(name, kBitText[s]))
        {
            continue;
        }
        Text base = text_slice(name, 0, name.size - kBitText[s].getLength());
        int id = lookup(table, base);
        int width = width_of(p_avatar, p_count, table, base);
        r_entry = entry(p_one.address, FEED_BIT, table, id, kBitIndex[s], width);
        return id >= 0;
    }
    return false;
}

// Builds the send list; returns how many entries were written to r_entries, at most p_max.
public export __extern_cpp int fe_plan(AvatarParam* p_avatar, int p_count, Entry* r_entries, int p_max)
{
    int n = 0;
    for (int k = 0; k < p_count && n < p_max; k++)
    {
        Entry e;
        if (entry_for(p_avatar, p_count, p_avatar[k], e))
        {
            r_entries[n] = e;
            n += 1;
        }
    }
    return n;
}

// Without a learned list: every v2 float under p_prefix, e.g. "FT/".
public int fallback_plan(Text p_prefix, Entry* r_entries, int p_max)
{
    int n = 0;
    for (int k = 0; k < V2_COUNT && n < p_max; k++)
    {
        Text address = text_of("/avatar/parameters/");
        text_add_text(address, p_prefix);
        text_add(address, "v2/");
        text_add(address, kV2[k]);
        r_entries[n] = entry(address, FEED_FLOAT, TABLE_V2, k, 0, 0);
        n += 1;
    }
    return n;
}

public int v2_count()
{
    return V2_COUNT;
}

// The avatar's parameters, learned from the client's own OSC output.
public struct Learned
{
    public Text avatar;
    public int count;
    public AvatarParam params[PARAMS_MAX];
};

public void learned_clear(inout Learned r_state)
{
    r_state.avatar = text_empty();
    r_state.count = 0;
}

// Folds one message in; true when the parameter set changed.
public bool observe(inout Learned r_state, Message p_message)
{
    if (text_equals(p_message.address, "/avatar/change"))
    {
        learned_clear(r_state);
        if (p_message.argc == 1 && p_message.args[0].tag == TAG_STRING)
        {
            r_state.avatar = p_message.args[0].s;
        }
        return true;
    }
    if (!text_starts_with(p_message.address, 0, "/avatar/parameters/") || p_message.argc == 0)
    {
        return false;
    }
    uint8_t tag = p_message.args[0].tag;
    if (tag == TAG_STRING || r_state.count >= PARAMS_MAX)
    {
        return false;
    }
    for (int k = 0; k < r_state.count; k++)
    {
        if (text_same(r_state.params[k].address, p_message.address))
        {
            return false;
        }
    }
    AvatarParam p;
    p.address = p_message.address;
    p.type = tag == TAG_FLOAT ? TAG_FLOAT : tag == TAG_INT ? TAG_INT : TAG_TRUE;
    r_state.params[r_state.count] = p;
    r_state.count += 1;
    return true;
}
