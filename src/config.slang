// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-License-Identifier: MIT
// Numbers as text, and the calibration and gains files: "name value" per line.
module config;

import kernels;
import libc;
import text;

// Parses [-]digits[.digits] from p_text starting at r_at; false when there is no number.
public bool parse_float(Text p_text, inout int r_at, out float r_value)
{
    r_value = 0.0;
    int at = r_at;
    while (at < p_text.size && (p_text.bytes[at] == 32 || p_text.bytes[at] == 9))
    {
        at += 1;
    }
    bool negative = at < p_text.size && p_text.bytes[at] == 45;
    if (negative)
    {
        at += 1;
    }
    int digits = 0;
    double v = 0.0;
    while (at < p_text.size && p_text.bytes[at] >= 48 && p_text.bytes[at] <= 57)
    {
        v = v * 10.0 + double(p_text.bytes[at] - 48);
        at += 1;
        digits += 1;
    }
    if (at < p_text.size && p_text.bytes[at] == 46)
    {
        at += 1;
        double scale = 0.1;
        while (at < p_text.size && p_text.bytes[at] >= 48 && p_text.bytes[at] <= 57)
        {
            v += double(p_text.bytes[at] - 48) * scale;
            scale *= 0.1;
            at += 1;
            digits += 1;
        }
    }
    if (digits == 0)
    {
        return false;
    }
    r_value = float(negative ? -v : v);
    r_at = at;
    return true;
}

public bool parse_int(Text p_text, out int r_value)
{
    r_value = 0;
    if (p_text.size == 0)
    {
        return false;
    }
    for (int k = 0; k < p_text.size; k++)
    {
        uint8_t c = p_text.bytes[k];
        if (c < 48 || c > 57)
        {
            return false;
        }
        r_value = r_value * 10 + int(c - 48);
    }
    return true;
}

// Six decimals, enough for a calibration level.
public void text_add_float(inout Text r_text, float p_value)
{
    float v = p_value;
    if (v < 0.0)
    {
        text_push(r_text, 45);
        v = -v;
    }
    int64_t scaled = int64_t(floor(double(v) * 1000000.0 + 0.5));
    text_add_int(r_text, scaled / 1000000);
    text_push(r_text, 46);
    int64_t fraction = scaled % 1000000;
    for (int64_t digit = 100000; digit > 0; digit /= 10)
    {
        text_push(r_text, uint8_t(48 + int((fraction / digit) % 10)));
    }
}

// Reads a whole small file into r_text; false when it cannot be opened.
public bool read_file(Text p_path, out Text r_text)
{
    r_text = text_empty();
    int fd = open(&p_path.bytes[0], O_RDONLY | O_CLOEXEC, 0);
    if (fd < 0)
    {
        return false;
    }
    int64_t n = read(fd, &r_text.bytes[0], uint64_t(TEXT_SIZE - 1));
    close(fd);
    if (n < 0)
    {
        return false;
    }
    r_text.size = int(n);
    r_text.bytes[r_text.size] = 0;
    return true;
}

public bool write_file(Text p_path, Text p_text)
{
    int fd = open(&p_path.bytes[0], O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 420);
    if (fd < 0)
    {
        return false;
    }
    text_write(fd, p_text);
    return close(fd) == 0;
}

// The next line of p_text from r_at, without its newline; false at the end.
bool next_line(Text p_text, inout int r_at, out Text r_line)
{
    r_line = text_empty();
    if (r_at >= p_text.size)
    {
        return false;
    }
    int end = r_at;
    while (end < p_text.size && p_text.bytes[end] != 10)
    {
        end += 1;
    }
    r_line = text_slice(p_text, r_at, end);
    r_at = end + 1;
    return true;
}

// Splits "name value" into the name and the index where the value starts.
bool split_word(Text p_line, out Text r_name, out int r_rest)
{
    int end = 0;
    while (end < p_line.size && p_line.bytes[end] != 32 && p_line.bytes[end] != 9)
    {
        end += 1;
    }
    r_name = text_slice(p_line, 0, end);
    r_rest = end;
    return end > 0;
}

// "left closed neutral wide" and "right closed neutral wide".
public bool calib_load(Text p_path, inout FrameCalib r_calib)
{
    Text file;
    if (!read_file(p_path, file))
    {
        return false;
    }
    FrameCalib c = r_calib;
    int at = 0;
    int seen = 0;
    Text line;
    while (next_line(file, at, line))
    {
        Text name;
        int rest;
        Calib e;
        if (!split_word(line, name, rest))
        {
            continue;
        }
        if (!parse_float(line, rest, e.closed) || !parse_float(line, rest, e.neutral) || !parse_float(line, rest, e.wide))
        {
            return false;
        }
        if (text_equals(name, "left"))
        {
            c.left = e;
            seen += 1;
        }
        else if (text_equals(name, "right"))
        {
            c.right = e;
            seen += 1;
        }
    }
    if (seen != 2)
    {
        return false;
    }
    r_calib = c;
    return true;
}

void add_calib_line(inout Text r_text, NativeString p_side, Calib p_c)
{
    text_add(r_text, p_side);
    text_push(r_text, 32);
    text_add_float(r_text, p_c.closed);
    text_push(r_text, 32);
    text_add_float(r_text, p_c.neutral);
    text_push(r_text, 32);
    text_add_float(r_text, p_c.wide);
    text_push(r_text, 10);
}

public bool calib_save(Text p_path, FrameCalib p_calib)
{
    Text t = text_empty();
    add_calib_line(t, "left", p_calib.left);
    add_calib_line(t, "right", p_calib.right);
    return write_file(p_path, t);
}

public Gains gains_default()
{
    Gains g = { 1.0, 0.6, 0.5, 0.3, 0.7, 0.8 };
    return g;
}

// An unknown name is an error; a missing one keeps its value.
public bool gains_load(Text p_path, inout Gains r_gains, out Text r_error)
{
    r_error = text_empty();
    Text file;
    if (!read_file(p_path, file))
    {
        r_error = p_path;
        text_add(r_error, ": cannot open");
        return false;
    }
    Gains g = r_gains;
    int at = 0;
    Text line;
    while (next_line(file, at, line))
    {
        Text name;
        int rest;
        float value;
        if (line.size == 0 || line.bytes[0] == 35 || !split_word(line, name, rest))
        {
            continue;
        }
        if (!parse_float(line, rest, value))
        {
            r_error = text_of("bad gain line: ");
            text_add_text(r_error, line);
            return false;
        }
        if (text_equals(name, "squint"))
        {
            g.squint = value;
        }
        else if (text_equals(name, "cheek_from_squint"))
        {
            g.cheek_from_squint = value;
        }
        else if (text_equals(name, "brow_down_from_squint"))
        {
            g.brow_down_from_squint = value;
        }
        else if (text_equals(name, "brow_pinch_from_squint"))
        {
            g.brow_pinch_from_squint = value;
        }
        else if (text_equals(name, "brow_inner_from_wide"))
        {
            g.brow_inner_from_wide = value;
        }
        else if (text_equals(name, "brow_outer_from_wide"))
        {
            g.brow_outer_from_wide = value;
        }
        else
        {
            r_error = text_of("unknown gain ");
            text_add_text(r_error, name);
            return false;
        }
    }
    r_gains = g;
    return true;
}
