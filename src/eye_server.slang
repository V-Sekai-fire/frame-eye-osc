// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 konsti219
// SPDX-FileCopyrightText: 2026 sasaken1102r
// SPDX-License-Identifier: MIT
// The eye server's shared memory, versions 4 and 5 of its layout, mapped read-write because
// reading takes the server's own mutex. Version 5 (SteamOS 0.4.3 on) inserts the 5-byte
// "Track Dominant Eye Only" setting at 0x152, which moves the sample record 5 bytes on. The
// layouts and the request-in-the-same-lock rule follow sasaken1102r's frameeyeosc fork.
module eye_server;

import kernels;
import libc;
import text;

static const int SHM_SIZE_V4 = 0x4f21a;
static const int SHM_SIZE_V5 = 0x4f21f;
public static const int RECORD_SIZE = 0xebc;
static const int MUTEX_OFFSET = 0x08;
static const int SEQUENCE_OFFSET = 0x38;
static const int REQUESTED_OFFSET = 0x3c;
static const int DOMINANT_OFFSET = 0x152;
// A larger jump in the sequence (or one back) is the server starting over, not samples missed.
static const uint32_t MAX_MISSED_JUMP = 900;

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
    public int size;
    public int record;
    // Where the dominant-eye setting sits, -1 in a version without it.
    public int dominant_at;
    public uint32_t version;
    // The sequence of the last record taken (before the first, the one there when first asked).
    public uint32_t last_sequence;
    public bool has_last;
    // Samples the server published that were not read, since the caller last cleared it.
    public uint32_t missed;
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

// The size, record offset and dominant-eye offset of a layout version; false for one not known.
bool layout_of(uint32_t p_version, out int r_size, out int r_record, out int r_dominant_at)
{
    r_size = SHM_SIZE_V4;
    r_record = 0x152;
    r_dominant_at = -1;
    if (p_version == 4)
    {
        return true;
    }
    if (p_version == 5)
    {
        r_size = SHM_SIZE_V5;
        r_record = 0x157;
        r_dominant_at = DOMINANT_OFFSET;
        return true;
    }
    return false;
}

// Decodes a raw record of RECORD_SIZE bytes, the same in every version.
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

// The "Track Dominant Eye Only" setting's 5 bytes, a flag then the eye as a little-endian int32:
// -1 off, 0 left, 1 right, and -2 for anything else (a read torn by the setting changing, or a
// meaning that has changed).
public export __extern_cpp int fe_dominant_eye(uint8_t* p_bytes)
{
    int eye = int(read_u32(p_bytes, 1));
    if (p_bytes[0] == 0 && eye >= -1 && eye <= 1)
    {
        return -1;
    }
    if (p_bytes[0] == 1 && (eye == 0 || eye == 1))
    {
        return eye;
    }
    return -2;
}

