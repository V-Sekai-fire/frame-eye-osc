// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
module osc;

import text;

public static const int OSC_ARGS = 4;
public static const int OSC_PACKET = 65536;

// tag is one of 'f', 'i', 'T', 'F', 's'.
public struct Arg
{
    public uint8_t tag;
    public float f;
    public int i;
    public Text s;
};

public struct Message
{
    public Text address;
    public int argc;
    public Arg args[OSC_ARGS];
};

public static const uint8_t TAG_FLOAT = 102;
public static const uint8_t TAG_INT = 105;
public static const uint8_t TAG_TRUE = 84;
public static const uint8_t TAG_FALSE = 70;
public static const uint8_t TAG_STRING = 115;

public Message osc_message(Text p_address)
{
    Message m;
    m.address = p_address;
    m.argc = 0;
    for (int k = 0; k < OSC_ARGS; k++)
    {
        m.args[k].tag = 0;
        m.args[k].f = 0.0;
        m.args[k].i = 0;
        m.args[k].s = text_empty();
    }
    return m;
}

bool add_arg(inout Message r_message, Arg p_arg)
{
    if (r_message.argc >= OSC_ARGS)
    {
        return false;
    }
    r_message.args[r_message.argc] = p_arg;
    r_message.argc += 1;
    return true;
}

Arg blank(uint8_t p_tag)
{
    Arg a;
    a.tag = p_tag;
    a.f = 0.0;
    a.i = 0;
    a.s = text_empty();
    return a;
}

public bool osc_add_float(inout Message r_message, float p_value)
{
    Arg a = blank(TAG_FLOAT);
    a.f = p_value;
    return add_arg(r_message, a);
}

public bool osc_add_int(inout Message r_message, int p_value)
{
    Arg a = blank(TAG_INT);
    a.i = p_value;
    return add_arg(r_message, a);
}

public bool osc_add_bool(inout Message r_message, bool p_value)
{
    return add_arg(r_message, blank(p_value ? TAG_TRUE : TAG_FALSE));
}

public bool osc_add_string(inout Message r_message, Text p_value)
{
    Arg a = blank(TAG_STRING);
    a.s = p_value;
    return add_arg(r_message, a);
}

public bool osc_arg_equal(Arg p_a, Arg p_b)
{
    if (p_a.tag != p_b.tag)
    {
        return false;
    }
    if (p_a.tag == TAG_FLOAT)
    {
        return asuint(p_a.f) == asuint(p_b.f);
    }
    if (p_a.tag == TAG_INT)
    {
        return p_a.i == p_b.i;
    }
    if (p_a.tag == TAG_STRING)
    {
        return text_same(p_a.s, p_b.s);
    }
    return true;
}

public bool osc_equal(Message p_a, Message p_b)
{
    if (!text_same(p_a.address, p_b.address) || p_a.argc != p_b.argc)
    {
        return false;
    }
    for (int k = 0; k < p_a.argc; k++)
    {
        if (!osc_arg_equal(p_a.args[k], p_b.args[k]))
        {
            return false;
        }
    }
    return true;
}

// A writer that stops, rather than overruns, when the buffer is full.
struct Writer
{
    uint8_t* out;
    int cap;
    int at;
    bool full;
};

void put_byte(inout Writer r_writer, uint8_t p_byte)
{
    if (r_writer.full || r_writer.at >= r_writer.cap)
    {
        r_writer.full = true;
        return;
    }
    r_writer.out[r_writer.at] = p_byte;
    r_writer.at += 1;
}

void put_text(inout Writer r_writer, Text p_text)
{
    for (int k = 0; k < p_text.size; k++)
    {
        put_byte(r_writer, p_text.bytes[k]);
    }
    for (int pad = 4 - p_text.size % 4; pad > 0; pad--)
    {
        put_byte(r_writer, 0);
    }
}

void put_u32(inout Writer r_writer, uint32_t p_value)
{
    put_byte(r_writer, uint8_t(p_value >> 24));
    put_byte(r_writer, uint8_t(p_value >> 16));
    put_byte(r_writer, uint8_t(p_value >> 8));
    put_byte(r_writer, uint8_t(p_value));
}

void put_message(inout Writer r_writer, Message p_message)
{
    Text tags = text_of(",");
    for (int k = 0; k < p_message.argc; k++)
    {
        text_push(tags, p_message.args[k].tag);
    }
    put_text(r_writer, p_message.address);
    put_text(r_writer, tags);
    for (int k = 0; k < p_message.argc; k++)
    {
        Arg a = p_message.args[k];
        if (a.tag == TAG_FLOAT)
        {
            put_u32(r_writer, asuint(a.f));
        }
        else if (a.tag == TAG_INT)
        {
            put_u32(r_writer, uint32_t(a.i));
        }
        else if (a.tag == TAG_STRING)
        {
            put_text(r_writer, a.s);
        }
    }
}

// Bytes written, or 0 when the buffer is too small.
public int osc_encode(Message p_message, uint8_t* r_out, int p_cap)
{
    Writer w = { r_out, p_cap, 0, false };
    put_message(w, p_message);
    return w.full ? 0 : w.at;
}

