// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 konsti219
// SPDX-License-Identifier: MIT
// frameeyeosc: reads the eye server's shared memory and sends OSC.
module main;

import bridge;
import config;
import eye_server;
import kernels;
import libc;
import osc;
import params;
import text;

// struct addrinfo on 64-bit Linux.
struct AddrInfo
{
    int flags;
    int family;
    int socktype;
    int protocol;
    uint32_t addrlen;
    SockAddrIn* addr;
    uint8_t* canonname;
    AddrInfo* next;
};

__extern_cpp int getaddrinfo(uint8_t* p_node, uint8_t* p_service, AddrInfo* p_hints, AddrInfo** r_result);
__extern_cpp void freeaddrinfo(AddrInfo* p_result);

struct Options
{
    Text target;
    Text prefix;
    Text source;
    Text gains;
    Text home;
    bool anime;
    bool heuristics;
    bool native;
    int learn_port;
    float lost_at;
};

int usage()
{
    log_line(text_of("usage: frameeyeosc [--target HOST:PORT] [--prefix /FT] [--source PATH]"));
    log_line(text_of("                   [--style reference|anime] [--no-heuristics] [--native]"));
    log_line(text_of("                   [--learn-port PORT] [--gains FILE] [--lost-at COV]"));
    return 2;
}

bool parse(int p_argc, uint8_t** p_argv, out Options r_options)
{
    r_options.target = text_of("127.0.0.1:9000");
    r_options.prefix = text_of("/FT");
    r_options.source = text_of("/dev/shm/eye-server.mmap");
    r_options.gains = text_empty();
    r_options.home = text_empty();
    r_options.anime = false;
    r_options.heuristics = true;
    r_options.native = false;
    r_options.learn_port = 0;
    r_options.lost_at = 0.02;
    for (int i = 1; i < p_argc; i++)
    {
        Text a = text_from_bytes(p_argv[i]);
        if (text_equals(a, "--no-heuristics"))
        {
            r_options.heuristics = false;
            continue;
        }
        if (text_equals(a, "--native"))
        {
            r_options.native = true;
            continue;
        }
        if (i + 1 >= p_argc)
        {
            return false;
        }
        i += 1;
        Text v = text_from_bytes(p_argv[i]);
        int at = 0;
        if (text_equals(a, "--target"))
        {
            r_options.target = v;
        }
        else if (text_equals(a, "--prefix"))
        {
            r_options.prefix = v;
        }
        else if (text_equals(a, "--source"))
        {
            r_options.source = v;
        }
        else if (text_equals(a, "--style") && (text_equals(v, "reference") || text_equals(v, "anime")))
        {
            r_options.anime = text_equals(v, "anime");
        }
        else if (text_equals(a, "--learn-port"))
        {
            if (!parse_int(v, r_options.learn_port))
            {
                return false;
            }
        }
        else if (text_equals(a, "--gains"))
        {
            r_options.gains = v;
        }
        else if (text_equals(a, "--lost-at"))
        {
            if (!parse_float(v, at, r_options.lost_at))
            {
                return false;
            }
        }
        else
        {
            return false;
        }
    }
    Text p = r_options.prefix;
    bool only_slashes = true;
    for (int k = 0; k < p.size; k++)
    {
        only_slashes = only_slashes && p.bytes[k] == 47;
    }
    return p.size > 0 && p.bytes[0] == 47 && !only_slashes;
}

int connect_udp(Text p_target)
{
    int colon = -1;
    for (int k = 0; k < p_target.size; k++)
    {
        if (p_target.bytes[k] == 58)
        {
            colon = k;
        }
    }
    if (colon < 0)
    {
        return -1;
    }
    Text host = text_slice(p_target, 0, colon);
    Text port = text_slice(p_target, colon + 1, p_target.size);
    AddrInfo hints = { 0, AF_INET, SOCK_DGRAM, 0, 0, (SockAddrIn*)0, (uint8_t*)0, (AddrInfo*)0 };
    AddrInfo* result = (AddrInfo*)0;
    if (getaddrinfo(&host.bytes[0], &port.bytes[0], &hints, &result) != 0)
    {
        return -1;
    }
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
    {
        freeaddrinfo(result);
        return -1;
    }
    if (connect(fd, result.addr, result.addrlen) != 0)
    {
        close(fd);
        freeaddrinfo(result);
        return -1;
    }
    freeaddrinfo(result);
    return fd;
}

