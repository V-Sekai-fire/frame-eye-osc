// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 konsti219
// SPDX-License-Identifier: MIT
// The eye server's shared memory: version 4 of its layout, mapped read-write because
// reading takes the server's own mutex.
module eye_server;

import kernels;
import libc;
import text;

public static const uint32_t SHM_VERSION = 4;
public static const int SHM_SIZE = 0x4f21a;
public static const int RECORD_OFFSET = 0x152;
public static const int RECORD_SIZE = 0xebc;
static const int MUTEX_OFFSET = 0x08;
static const int SEQUENCE_OFFSET = 0x38;
static const int REQUESTED_OFFSET = 0x3c;

public struct Sample
{
    public uint32_t producer_state;
    public double sample_time;
    public Vec3 gaze[2];
    public Vec3 gaze_covariance[2];
    public Vec3 fixation_point;
    public float openness[2];
};

public struct Source
{
    public uint8_t* map;
};

uint32_t read_u32(uint8_t* p_bytes, int p_offset)
{
    return uint32_t(p_bytes[p_offset]) | (uint32_t(p_bytes[p_offset + 1]) << 8) |
           (uint32_t(p_bytes[p_offset + 2]) << 16) | (uint32_t(p_bytes[p_offset + 3]) << 24);
}

void write_u32(uint8_t* p_bytes, int p_offset, uint32_t p_value)
{
    p_bytes[p_offset] = uint8_t(p_value);
    p_bytes[p_offset + 1] = uint8_t(p_value >> 8);
    p_bytes[p_offset + 2] = uint8_t(p_value >> 16);
    p_bytes[p_offset + 3] = uint8_t(p_value >> 24);
}

float read_f32(uint8_t* p_bytes, int p_offset)
{
    return asfloat(read_u32(p_bytes, p_offset));
}

Vec3 read_vec3(uint8_t* p_bytes, int p_offset)
{
    Vec3 v;
    v.x = read_f32(p_bytes, p_offset);
    v.y = read_f32(p_bytes, p_offset + 4);
    v.z = read_f32(p_bytes, p_offset + 8);
    return v;
}

// Decodes a raw record of RECORD_SIZE bytes, as it sits at RECORD_OFFSET.
public export __extern_cpp Sample fe_decode(uint8_t* p_record)
{
    Sample s;
    s.producer_state = read_u32(p_record, 0x00);
    s.sample_time = asdouble(read_u32(p_record, 0x05), read_u32(p_record, 0x09));
    s.gaze[0] = read_vec3(p_record, 0x0d);
    s.gaze[1] = read_vec3(p_record, 0x19);
    s.gaze_covariance[0] = read_vec3(p_record, 0x25);
    s.gaze_covariance[1] = read_vec3(p_record, 0x31);
    s.fixation_point = read_vec3(p_record, 0x3d);
    s.openness[0] = read_f32(p_record, 0x79);
    s.openness[1] = read_f32(p_record, 0x7d);
    return s;
}

Text failure(Text p_path, NativeString p_what)
{
    Text t = p_path;
    text_add(t, ": ");
    text_add(t, p_what);
    return t;
}

Text failure_errno(Text p_path)
{
    Text t = failure(p_path, "errno ");
    text_add_int(t, errno_value());
    return t;
}

// Maps the eye server's shared memory; false with a message in r_error on failure.
public bool eye_open(Text p_path, out Source r_source, out Text r_error)
{
    r_source.map = (uint8_t*)0;
    r_error = text_empty();
    int fd = open(&p_path.bytes[0], O_RDWR | O_CLOEXEC, 0);
    if (fd < 0)
    {
        r_error = failure_errno(p_path);
        return false;
    }
    if (lseek(fd, 0, SEEK_END) < SHM_SIZE)
    {
        close(fd);
        r_error = failure(p_path, "shared memory is too small");
        return false;
    }
    uint8_t* map = mmap((uint8_t*)0, uint64_t(SHM_SIZE), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if ((int64_t)map == -1)
    {
        r_error = failure_errno(p_path);
        return false;
    }
    uint32_t version = read_u32(map, 0);
    if (version != SHM_VERSION)
    {
        munmap(map, uint64_t(SHM_SIZE));
        r_error = text_of("unsupported eye shared-memory version ");
        text_add_int(r_error, int64_t(version));
        text_add(r_error, "; expected 4");
        return false;
    }
    if (read_u32(map, 4) != 1)
    {
        munmap(map, uint64_t(SHM_SIZE));
        r_error = text_of("eye shared memory is not initialized");
        return false;
    }
    r_source.map = map;
    return true;
}

int lock(Source p_source)
{
    uint8_t* mutex = p_source.map + MUTEX_OFFSET;
    int rc = pthread_mutex_lock(mutex);
    if (rc != EOWNERDEAD)
    {
        return rc;
    }
    rc = pthread_mutex_consistent(mutex);
    if (rc != 0)
    {
        pthread_mutex_unlock(mutex);
    }
    return rc;
}

void unlock(Source p_source)
{
    pthread_mutex_unlock(p_source.map + MUTEX_OFFSET);
}

// 1 when a new record was read into r_sample, 0 on timeout, -1 on error (message in r_error).
// The sequence is polled every millisecond under the server's mutex.
public int eye_next(Source p_source, int p_timeout_ms, out Sample r_sample, out Text r_error)
{
    r_sample = fe_decode(p_source.map + RECORD_OFFSET);
    r_error = text_empty();
    if (lock(p_source) != 0)
    {
        r_error = text_of("eye mutex could not be taken");
        return -1;
    }
    uint32_t seen = read_u32(p_source.map, SEQUENCE_OFFSET);
    write_u32(p_source.map, REQUESTED_OFFSET, 1);
    unlock(p_source);
    for (int waited = 0; waited <= p_timeout_ms; waited++)
    {
        if (lock(p_source) != 0)
        {
            r_error = text_of("eye mutex could not be taken");
            return -1;
        }
        bool fresh = read_u32(p_source.map, SEQUENCE_OFFSET) != seen;
        if (fresh)
        {
            r_sample = fe_decode(p_source.map + RECORD_OFFSET);
        }
        unlock(p_source);
        if (fresh)
        {
            return 1;
        }
        usleep(1000);
    }
    return 0;
}

public void eye_close(inout Source r_source)
{
    if ((int64_t)r_source.map == 0)
    {
        return;
    }
    munmap(r_source.map, uint64_t(SHM_SIZE));
    r_source.map = (uint8_t*)0;
}