bool read_text(uint8_t* p_data, int p_size, inout int r_at, out Text r_text)
{
    r_text = text_empty();
    int end = r_at;
    while (end < p_size && p_data[end] != 0)
    {
        end += 1;
    }
    if (end >= p_size || end - r_at >= TEXT_SIZE)
    {
        return false;
    }
    int next = (end + 4) & ~3;
    if (next > p_size)
    {
        return false;
    }
    for (int k = r_at; k < end; k++)
    {
        text_push(r_text, p_data[k]);
    }
    r_at = next;
    return true;
}

bool read_u32(uint8_t* p_data, int p_size, inout int r_at, out uint32_t r_value)
{
    r_value = 0;
    if (r_at + 4 > p_size)
    {
        return false;
    }
    r_value = (uint32_t(p_data[r_at]) << 24) | (uint32_t(p_data[r_at + 1]) << 16) |
              (uint32_t(p_data[r_at + 2]) << 8) | uint32_t(p_data[r_at + 3]);
    r_at += 4;
    return true;
}

bool read_arg(uint8_t* p_data, int p_size, inout int r_at, uint8_t p_tag, inout Message r_message)
{
    if (p_tag == TAG_TRUE || p_tag == TAG_FALSE)
    {
        return osc_add_bool(r_message, p_tag == TAG_TRUE);
    }
    if (p_tag == TAG_STRING)
    {
        Text s;
        return read_text(p_data, p_size, r_at, s) && osc_add_string(r_message, s);
    }
    if (p_tag != TAG_FLOAT && p_tag != TAG_INT)
    {
        return false;
    }
    uint32_t word;
    if (!read_u32(p_data, p_size, r_at, word))
    {
        return false;
    }
    if (p_tag == TAG_INT)
    {
        return osc_add_int(r_message, int(word));
    }
    return osc_add_float(r_message, asfloat(word));
}

// False when the bytes are not one well-formed message.
public bool osc_decode(uint8_t* p_data, int p_size, out Message r_message)
{
    int at = 0;
    Text address;
    Text tags;
    r_message = osc_message(text_empty());
    if (!read_text(p_data, p_size, at, address) || address.size == 0 || address.bytes[0] != 47)
    {
        return false;
    }
    if (!read_text(p_data, p_size, at, tags) || tags.size == 0 || tags.bytes[0] != 44)
    {
        return false;
    }
    Message m = osc_message(address);
    for (int k = 1; k < tags.size; k++)
    {
        if (!read_arg(p_data, p_size, at, tags.bytes[k], m))
        {
            return false;
        }
    }
    r_message = m;
    return true;
}

bool is_bundle(uint8_t* p_data, int p_size)
{
    return p_size >= 16 && p_data[0] == 35 && p_data[1] == 98 && p_data[2] == 117 && p_data[3] == 110 &&
           p_data[4] == 100 && p_data[5] == 108 && p_data[6] == 101 && p_data[7] == 0;
}

static const int MAX_DEPTH = 8;

// A message or a #bundle, nested bundles flattened; malformed elements are skipped.
// Returns how many messages were written to r_messages, at most p_max.
public int osc_decode_packet(uint8_t* p_data, int p_size, Message* r_messages, int p_max)
{
    int starts[MAX_DEPTH];
    int ends[MAX_DEPTH];
    int depth = 1;
    int count = 0;
    starts[0] = 0;
    ends[0] = p_size;
    if (!is_bundle(p_data, p_size))
    {
        Message m;
        if (p_max > 0 && osc_decode(p_data, p_size, m))
        {
            r_messages[0] = m;
            return 1;
        }
        return 0;
    }
    starts[0] = 16;
    while (depth > 0)
    {
        int level = depth - 1;
        int at = starts[level];
        uint32_t n;
        if (!read_u32(p_data, ends[level], at, n) || at + int(n) > ends[level])
        {
            depth -= 1;
            continue;
        }
        starts[level] = at + int(n);
        uint8_t* element = p_data + at;
        if (is_bundle(element, int(n)) && depth < MAX_DEPTH)
        {
            starts[depth] = at + 16;
            ends[depth] = at + int(n);
            depth += 1;
            continue;
        }
        Message m;
        if (count < p_max && osc_decode(element, int(n), m))
        {
            r_messages[count] = m;
            count += 1;
        }
    }
    return count;
}

// Bytes written, or 0 when the buffer is too small.
public int osc_bundle(Message* p_messages, int p_count, uint8_t* r_out, int p_cap)
{
    Writer w = { r_out, p_cap, 0, false };
    put_text(w, text_of("#bundle"));
    put_u32(w, 0);
    put_u32(w, 0);
    for (int k = 0; k < p_count; k++)
    {
        int length_at = w.at;
        put_u32(w, 0);
        int start = w.at;
        put_message(w, p_messages[k]);
        if (w.full)
        {
            return 0;
        }
        uint32_t n = uint32_t(w.at - start);
        r_out[length_at] = uint8_t(n >> 24);
        r_out[length_at + 1] = uint8_t(n >> 16);
        r_out[length_at + 2] = uint8_t(n >> 8);
        r_out[length_at + 3] = uint8_t(n);
    }
    return w.full ? 0 : w.at;
}
