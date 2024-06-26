#include <renderer/postprocessing.inl>
#include <renderer/kajiya/inc/camera.glsl>

#if PostprocessingRasterShader

DAXA_DECL_PUSH_CONSTANT(PostprocessingRasterPush, push)
daxa_BufferPtr(GpuInput) gpu_input = push.uses.gpu_input;
daxa_ImageViewIndex composited_image_id = push.uses.composited_image_id;
daxa_ImageViewIndex render_image = push.uses.render_image;

const mat3 SRGB_2_XYZ_MAT = mat3(
    0.4124564, 0.3575761, 0.1804375,
    0.2126729, 0.7151522, 0.0721750,
    0.0193339, 0.1191920, 0.9503041);
const float SRGB_ALPHA = 0.055;

vec3 srgb_encode(vec3 linear) {
    vec3 higher = (pow(abs(linear), vec3(0.41666666)) * (1.0 + SRGB_ALPHA)) - SRGB_ALPHA;
    vec3 lower = linear * 12.92;
    return mix(higher, lower, step(linear, vec3(0.0031308)));
}

float luminance(vec3 color) {
    vec3 luminanceCoefficients = SRGB_2_XYZ_MAT[1];
    return dot(color, luminanceCoefficients);
}

const mat3 agxTransform = mat3(
    0.842479062253094, 0.0423282422610123, 0.0423756549057051,
    0.0784335999999992, 0.878468636469772, 0.0784336,
    0.0792237451477643, 0.0791661274605434, 0.879142973793104);

const mat3 agxTransformInverse = mat3(
    1.19687900512017, -0.0528968517574562, -0.0529716355144438,
    -0.0980208811401368, 1.15190312990417, -0.0980434501171241,
    -0.0990297440797205, -0.0989611768448433, 1.15107367264116);

vec3 agxDefaultContrastApproximation(vec3 x) {
    vec3 x2 = x * x;
    vec3 x4 = x2 * x2;

    return +15.5 * x4 * x2 - 40.14 * x4 * x + 31.96 * x4 - 6.868 * x2 * x + 0.4298 * x2 + 0.1191 * x - 0.00232;
}

void agx(inout vec3 color) {
    const float minEv = -12.47393;
    const float maxEv = 4.026069;

    color = agxTransform * color;
    color = clamp(log2(color), minEv, maxEv);
    color = (color - minEv) / (maxEv - minEv);
    color = agxDefaultContrastApproximation(color);
}

void agxEotf(inout vec3 color) {
    color = agxTransformInverse * color;
}

void agxLook(inout vec3 color) {
    // Punchy
    const vec3 slope = vec3(1.0);
    const vec3 power = vec3(1.0);
    const float saturation = 1.5;

    float luma = luminance(color);

    color = pow(color * slope, power);
    color = max(luma + saturation * (color - luma), vec3(0.0));
}

vec3 color_correct(vec3 x) {
    agx(x);
    agxLook(x);
    agxEotf(x);
    // x = srgb_encode(x);
    return x;
}

layout(location = 0) out vec4 color;

// 8-bit
uint bit_reverse(uint b) {
    b = (b & 0xF0) >> 4 | (b & 0x0F) << 4;
    b = (b & 0xCC) >> 2 | (b & 0x33) << 2;
    b = (b & 0xAA) >> 1 | (b & 0x55) << 1;
    return b;
}
uint interleave_uint32_with_zeros(uint word) {
    word = (word ^ (word << 16)) & 0x0000ffffu;
    word = (word ^ (word << 8)) & 0x00ff00ffu;
    word = (word ^ (word << 4)) & 0x0f0f0f0fu;
    word = (word ^ (word << 2)) & 0x33333333u;
    word = (word ^ (word << 1)) & 0x55555555u;
    return word;
}
uint bit_interleave(uint a, uint b) {
    return interleave_uint32_with_zeros(a) | interleave_uint32_with_zeros(b << 1);
}
uint bitwise_xor(uint a, uint b) {
    return a ^ b;
}

#include <utilities/gpu/random.glsl>

void main() {
    vec2 g_buffer_scl = vec2(deref(gpu_input).render_res_scl) * vec2(deref(gpu_input).frame_dim) / vec2(deref(gpu_input).rounded_frame_dim);
    vec2 uv = vec2(gl_FragCoord.xy);
    vec3 final_color = texelFetch(daxa_texture2D(composited_image_id), ivec2(uv), 0).rgb;

    if ((deref(gpu_input).flags & GAME_FLAG_BITS_PAUSED) == 0) {
        ivec2 center_offset_uv = ivec2(uv.xy) - ivec2(deref(gpu_input).frame_dim.xy / deref(gpu_input).render_res_scl) / 2;
        if ((abs(center_offset_uv.x) <= 1 || abs(center_offset_uv.y) <= 1) && abs(center_offset_uv.x) + abs(center_offset_uv.y) < 6) {
            final_color *= vec3(0.1);
        }
        if ((abs(center_offset_uv.x) <= 0 || abs(center_offset_uv.y) <= 0) && abs(center_offset_uv.x) + abs(center_offset_uv.y) < 5) {
            final_color += vec3(2.0);
        }
    }

    color = vec4(color_correct(final_color), 1.0);

    // Dithering:
    uvec2 ij = uvec2(uv * g_buffer_scl) & 7;
    uint i = ij[0], j = ij[1];
    rand_seed(good_rand_hash(floatBitsToUint(uv)));
    float off = rand(); // float(bit_reverse(bit_interleave(bitwise_xor(i, j), i))) / 256.0;
    color.rgb = floor(color.rgb * 256 + off) / 256;
}