uint16_t network_order(uint16_t p_port)
{
    return uint16_t(((p_port & 0xff) << 8) | (p_port >> 8));
}

int listen_udp(int p_port)
{
    int fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
    {
        return -1;
    }
    int one = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &one, 4);
    SockAddrIn address = { uint16_t(AF_INET), network_order(uint16_t(p_port)), 0, 0, 0 };
    if (bind(fd, &address, 16) != 0)
    {
        close(fd);
        return -1;
    }
    return fd;
}

// Encodes into p_scratch, which must hold OSC_PACKET bytes.
void send_message(int p_fd, Message p_message, uint8_t* p_scratch)
{
    int n = osc_encode(p_message, p_scratch, OSC_PACKET);
    if (n == 0)
    {
        return;
    }
    send(p_fd, p_scratch, uint64_t(n), 0);
}

int64_t now_ms()
{
    TimeSpec t = { 0, 0 };
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.seconds * 1000 + t.nanoseconds / 1000000;
}

Text calib_path(Text p_home)
{
    Text dir = p_home.size > 0 ? p_home : text_of(".");
    text_add(dir, "/.config/frameeyeosc");
    mkdir(&dir.bytes[0], 493);
    text_add(dir, "/calib.txt");
    return dir;
}

// The anime style: calibrated, blink events, expressive filtered gaze, avatar-matched parameters.
struct Driver
{
    Options options;
    Gains gains;
    Text prefix;
    int entry_count;
    Entry entries[PARAMS_MAX];
    Arg last[PARAMS_MAX];
    bool has_last[PARAMS_MAX];
    Learned learned;
    int64_t changed_at;
    FrameCalib calib;
    Tuning tuning;
    StyleState state;
    OneEuro pitch;
    OneEuro yaw;
    double last_time;
    int64_t refreshed_at;
    int64_t saved_at;
};

void use_plan(inout Driver r_driver, int p_count)
{
    r_driver.entry_count = p_count;
    for (int k = 0; k < PARAMS_MAX; k++)
    {
        r_driver.has_last[k] = false;
    }
}

Calib calib_default()
{
    Calib c = { 0.0, 0.75, 1.0 };
    return c;
}

EyeState eye_state_default()
{
    EyeState s = { OPENED, 0.0, 1.0, 0.0 };
    return s;
}

void driver_init(inout Driver r_driver, Options p_options, Gains p_gains)
{
    r_driver.options = p_options;
    r_driver.gains = p_gains;
    // "/FT" -> "FT/", the form the fallback plan puts after /avatar/parameters/.
    r_driver.prefix = text_slice(p_options.prefix, 1, p_options.prefix.size);
    if (r_driver.prefix.size > 0 && r_driver.prefix.bytes[r_driver.prefix.size - 1] != 47)
    {
        text_push(r_driver.prefix, 47);
    }
    use_plan(r_driver, fallback_plan(r_driver.prefix, &r_driver.entries[0], PARAMS_MAX));
    learned_clear(r_driver.learned);
    r_driver.changed_at = 0;
    r_driver.calib.left = calib_default();
    r_driver.calib.right = calib_default();
    calib_load(calib_path(p_options.home), r_driver.calib);
    Tuning k = { 0.35, 0.55, 60.0, 140.0, 0.8, 250.0, 400.0, 0.2, 0.25 };
    r_driver.tuning = k;
    r_driver.state.left = eye_state_default();
    r_driver.state.right = eye_state_default();
    r_driver.pitch.primed = false;
    r_driver.yaw.primed = false;
    r_driver.last_time = 0.0;
    r_driver.refreshed_at = 0;
    r_driver.saved_at = 0;
}

