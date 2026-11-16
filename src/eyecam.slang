// SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
// SPDX-FileCopyrightText: 2026 sasaken1102r
// SPDX-License-Identifier: MIT
// The eye cameras' per-eye values (lid, widen, squint, pupil) that tools/eyecam publishes in
// /run/user/1000/eyecam/live, version 1 of its 200-byte page, and how they replace the
// eye server's own openness. The page layout follows sasaken1102r's frameeyeosc fork.
module eyecam;
import kernels;

public static const int CAM_OK = 0;
public static const int CAM_SHORT = 1;
public static const int CAM_MAGIC = 2;
public static const int CAM_VERSION = 3;
public static const int CAM_STRUCT_SIZE = 4;
public static const int CAM_WRITING = 5;
public static const int CAM_IDLE = 6;

static const uint32_t PAGE_MAGIC = 0x4D435945;
static const uint32_t PAGE_VERSION = 1;
static const int PAGE_BYTES = 200;
static const int SEQ_AT = 24;
static const int LIVE_AT = 52;
static const int EYE_AT = 56;
static const int EYE_BYTES = 72;

public struct CamEye
{
    // 1 when the values below belong to a fresh, finite frame of this eye; 0 when none may be used.
    public int usable;
    public int closed;
    public float lid;
    public float wide;
    public float squint;
    public float pupil_ratio;
    public float pupil_mm;
    public float pupil_dilation;
    public float confidence;
};

public struct CamPage
{
    public int status;
    public CamEye left;
    public CamEye right;
};

uint32_t cam_u32(uint8_t* p_bytes, int p_offset)
{
    return uint32_t(p_bytes[p_offset]) | (uint32_t(p_bytes[p_offset + 1]) << 8) |
           (uint32_t(p_bytes[p_offset + 2]) << 16) | (uint32_t(p_bytes[p_offset + 3]) << 24);
}

uint64_t cam_u64(uint8_t* p_bytes, int p_offset)
{
    return uint64_t(cam_u32(p_bytes, p_offset)) | (uint64_t(cam_u32(p_bytes, p_offset + 4)) << 32);
}

float cam_f32(uint8_t* p_bytes, int p_offset)
{
    return asfloat(cam_u32(p_bytes, p_offset));
}

CamEye cam_blank()
{
    CamEye e;
    e.usable = 0;
    e.closed = 0;
    e.lid = 0.0;
    e.wide = 0.0;
    e.squint = 0.0;
    e.pupil_ratio = 0.0;
    e.pupil_mm = 0.0;
    e.pupil_dilation = 0.0;
    e.confidence = 0.0;
    return e;
}

// A frame is usable when it is stamped, not from the future, no older than p_max_age_ns, and
// every value is finite.
CamEye cam_eye(uint8_t* p_page, int p_at, uint64_t p_now_ns, uint64_t p_max_age_ns)
{
    CamEye e = cam_blank();
    uint64_t t = cam_u64(p_page, p_at);
    if (cam_u32(p_page, p_at + 24) != 1 || t == 0 || t > p_now_ns || p_now_ns - t > p_max_age_ns)
    {
        return e;
    }
    float lid = cam_f32(p_page, p_at + 32);
    float wide = cam_f32(p_page, p_at + 36);
    float squint = cam_f32(p_page, p_at + 40);
    float pupil_ratio = cam_f32(p_page, p_at + 44);
    float pupil_mm = cam_f32(p_page, p_at + 48);
    float pupil_dilation = cam_f32(p_page, p_at + 52);
    float confidence = cam_f32(p_page, p_at + 56);
    if (!isfinite(lid) || !isfinite(wide) || !isfinite(squint) || !isfinite(pupil_ratio) ||
        !isfinite(pupil_mm) || !isfinite(pupil_dilation) || !isfinite(confidence))
    {
        return e;
    }
    e.usable = 1;
    e.closed = cam_u32(p_page, p_at + 28) == 1 ? 1 : 0;
    e.lid = lid;
    e.wide = wide;
    e.squint = squint;
    e.pupil_ratio = pupil_ratio;
    e.pupil_mm = pupil_mm;
    e.pupil_dilation = pupil_dilation;
    e.confidence = confidence;
    return e;
}

