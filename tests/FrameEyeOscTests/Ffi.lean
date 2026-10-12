-- SPDX-FileCopyrightText: 2026 K. S. Ernest (iFire) Lee
-- SPDX-License-Identifier: MIT
/-!
# The Slang driver, through tests/ffi/shim.cpp

A struct crosses as a `FloatArray` of its fields in declaration order (see
`tests/ffi/abi.h`); OSC messages and plan entries cross as their raw bytes.
-/

namespace FrameEyeOscTests.Ffi

@[extern "fe_lean_clamp01"] opaque clamp01 : Float → Float
@[extern "fe_lean_calib_normalized"] opaque calibNormalized : @& FloatArray → FloatArray
@[extern "fe_lean_calib_step"] opaque calibStep : @& FloatArray → Float → FloatArray
@[extern "fe_lean_blink_of"] opaque blinkOf : @& FloatArray → Float → Float
@[extern "fe_lean_wide_of"] opaque wideOf : @& FloatArray → Float → Float
@[extern "fe_lean_eye"] opaque eye : UInt8 → @& FloatArray → UInt8 → @& FloatArray → @& FloatArray → FloatArray
@[extern "fe_lean_frame"] opaque frame : @& FloatArray → UInt8 → @& FloatArray → @& FloatArray → FloatArray
@[extern "fe_lean_parallel"] opaque parallel : @& FloatArray → FloatArray
@[extern "fe_lean_mirror"] opaque mirror : @& FloatArray → FloatArray
@[extern "fe_lean_level"] opaque level : @& FloatArray → @& FloatArray → Float
@[extern "fe_lean_style_step"] opaque styleStep : @& FloatArray → Float → @& FloatArray → Float → Float → FloatArray
@[extern "fe_lean_style_eye"] opaque styleEye :
  @& FloatArray → @& FloatArray → UInt8 → @& FloatArray → Float → @& FloatArray → @& FloatArray → FloatArray
@[extern "fe_lean_wink_gate"] opaque winkGate : UInt8 → UInt8 → Float → Float → FloatArray
@[extern "fe_lean_eye_lost"] opaque eyeLost : @& FloatArray → Float → UInt8
@[extern "fe_lean_expressive"] opaque expressive : Float → Float → Float → Float → Float
@[extern "fe_lean_one_euro_step"] opaque oneEuroStep : @& FloatArray → Float → Float → FloatArray
@[extern "fe_lean_pitch_yaw"] opaque pitchYaw : @& FloatArray → FloatArray
@[extern "fe_lean_gaze_angles"] opaque gazeAngles : @& FloatArray → FloatArray
@[extern "fe_lean_quantize"] opaque quantize : UInt32 → Float → UInt32

@[extern "fe_lean_sample_valid"] opaque sampleValid : @& FloatArray → UInt8
@[extern "fe_lean_reference_messages"] opaque referenceMessages : @& FloatArray → @& String → Array ByteArray
@[extern "fe_lean_decode"] opaque decode : @& ByteArray → FloatArray
@[extern "fe_lean_shm_create"] opaque shmCreate : @& String → UInt32 → IO Bool
@[extern "fe_lean_shm_publish"] opaque shmPublish : @& String → Float → Float → IO Bool
@[extern "fe_lean_eye_read_once"] opaque eyeReadOnce : @& String → UInt32 → IO FloatArray
@[extern "fe_lean_shm_set_dominant"] opaque shmSetDominant : @& String → UInt8 → Int32 → IO Bool
@[extern "fe_lean_eye_read_busy"] opaque eyeReadBusy : @& String → IO FloatArray
@[extern "fe_lean_dominant_eye"] opaque dominantEye : @& ByteArray → Int32

@[extern "fe_lean_message"] opaque message : @& String → ByteArray
@[extern "fe_lean_add_float"] opaque addFloat : @& ByteArray → Float → ByteArray
@[extern "fe_lean_add_int"] opaque addInt : @& ByteArray → UInt32 → ByteArray
@[extern "fe_lean_add_bool"] opaque addBool : @& ByteArray → UInt8 → ByteArray
@[extern "fe_lean_add_string"] opaque addString : @& ByteArray → @& String → ByteArray
@[extern "fe_lean_message_address"] opaque messageAddress : @& ByteArray → String
@[extern "fe_lean_message_tag"] opaque messageTag : @& ByteArray → UInt32 → UInt8
@[extern "fe_lean_message_float"] opaque messageFloat : @& ByteArray → UInt32 → Float
@[extern "fe_lean_encode"] opaque encode : @& ByteArray → UInt32 → ByteArray
@[extern "fe_lean_decode_message"] opaque decodeMessage : @& ByteArray → ByteArray
@[extern "fe_lean_message_equal"] opaque messageEqual : @& ByteArray → @& ByteArray → UInt8
@[extern "fe_lean_bundle"] opaque bundle : @& Array ByteArray → ByteArray
@[extern "fe_lean_decode_packet"] opaque decodePacket : @& ByteArray → Array ByteArray

@[extern "fe_lean_plan"] opaque plan : @& Array String → @& ByteArray → Array ByteArray
@[extern "fe_lean_fallback_plan"] opaque fallbackPlan : @& String → Array ByteArray
@[extern "fe_lean_v2_count"] opaque v2Count : Unit → UInt32
@[extern "fe_lean_entry_address"] opaque entryAddress : @& ByteArray → String
@[extern "fe_lean_entry_width"] opaque entryWidth : @& ByteArray → UInt32
@[extern "fe_lean_entry_bit"] opaque entryBit : @& ByteArray → UInt32
@[extern "fe_lean_message_for"] opaque messageFor : @& ByteArray → @& FloatArray → ByteArray
@[extern "fe_lean_learn"] opaque learn : @& Array ByteArray → String × Array ByteArray
@[extern "fe_lean_learned_counts"] opaque learnedCounts : @& Array ByteArray → FloatArray

@[extern "fe_lean_message_argc"] opaque messageArgc : @& ByteArray → UInt32
@[extern "fe_lean_message_int"] opaque messageInt : @& ByteArray → UInt32 → UInt32
@[extern "fe_lean_steamlink_closed"] opaque steamlinkClosed : Float → Float
@[extern "fe_lean_steamlink_messages"] opaque steamlinkMessages : @& FloatArray → Array ByteArray
@[extern "fe_lean_gaze_vector"] opaque gazeVector : Float → Float → FloatArray
@[extern "fe_lean_native_messages"] opaque nativeMessages : @& FloatArray → UInt8 → Array ByteArray
@[extern "fe_lean_active_message"] opaque activeMessage : @& String → UInt8 → UInt32 → Array ByteArray
@[extern "fe_lean_etvr_lid"] opaque etvrLid : Float → Float
@[extern "fe_lean_etvr_messages"] opaque etvrMessages : @& FloatArray → @& String → Array ByteArray
@[extern "fe_lean_livelink_shapes"] opaque livelinkShapes : @& FloatArray → FloatArray
@[extern "fe_lean_livelink_packet"] opaque livelinkPacket : Float → @& FloatArray → ByteArray
@[extern "fe_lean_throttle_count"] opaque throttleCount : UInt32 → UInt32 → UInt8 → UInt32

@[extern "fe_lean_calib_round_trip"] opaque calibRoundTrip : @& String → @& FloatArray → IO FloatArray

end FrameEyeOscTests.Ffi
