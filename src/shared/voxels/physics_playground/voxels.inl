#pragma once

#include <shared/core.inl>

#define RIGID_BODY_FLAGS_IS_STATIC_OFFSET 0
#define RIGID_BODY_FLAG_MASK_IS_STATIC (1 << RIGID_BODY_FLAGS_IS_STATIC_OFFSET)

#define RIGID_BODY_FLAGS_SHAPE_TYPE_OFFSET 1
#define RIGID_BODY_FLAG_MASK_SHAPE_TYPE (0x7 << RIGID_BODY_FLAGS_SHAPE_TYPE_OFFSET)
#define RIGID_BODY_SHAPE_TYPE_SPHERE (0 << RIGID_BODY_FLAGS_SHAPE_TYPE_OFFSET)
#define RIGID_BODY_SHAPE_TYPE_BOX (1 << RIGID_BODY_FLAGS_SHAPE_TYPE_OFFSET)

#define RIGID_BODY_MAX_N 10

struct RigidBody {
    f32vec3 pos;
    f32vec3 lin_vel;

    // TODO: store as Rotor
    f32vec3 rot;
    f32vec3 rot_vel;

    f32vec3 size;

    float density;
    float mass;
    float restitution;

    u32 flags;
};

struct VoxelWorldGlobals {
    i32vec3 prev_offset;
    i32vec3 offset;

    u32 rigid_body_n;
    RigidBody rigid_bodies[RIGID_BODY_MAX_N];
};
DAXA_DECL_BUFFER_PTR(VoxelWorldGlobals)

#define VOXELS_USE_BUFFERS(ptr_type, mode) \
    DAXA_TASK_USE_BUFFER(voxel_globals, ptr_type(VoxelWorldGlobals), mode)

#define VOXELS_BUFFER_USES_ASSIGN(voxel_buffers) \
    .voxel_globals = voxel_buffers.task_voxel_globals

struct VoxelWorldOutput {
    u32 _dummy;
};

struct VoxelBufferPtrs {
    daxa_BufferPtr(VoxelWorldGlobals) globals;
};
struct VoxelRWBufferPtrs {
    daxa_RWBufferPtr(VoxelWorldGlobals) globals;
};

#define VOXELS_BUFFER_PTRS VoxelBufferPtrs(daxa_BufferPtr(VoxelWorldGlobals)(voxel_globals))
#define VOXELS_RW_BUFFER_PTRS VoxelRWBufferPtrs(daxa_RWBufferPtr(VoxelWorldGlobals)(voxel_globals))