#endif

#if DebugImageRasterShader

DAXA_DECL_PUSH_CONSTANT(DebugImageRasterPush, push)
daxa_BufferPtr(GpuInput) gpu_input = push.uses.gpu_input;
daxa_ImageViewIndex image_id = push.uses.image_id;
daxa_ImageViewIndex cube_image_id = push.uses.cube_image_id;
daxa_ImageViewIndex image_id_3d = push.uses.image_id_3d;
daxa_ImageViewIndex render_image = push.uses.render_image;

#include <renderer/kajiya/inc/reservoir.glsl>
#include <renderer/kajiya/inc/gbuffer.glsl>

layout(location = 0) out vec4 color;

void main() {
    vec2 uv = vec2(gl_FragCoord.xy) / vec2(push.output_tex_size.xy);
    vec3 tex_color;

    if (push.type == DEBUG_IMAGE_TYPE_GBUFFER) {
        ivec2 in_pixel_i = ivec2(uv * textureSize(daxa_utexture2D(image_id), 0).xy);
        GbufferDataPacked gbuffer_packed = GbufferDataPacked(texelFetch(daxa_utexture2D(image_id), in_pixel_i, 0));
        GbufferData gbuffer = unpack(gbuffer_packed);
        float depth = uintBitsToFloat(gbuffer_packed.data0.z);
        tex_color = vec3(gbuffer.albedo);
        // tex_color = vec3(depth);
        // tex_color = vec3(g_buffer_value.x * 0.00001, g_buffer_value.y * 0.0001, depth * 0.01);
    } else if (push.type == DEBUG_IMAGE_TYPE_SHADOW_BITMAP) {
        ivec2 in_pixel_i = ivec2(uv * textureSize(daxa_utexture2D(image_id), 0).xy);
        uint shadow_value = texelFetch(daxa_utexture2D(image_id), in_pixel_i, 0).r;
        ivec2 in_tile_i = ivec2(uv * textureSize(daxa_utexture2D(image_id), 0).xy * vec2(8, 4)) & ivec2(7, 3);
        uint bit_index = in_tile_i.x + in_tile_i.y * 8;
        tex_color = vec3((shadow_value >> bit_index) & 1);
    } else if (push.type == DEBUG_IMAGE_TYPE_DEFAULT_UINT) {
        ivec2 in_pixel_i = ivec2(uv * textureSize(daxa_utexture2D(image_id), 0).xy);
        tex_color = texelFetch(daxa_utexture2D(image_id), in_pixel_i, 0).rgb;
    } else if (push.type == DEBUG_IMAGE_TYPE_DEFAULT) {
        ivec2 in_pixel_i = ivec2(uv * textureSize(daxa_texture2D(image_id), 0).xy);
        tex_color = texelFetch(daxa_texture2D(image_id), in_pixel_i, 0).rgb;
    } else if (push.type == DEBUG_IMAGE_TYPE_CUBEMAP) {
        uv = uv * vec2(3, 2);
        ivec2 uv_i = ivec2(floor(uv));
        uv = uv - uv_i;
        int face = uv_i.x + uv_i.y * 3;
        ivec2 in_pixel_i = ivec2(uv * push.cube_size);
        tex_color = texelFetch(daxa_texture2DArray(cube_image_id), ivec3(in_pixel_i, face), 0).rgb * 0.05;
    } else if (push.type == DEBUG_IMAGE_TYPE_RESERVOIR) {
        ivec2 in_pixel_i = ivec2(uv * textureSize(daxa_texture2D(image_id), 0).xy);
        Reservoir1spp r = Reservoir1spp_from_raw(texelFetch(daxa_utexture2D(image_id), in_pixel_i, 0).xy);
        tex_color = vec3(r.W);
    } else if (push.type == DEBUG_IMAGE_TYPE_RTDGI_DEBUG) {
        ivec2 in_pixel_i = ivec2(uv * textureSize(daxa_texture2D(image_id), 0).xy);
        vec4 value = texelFetch(daxa_texture2D(image_id), in_pixel_i, 0);
        tex_color = vec3(value.rgb);
    } else if (push.type == DEBUG_IMAGE_TYPE_3D) {
        ivec3 in_pixel_i = ivec3(uv * textureSize(daxa_texture3D(image_id_3d), 0).xy, push.settings.flags);
        vec4 value = texelFetch(daxa_texture3D(image_id_3d), in_pixel_i, 0);
        tex_color = vec3(value.rgb);
    }

    tex_color = tex_color * push.settings.brightness;

    if (push.type != DEBUG_IMAGE_TYPE_3D) {
        if (((push.settings.flags >> DEBUG_IMAGE_FLAGS_GAMMA_CORRECT_INDEX) & 1) != 0) {
            tex_color = pow(tex_color, vec3(1.0 / 2.2));
        }
    }

    color = vec4(tex_color, 1.0);
}

#endif