void driver_learn(inout Driver r_driver, Message p_message, int64_t p_now)
{
    if (observe(r_driver.learned, p_message))
    {
        r_driver.changed_at = p_now;
    }
}

// Adopts a learned parameter list once it has been quiet for 300 ms.
void driver_adopt(inout Driver r_driver, int64_t p_now)
{
    if (r_driver.changed_at == 0 || p_now - r_driver.changed_at < 300)
    {
        return;
    }
    r_driver.changed_at = 0;
    int n = r_driver.learned.count == 0
                ? fallback_plan(r_driver.prefix, &r_driver.entries[0], PARAMS_MAX)
                : fe_plan(&r_driver.learned.params[0], r_driver.learned.count, &r_driver.entries[0], PARAMS_MAX);
    use_plan(r_driver, n);
    Text t = text_of("avatar ");
    text_add_text(t, r_driver.learned.avatar);
    text_add(t, ": ");
    text_add_int(t, n);
    text_add(t, " parameters driven of ");
    text_add_int(t, r_driver.learned.count);
    text_add(t, " seen");
    log_line(t);
}

void driver_send(inout Driver r_driver, Sample p_sample, int64_t p_now, int p_fd, uint8_t* p_scratch)
{
    float dt_s = r_driver.last_time == 0.0 ? 0.011 : float(p_sample.sample_time - r_driver.last_time);
    dt_s = clamp(dt_s, 0.0, 0.1);
    r_driver.last_time = p_sample.sample_time;

    Vec3 center = fe_center_direction(p_sample.gaze[0], p_sample.gaze[1]);
    float pitch;
    float yaw;
    fe_pitch_yaw_degrees(center, pitch, yaw);
    r_driver.pitch = fe_one_euro_step(r_driver.pitch, pitch, dt_s);
    r_driver.yaw = fe_one_euro_step(r_driver.yaw, yaw, dt_s);
    float gx = fe_expressive(1.8, 30.0, 1.5, r_driver.yaw.x) / 45.0;
    float gy = -fe_expressive(1.8, 30.0, 1.5, r_driver.pitch.x) / 45.0;

    FrameIn input;
    input.left.openness = p_sample.openness[0];
    input.left.x = gx;
    input.left.y = gy;
    input.right.openness = p_sample.openness[1];
    input.right.x = gx;
    input.right.y = gy;
    r_driver.calib = fe_frame_calib_step(r_driver.calib, input);

    float rl = fe_relative(r_driver.calib.left, input.left.openness);
    float rr = fe_relative(r_driver.calib.right, input.right.openness);
    bool lost_l = fe_eye_lost(p_sample.gaze_covariance[0], r_driver.options.lost_at);
    bool lost_r = fe_eye_lost(p_sample.gaze_covariance[1], r_driver.options.lost_at);
    fe_wink_gate(lost_l, lost_r, rl, rr);
    r_driver.state = fe_style_step(r_driver.tuning, dt_s * 1000.0, r_driver.state, rl, rr);

    bool h = r_driver.options.heuristics;
    FrameOut output = fe_frame(r_driver.gains, h, r_driver.calib, input);
    output.left = fe_style_eye(r_driver.tuning, r_driver.gains, h, r_driver.calib.left, input.left.openness,
                               r_driver.state.left, output.left);
    output.right = fe_style_eye(r_driver.tuning, r_driver.gains, h, r_driver.calib.right, input.right.openness,
                                r_driver.state.right, output.right);

    bool refresh = p_now - r_driver.refreshed_at >= 1000;
    if (refresh)
    {
        r_driver.refreshed_at = p_now;
    }
    if (p_now - r_driver.saved_at >= 60000)
    {
        r_driver.saved_at = p_now;
        calib_save(calib_path(r_driver.options.home), r_driver.calib);
    }
    for (int k = 0; k < r_driver.entry_count; k++)
    {
        Message m = message_for(r_driver.entries[k], output);
        if (!refresh && r_driver.has_last[k] && osc_arg_equal(r_driver.last[k], m.args[0]))
        {
            continue;
        }
        r_driver.last[k] = m.args[0];
        r_driver.has_last[k] = true;
        send_message(p_fd, m, p_scratch);
    }
    if (!r_driver.options.native)
    {
        return;
    }
    Message native = osc_message(text_of("/tracking/eye/CenterPitchYaw"));
    osc_add_float(native, -gy * 45.0);
    osc_add_float(native, gx * 45.0);
    send_message(p_fd, native, p_scratch);
}