// The setting as the source holds it now: -1 also for a version without it. Only read, without the
// lock (a client sets it, not the server), so it is read twice and must say the same both times.
public int eye_dominant(Source p_source)
{
    if (p_source.dominant_at < 0)
    {
        return -1;
    }
    uint8_t first[5];
    uint8_t second[5];
    for (int k = 0; k < 5; k++)
    {
        first[k] = p_source.map[p_source.dominant_at + k];
    }
    for (int k = 0; k < 5; k++)
    {
        second[k] = p_source.map[p_source.dominant_at + k];
    }
    for (int k = 0; k < 5; k++)
    {
        if (first[k] != second[k])
        {
            return -2;
        }
    }
    return fe_dominant_eye(&first[0]);
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

Text unsupported(uint32_t p_version)
{
    Text t = text_of("unsupported eye shared-memory version ");
    text_add_int(t, int64_t(p_version));
    text_add(t, "; supported: 4, 5");
    return t;
}

// Maps the eye server's shared memory; false with a message in r_error on failure. The version is
// read before the file is mapped, so a version this does not know is never written to.
public bool eye_open(Text p_path, out Source r_source, out Text r_error)
{
    r_source.map = (uint8_t*)0;
    r_source.size = 0;
    r_source.record = 0;
    r_source.dominant_at = -1;
    r_source.version = 0;
    r_source.last_sequence = 0;
    r_source.has_last = false;
    r_source.missed = 0;
    r_error = text_empty();
    int fd = open(&p_path.bytes[0], O_RDWR | O_CLOEXEC, 0);
    if (fd < 0)
    {
        r_error = failure_errno(p_path);
        return false;
    }
    uint8_t head[4] = { 0, 0, 0, 0 };
    if (read(fd, &head[0], 4) != 4)
    {
        close(fd);
        r_error = failure(p_path, "shared memory is too small");
        return false;
    }
    uint32_t version = read_u32(&head[0], 0);
    int size;
    int record;
    int dominant_at;
    if (!layout_of(version, size, record, dominant_at))
    {
        close(fd);
        r_error = unsupported(version);
        return false;
    }
    if (lseek(fd, 0, SEEK_END) < size)
    {
        close(fd);
        r_error = failure(p_path, "shared memory is too small");
        return false;
    }
    uint8_t* map = mmap((uint8_t*)0, uint64_t(size), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    close(fd);
    if ((int64_t)map == -1)
    {
        r_error = failure_errno(p_path);
        return false;
    }
    if (read_u32(map, 0) != version)
    {
        // Rewritten by a restarting server between the read and the mapping.
        munmap(map, uint64_t(size));
        r_error = failure(p_path, "the shared-memory version changed while opening it");
        return false;
    }
    if (read_u32(map, 4) != 1)
    {
        munmap(map, uint64_t(size));
        r_error = text_of("eye shared memory is not initialized");
        return false;
    }
    r_source.map = map;
    r_source.size = size;
    r_source.record = record;
    r_source.dominant_at = dominant_at;
    r_source.version = version;
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

// Copies out the record published as p_sequence and requests the next sample, with the mutex held.
// The server publishes a frame only if a sample was requested by then, and clears the request with
// it; requesting the next one only when the next call started lost every other frame (90 -> 45 a
// second) whenever processing and sending took longer than a frame.
Sample take(inout Source r_source, uint32_t p_sequence)
{
    Sample s = fe_decode(r_source.map + r_source.record);
    write_u32(r_source.map, REQUESTED_OFFSET, 1);
    if (r_source.has_last)
    {
        uint32_t jump = p_sequence - r_source.last_sequence;
        if (jump >= 2 && jump <= MAX_MISSED_JUMP)
        {
            r_source.missed += jump - 1;
        }
    }
    r_source.last_sequence = p_sequence;
    r_source.has_last = true;
    return s;
}

// 1 when a new record was read into r_sample, 0 on timeout, -1 on error (message in r_error); -1
// also when the server rewrote the file as another version, which the caller reopens. A sample
// published while the last one was processed is read at once; otherwise the sequence is polled
// every millisecond under the server's mutex. The first call after opening waits for a new sample
// rather than return the one already there.
public int eye_next(inout Source r_source, int p_timeout_ms, out Sample r_sample, out Text r_error)
{
    r_sample = fe_decode(r_source.map + r_source.record);
    r_error = text_empty();
    if (read_u32(r_source.map, 0) != r_source.version)
    {
        r_error = text_of("the eye shared memory was rewritten as another version");
        return -1;
    }
    if (lock(r_source) != 0)
    {
        r_error = text_of("eye mutex could not be taken");
        return -1;
    }
    uint32_t sequence = read_u32(r_source.map, SEQUENCE_OFFSET);
    if (!r_source.has_last)
    {
        r_source.last_sequence = sequence;
        r_source.has_last = true;
    }
    if (sequence != r_source.last_sequence)
    {
        r_sample = take(r_source, sequence);
        unlock(r_source);
        return 1;
    }
    write_u32(r_source.map, REQUESTED_OFFSET, 1);
    unlock(r_source);
    for (int waited = 0; waited < p_timeout_ms; waited++)
    {
        usleep(1000);
        if (lock(r_source) != 0)
        {
            r_error = text_of("eye mutex could not be taken");
            return -1;
        }
        sequence = read_u32(r_source.map, SEQUENCE_OFFSET);
        bool fresh = sequence != r_source.last_sequence;
        if (fresh)
        {
            r_sample = take(r_source, sequence);
        }
        unlock(r_source);
        if (fresh)
        {
            return 1;
        }
    }
    return 0;
}

public void eye_close(inout Source r_source)
{
    if ((int64_t)r_source.map == 0)
    {
        return;
    }
    munmap(r_source.map, uint64_t(r_source.size));
    r_source.map = (uint8_t*)0;
}
