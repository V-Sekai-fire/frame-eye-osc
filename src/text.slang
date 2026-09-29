// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Fixed-size byte text: addresses, paths and messages, always NUL-terminated.
module text;

import libc;

public static const int TEXT_SIZE = 256;

public struct Text
{
    public uint8_t bytes[TEXT_SIZE];
    public int size;
};

public Text text_empty()
{
    Text t;
    for (int k = 0; k < TEXT_SIZE; k++)
    {
        t.bytes[k] = 0;
    }
    t.size = 0;
    return t;
}

// False when the byte did not fit; the text keeps what fitted.
public bool text_push(inout Text r_text, uint8_t p_byte)
{
    if (r_text.size + 1 >= TEXT_SIZE)
    {
        return false;
    }
    r_text.bytes[r_text.size] = p_byte;
    r_text.size += 1;
    r_text.bytes[r_text.size] = 0;
    return true;
}

public bool text_add(inout Text r_text, NativeString p_literal)
{
    uint8_t* bytes = (uint8_t*)p_literal.getBuffer();
    int n = p_literal.getLength();
    for (int k = 0; k < n; k++)
    {
        if (!text_push(r_text, bytes[k]))
        {
            return false;
        }
    }
    return true;
}

// Appends a NUL-terminated byte string.
public bool text_add_bytes(inout Text r_text, uint8_t* p_bytes)
{
    for (int k = 0; p_bytes[k] != 0; k++)
    {
        if (!text_push(r_text, p_bytes[k]))
        {
            return false;
        }
    }
    return true;
}

public bool text_add_text(inout Text r_text, Text p_other)
{
    for (int k = 0; k < p_other.size; k++)
    {
        if (!text_push(r_text, p_other.bytes[k]))
        {
            return false;
        }
    }
    return true;
}

public bool text_add_int(inout Text r_text, int64_t p_value)
{
    uint8_t digits[24];
    int n = 0;
    uint64_t v = uint64_t(p_value < 0 ? -p_value : p_value);
    if (p_value < 0 && !text_push(r_text, 45))
    {
        return false;
    }
    if (v == 0)
    {
        return text_push(r_text, 48);
    }
    while (v > 0)
    {
        digits[n] = uint8_t(48 + int(v % 10));
        v = v / 10;
        n += 1;
    }
    for (int k = n - 1; k >= 0; k--)
    {
        if (!text_push(r_text, digits[k]))
        {
            return false;
        }
    }
    return true;
}

public Text text_of(NativeString p_literal)
{
    Text t = text_empty();
    text_add(t, p_literal);
    return t;
}

public bool text_equals(Text p_text, NativeString p_literal)
{
    uint8_t* bytes = (uint8_t*)p_literal.getBuffer();
    int n = p_literal.getLength();
    if (p_text.size != n)
    {
        return false;
    }
    for (int k = 0; k < n; k++)
    {
        if (p_text.bytes[k] != bytes[k])
        {
            return false;
        }
    }
    return true;
}

public bool text_same(Text p_a, Text p_b)
{
    if (p_a.size != p_b.size)
    {
        return false;
    }
    for (int k = 0; k < p_a.size; k++)
    {
        if (p_a.bytes[k] != p_b.bytes[k])
        {
            return false;
        }
    }
    return true;
}

public bool text_starts_with(Text p_text, int p_from, NativeString p_prefix)
{
    uint8_t* bytes = (uint8_t*)p_prefix.getBuffer();
    int n = p_prefix.getLength();
    if (p_from + n > p_text.size)
    {
        return false;
    }
    for (int k = 0; k < n; k++)
    {
        if (p_text.bytes[p_from + k] != bytes[k])
        {
            return false;
        }
    }
    return true;
}

public bool text_ends_with(Text p_text, NativeString p_suffix)
{
    int n = p_suffix.getLength();
    if (n > p_text.size)
    {
        return false;
    }
    return text_starts_with(p_text, p_text.size - n, p_suffix);
}

// The bytes from p_from to p_to, as a new text.
public Text text_slice(Text p_text, int p_from, int p_to)
{
    Text t = text_empty();
    for (int k = p_from; k < p_to && k < p_text.size; k++)
    {
        text_push(t, p_text.bytes[k]);
    }
    return t;
}

public Text text_from_bytes(uint8_t* p_bytes)
{
    Text t = text_empty();
    text_add_bytes(t, p_bytes);
    return t;
}

public void text_write(int p_fd, Text p_text)
{
    IoVec v;
    v.base = &p_text.bytes[0];
    v.size = uint64_t(p_text.size);
    writev(p_fd, &v, 1);
}

// Writes one line to stderr.
public void log_line(Text p_text)
{
    Text line = p_text;
    text_push(line, 10);
    text_write(2, line);
}