static const int LEARN_BATCH = 64;

void drain_learning(int p_fd, inout Driver r_driver, uint8_t* p_scratch, Message* p_messages)
{
    for (;;)
    {
        int64_t n = recv(p_fd, p_scratch, uint64_t(OSC_PACKET), MSG_DONTWAIT);
        if (n <= 0)
        {
            return;
        }
        int64_t now = now_ms();
        int count = osc_decode_packet(p_scratch, int(n), p_messages, LEARN_BATCH);
        for (int k = 0; k < count; k++)
        {
            driver_learn(r_driver, p_messages[k], now);
        }
    }
}

// HOME from the environment block.
Text home_of(uint8_t** p_envp)
{
    for (int k = 0; (int64_t)p_envp[k] != 0; k++)
    {
        Text entry = text_from_bytes(p_envp[k]);
        if (text_starts_with(entry, 0, "HOME="))
        {
            return text_slice(entry, 5, entry.size);
        }
    }
    return text_empty();
}

__global Driver g_driver;
__global uint8_t g_scratch[OSC_PACKET];
__global Message g_learned_batch[LEARN_BATCH];

public export __extern_cpp int main(int argc, uint8_t** argv, uint8_t** envp)
{
    Options o;
    if (!parse(argc, argv, o))
    {
        return usage();
    }
    o.home = home_of(envp);
    Gains gains = gains_default();
    Text error;
    if (o.gains.size > 0 && !gains_load(o.gains, gains, error))
    {
        log_line(error);
        return 1;
    }
    int fd = connect_udp(o.target);
    if (fd < 0)
    {
        Text t = text_of("--target ");
        text_add_text(t, o.target);
        text_add(t, " did not resolve to an address");
        log_line(t);
        return 1;
    }
    int learn_fd = o.learn_port > 0 ? listen_udp(o.learn_port) : -1;
    if (o.learn_port > 0 && learn_fd < 0)
    {
        Text t = text_of("cannot listen on UDP ");
        text_add_int(t, o.learn_port);
        log_line(t);
        return 1;
    }
    Source eyes;
    if (!eye_open(o.source, eyes, error))
    {
        log_line(error);
        return 1;
    }
    Text hello = text_of("Reading ");
    text_add_text(hello, o.source);
    text_add(hello, " and sending OSC to ");
    text_add_text(hello, o.target);
    if (o.anime)
    {
        text_add(hello, " (anime style)");
    }
    else
    {
        text_add(hello, " (reference style)");
    }
    log_line(hello);
    driver_init(g_driver, o, gains);
    bool active = false;
    Message reference[REFERENCE_MESSAGES];
    for (;;)
    {
        Sample s;
        int r = eye_next(eyes, o.anime ? 50 : 1000, s, error);
        if (r < 0)
        {
            log_line(error);
            eye_close(eyes);
            return 1;
        }
        int64_t now = now_ms();
        if (learn_fd >= 0)
        {
            drain_learning(learn_fd, g_driver, &g_scratch[0], &g_learned_batch[0]);
            driver_adopt(g_driver, now);
        }
        bool valid = r == 1 && fe_sample_valid(s);
        if (valid && o.anime)
        {
            driver_send(g_driver, s, now, fd, &g_scratch[0]);
            continue;
        }
        if (valid)
        {
            fe_reference_messages(s, o.prefix, &reference[0]);
            for (int k = 0; k < REFERENCE_MESSAGES; k++)
            {
                send_message(fd, reference[k], &g_scratch[0]);
            }
            active = true;
            continue;
        }
        if (!active)
        {
            continue;
        }
        send_message(fd, fe_tracking_active(o.prefix, false), &g_scratch[0]);
        active = false;
    }
}
