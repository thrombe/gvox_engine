#pragma once

#include "../core.inl"

DAXA_DECL_TASK_USES_BEGIN(ColorSceneComputeUses, DAXA_UNIFORM_BUFFER_SLOT0)
DAXA_TASK_USE_BUFFER(settings, daxa_BufferPtr(GpuSettings), COMPUTE_SHADER_READ)
DAXA_TASK_USE_BUFFER(gpu_input, daxa_BufferPtr(GpuInput), COMPUTE_SHADER_READ)
DAXA_TASK_USE_BUFFER(globals, daxa_BufferPtr(GpuGlobals), COMPUTE_SHADER_READ)
DAXA_TASK_USE_BUFFER(voxel_malloc_global_allocator, daxa_RWBufferPtr(VoxelMalloc_GlobalAllocator), COMPUTE_SHADER_READ)
DAXA_TASK_USE_BUFFER(voxel_chunks, daxa_BufferPtr(VoxelLeafChunk), COMPUTE_SHADER_READ)
DAXA_TASK_USE_IMAGE(blue_noise_cosine_vec3, REGULAR_3D, COMPUTE_SHADER_READ)
DAXA_TASK_USE_IMAGE(render_pos_image_id, REGULAR_2D, COMPUTE_SHADER_READ)
DAXA_TASK_USE_IMAGE(render_prev_pos_image_id, REGULAR_2D, COMPUTE_SHADER_READ)
DAXA_TASK_USE_IMAGE(render_col_image_id, REGULAR_2D, COMPUTE_SHADER_WRITE)
DAXA_TASK_USE_IMAGE(render_prev_col_image_id, REGULAR_2D, COMPUTE_SHADER_READ)
DAXA_TASK_USE_IMAGE(raster_color_image, REGULAR_2D, COMPUTE_SHADER_READ)
DAXA_TASK_USE_BUFFER(simulated_voxel_particles, daxa_BufferPtr(SimulatedVoxelParticle), SHADER_READ)
DAXA_DECL_TASK_USES_END()

#if defined(__cplusplus)

struct ColorSceneComputeTaskState {
    daxa::PipelineManager &pipeline_manager;
    AppUi &ui;
    u32vec2 &render_size;
    std::shared_ptr<daxa::ComputePipeline> pipeline;

    void compile_pipeline() {
        auto compile_result = pipeline_manager.add_compute_pipeline({
            .shader_info = {
                .source = daxa::ShaderFile{"color_scene.comp.glsl"},
                .compile_options = {.defines = {{"COLOR_SCENE_COMPUTE", "1"}}},
            },
            .name = "color_scene",
        });
        if (compile_result.is_err()) {
            ui.console.add_log(compile_result.to_string());
            return;
        }
        pipeline = compile_result.value();
    }

    ColorSceneComputeTaskState(daxa::PipelineManager &a_pipeline_manager, AppUi &a_ui, u32vec2 &a_render_size) : pipeline_manager{a_pipeline_manager}, ui{a_ui}, render_size{a_render_size} {}

    void record_commands(daxa::CommandList &cmd_list) {
        if (!pipeline) {
            compile_pipeline();
            if (!pipeline)
                return;
        }
        cmd_list.set_pipeline(*pipeline);
        assert((render_size.x % 8) == 0 && (render_size.y % 8) == 0);
        cmd_list.dispatch(render_size.x / 8, render_size.y / 8);
    }
};

struct ColorSceneComputeTask : ColorSceneComputeUses {
    ColorSceneComputeTaskState *state;
    void callback(daxa::TaskInterface const &ti) {
        auto cmd_list = ti.get_command_list();
        cmd_list.set_uniform_buffer(ti.uses.get_uniform_buffer_info());
        state->record_commands(cmd_list);
    }
};

#endif
