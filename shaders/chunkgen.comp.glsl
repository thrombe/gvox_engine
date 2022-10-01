#include <shared/shared.inl>

DAXA_USE_PUSH_CONSTANT(ChunkgenCompPush)

#include <utils/chunkgen.glsl>

layout(local_size_x = 8, local_size_y = 8, local_size_z = 8) in;
void main() {
    u32 chunk_index = VOXEL_WORLD.chunkgen_index;
    if (VOXEL_WORLD.chunks_genstate[chunk_index].edit_stage != 1)
        return;

    u32vec3 voxel_i = gl_GlobalInvocationID.xyz;
    u32 voxel_index = voxel_i.x + voxel_i.y * CHUNK_SIZE + voxel_i.z * CHUNK_SIZE * CHUNK_SIZE;

#if USING_BRICKMAP
    f32vec3 voxel_p = f32vec3(voxel_i) / VOXEL_SCL + VOXEL_WORLD.generation_chunk.box.bound_min;
    Voxel result = gen_voxel(voxel_p);

    VOXEL_WORLD.generation_chunk.packed_voxels[voxel_index] = pack_voxel(result);
#else
    f32vec3 voxel_p = f32vec3(voxel_i) / VOXEL_SCL + VOXEL_CHUNKS[chunk_index].box.bound_min;
    Voxel result = gen_voxel(voxel_p);

    VOXEL_CHUNKS[chunk_index].packed_voxels[voxel_index] = pack_voxel(result);
#endif
}