// Decodes one copy of the page. The caller copies it under the seqlock; a copy taken mid-write
// has an odd sequence and is refused here as well.
public export __extern_cpp CamPage fe_eyecam_decode(uint8_t* p_page, int p_size, uint64_t p_now_ns,
                                                     uint64_t p_max_age_ns)
{
    CamPage page;
    page.left = cam_blank();
    page.right = page.left;
    if (p_size < PAGE_BYTES)
    {
        page.status = CAM_SHORT;
        return page;
    }
    if (cam_u32(p_page, 0) != PAGE_MAGIC)
    {
        page.status = CAM_MAGIC;
        return page;
    }
    if (cam_u32(p_page, 4) != PAGE_VERSION)
    {
        page.status = CAM_VERSION;
        return page;
    }
    if (cam_u32(p_page, 8) < uint32_t(PAGE_BYTES))
    {
        page.status = CAM_STRUCT_SIZE;
        return page;
    }
    if ((cam_u32(p_page, SEQ_AT) & 1) != 0)
    {
        page.status = CAM_WRITING;
        return page;
    }
    if (cam_u32(p_page, LIVE_AT) != 1)
    {
        page.status = CAM_IDLE;
        return page;
    }
    page.status = CAM_OK;
    page.left = cam_eye(p_page, EYE_AT, p_now_ns, p_max_age_ns);
    page.right = cam_eye(p_page, EYE_AT + EYE_BYTES, p_now_ns, p_max_age_ns);
    return page;
}

// The eye cameras replace what the eye server's openness gave for lid, wide and squint, and
// the brows that follow them. A frame that is not usable leaves p_base exactly as it was.
public export __extern_cpp EyeOut fe_eyecam_apply(Gains p_g, bool p_heuristics, EyeOut p_base, CamEye p_cam)
{
    if (p_cam.usable != 1)
    {
        return p_base;
    }
    EyeOut o = p_base;
    float lid = fe_clamp01(p_cam.lid);
    o.openness = fe_clamp01(lid / 0.75);
    o.blink = fe_clamp01(1.0 - o.openness);
    if (p_cam.closed == 1)
    {
        lid = 0.0;
        o.openness = 0.0;
        o.blink = 1.0;
    }
    o.lid = lid;
    o.wide = o.blink > 0.0 ? 0.0 : fe_clamp01(p_cam.wide);
    o.squint = p_cam.closed == 1 ? 0.0 : fe_clamp01(p_cam.squint);
    o.cheek_squint = 0.0;
    o.brow_lowerer = 0.0;
    o.brow_pinch = 0.0;
    o.brow_inner_up = 0.0;
    o.brow_outer_up = 0.0;
    if (p_heuristics)
    {
        o.cheek_squint = fe_clamp01(p_g.cheek_from_squint * o.squint);
        o.brow_lowerer = fe_clamp01(p_g.brow_down_from_squint * o.squint);
        o.brow_pinch = fe_clamp01(p_g.brow_pinch_from_squint * o.squint);
        o.brow_inner_up = fe_clamp01(p_g.brow_inner_from_wide * o.wide);
        o.brow_outer_up = fe_clamp01(p_g.brow_outer_from_wide * o.wide);
    }
    return o;
}

// VRCFT's PupilDiameter parameters are centimetres, at most 1; 0 when there is no usable frame.
public export __extern_cpp float fe_eyecam_pupil_cm(CamEye p_cam)
{
    if (p_cam.usable != 1)
    {
        return 0.0;
    }
    return clamp(p_cam.pupil_mm / 10.0, 0.0, 1.0);
}
