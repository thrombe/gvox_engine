#pragma once

// NOTE(grundlett): For `PER_VOXEL_NORMALS`
#include <utilities/gpu/defs.glsl>

#define DIFFUSE_GI_USE_RESTIR 1
#define RESTIR_TEMPORAL_M_CLAMP 80.0

// Reduces fireflies, but causes darkening in corners
#define RESTIR_RESERVOIR_W_CLAMP 80.0
// RTDGI_RESTIR_USE_JACOBIAN_BASED_REJECTION covers the same niche.
//#define RESTIR_RESERVOIR_W_CLAMP 1e5

const bool RESTIR_USE_SPATIAL = true;
const bool RESTIR_TEMPORAL_USE_PERMUTATIONS = true;
const bool RESTIR_USE_PATH_VALIDATION = true;

// Narrow down the spatial resampling kernel when M is already high.
#define RTDGI_RESTIR_SPATIAL_USE_KERNEL_NARROWING true

// NOTE(grundlett): This should be disabled for per-voxel normals.
#if PER_VOXEL_NORMALS
const bool RTDGI_RESTIR_SPATIAL_USE_RAYMARCH = !true;
#else
const bool RTDGI_RESTIR_SPATIAL_USE_RAYMARCH = true;
#endif
const bool RTDGI_RESTIR_SPATIAL_USE_RAYMARCH_COLOR_BOUNCE = !true;
const bool RTDGI_RESTIR_USE_JACOBIAN_BASED_REJECTION = true;
#define RTDGI_RESTIR_JACOBIAN_BASED_REJECTION_VALUE 8

const bool RTDGI_RESTIR_USE_RESOLVE_SPATIAL_FILTER = true;

// If `1`, every RTDGI_INTERLEAVED_VALIDATION_PERIOD-th frame is a validation one,
// where new candidates are not suggested, but the reservoir picks are validated instead.
// This hides the cost of validation, but reduces responsiveness.
#define RTDGI_INTERLEAVE_TRACING_AND_VALIDATION 1

// How often should validation happen in interleaved mode. Lower values result
// in more frequent validation, but less frequent candidate generation.
// Note that validation also updates irradiance values, so those frames are not useless
// for the purpose of integration either.
#define RTDGI_INTERLEAVED_VALIDATION_PERIOD 4

// If `1`, we will always trace candidate rays, but keep them short on frames where
// `is_rtdgi_tracing_frame` yields false.
// This preserves contact lighting, but introduces some frame jitter.
// New traces are a bit more expensive than validations, so the jitter is not terrible.
#define RTDGI_INTERLEAVED_VALIDATION_ALWAYS_TRACE_NEAR_FIELD 1

bool is_rtdgi_validation_frame(uint frame_index) {
    #if RTDGI_INTERLEAVE_TRACING_AND_VALIDATION
        return (frame_index % RTDGI_INTERLEAVED_VALIDATION_PERIOD) == 0;
    #else
        return true;
    #endif
}

bool is_rtdgi_tracing_frame(uint frame_index) {
    #if RTDGI_INTERLEAVE_TRACING_AND_VALIDATION
        return !is_rtdgi_validation_frame(frame_index);
    #else
        return true;
    #endif
}
