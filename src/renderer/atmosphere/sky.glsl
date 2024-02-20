#pragma once

#include <core.inl>
#include <g_samplers>

#define SUN_DIRECTION deref(gpu_input).sky_settings.sun_direction
#define SUN_INTENSITY 1.0
const vec3 sun_color = vec3(255, 240, 233) / 255.0; // 5000 kelvin blackbody
#define SUN_COL(sky_lut_tex) (get_far_sky_color(sky_lut_tex, SUN_DIRECTION) * SUN_INTENSITY)

vec3 get_sky_world_camera_position(daxa_BufferPtr(GpuInput) gpu_input) {
    // Because the atmosphere is using km as it's default units and we want one unit in world
    // space to be one meter we need to scale the position by a factor to get from meters -> kilometers
    const vec3 camera_position = (deref(gpu_input).player.pos + deref(gpu_input).player.player_unit_offset) * 0.001 + vec3(0.0, 0.0, 2.0);
    vec3 world_camera_position = camera_position * vec3(0, 0, 1);
    world_camera_position.z += deref(gpu_input).sky_settings.atmosphere_bottom;
    return world_camera_position;
}

struct TransmittanceParams {
    float height;
    float zenith_cos_angle;
};

struct SkyviewParams {
    float view_zenith_angle;
    float light_view_angle;
};

/* Return sqrt clamped to 0 */
float safe_sqrt(float x) { return sqrt(max(0, x)); }

float from_subuv_to_unit(float u, float resolution) {
    return (u - 0.5 / resolution) * (resolution / (resolution - 1.0));
}

float from_unit_to_subuv(float u, float resolution) {
    return (u + 0.5 / resolution) * (resolution / (resolution + 1.0));
}

/// Return distance of the first intersection between ray and sphere
/// @param r0 - ray origin
/// @param rd - normalized ray direction
/// @param s0 - sphere center
/// @param sR - sphere radius
/// @return return distance of intersection or -1.0 if there is no intersection
float ray_sphere_intersect_nearest(vec3 r0, vec3 rd, vec3 s0, float sR) {
    float a = dot(rd, rd);
    vec3 s0_r0 = r0 - s0;
    float b = 2.0 * dot(rd, s0_r0);
    float c = dot(s0_r0, s0_r0) - (sR * sR);
    float delta = b * b - 4.0 * a * c;
    if (delta < 0.0 || a == 0.0) {
        return -1.0;
    }
    float sol0 = (-b - safe_sqrt(delta)) / (2.0 * a);
    float sol1 = (-b + safe_sqrt(delta)) / (2.0 * a);
    if (sol0 < 0.0 && sol1 < 0.0) {
        return -1.0;
    }
    if (sol0 < 0.0) {
        return max(0.0, sol1);
    } else if (sol1 < 0.0) {
        return max(0.0, sol0);
    }
    return max(0.0, min(sol0, sol1));
}

const float PLANET_RADIUS_OFFSET = 0.01;

///	Transmittance LUT uses not uniform mapping -> transfer from mapping to texture uv
///	@param parameters
/// @param atmosphere_bottom - bottom radius of the atmosphere in km
/// @param atmosphere_top - top radius of the atmosphere in km
///	@return - uv of the corresponding texel
vec2 transmittance_lut_to_uv(TransmittanceParams parameters, float atmosphere_bottom, float atmosphere_top) {
    float H = safe_sqrt(atmosphere_top * atmosphere_top - atmosphere_bottom * atmosphere_bottom);
    float rho = safe_sqrt(parameters.height * parameters.height - atmosphere_bottom * atmosphere_bottom);

    float discriminant = parameters.height * parameters.height *
                             (parameters.zenith_cos_angle * parameters.zenith_cos_angle - 1.0) +
                         atmosphere_top * atmosphere_top;
    /* Distance to top atmosphere boundary */
    float d = max(0.0, (-parameters.height * parameters.zenith_cos_angle + safe_sqrt(discriminant)));

    float d_min = atmosphere_top - parameters.height;
    float d_max = rho + H;
    float mu = (d - d_min) / (d_max - d_min);
    float r = rho / H;

    return vec2(mu, r);
}

/// Transmittance LUT uses not uniform mapping -> transfer from uv to this mapping
/// @param uv - uv in the range [0,1]
/// @param atmosphere_bottom - bottom radius of the atmosphere in km
/// @param atmosphere_top - top radius of the atmosphere in km
/// @return - TransmittanceParams structure
TransmittanceParams uv_to_transmittance_lut_params(vec2 uv, float atmosphere_bottom, float atmosphere_top) {
    TransmittanceParams params;
    float H = safe_sqrt(atmosphere_top * atmosphere_top - atmosphere_bottom * atmosphere_bottom.x);

    float rho = H * uv.y;
    params.height = safe_sqrt(rho * rho + atmosphere_bottom * atmosphere_bottom);

    float d_min = atmosphere_top - params.height;
    float d_max = rho + H;
    float d = d_min + uv.x * (d_max - d_min);

    params.zenith_cos_angle = d == 0.0 ? 1.0 : (H * H - rho * rho - d * d) / (2.0 * params.height * d);
    params.zenith_cos_angle = clamp(params.zenith_cos_angle, -1.0, 1.0);

    return params;
}

/// Get parameters used for skyview LUT computation from uv coords
/// @param uv - texel uv in the range [0,1]
/// @param atmosphere_bottom - bottom of the atmosphere in km
/// @param atmosphere_top - top of the atmosphere in km
/// @param skyview dimensions
/// @param view_height - view_height in world coordinates -> distance from planet center
/// @return - SkyviewParams structure
SkyviewParams uv_to_skyview_lut_params(vec2 uv, float atmosphere_bottom,
                                       float atmosphere_top, vec2 skyview_dimensions, float view_height) {
    /* Constrain uvs to valid sub texel range
    (avoid zenith derivative issue making LUT usage visible) */
    uv = vec2(from_subuv_to_unit(uv.x, skyview_dimensions.x),
              from_subuv_to_unit(uv.y, skyview_dimensions.y));

    float beta = asin(atmosphere_bottom / view_height);
    float zenith_horizon_angle = M_PI - beta;

    float view_zenith_angle;
    float light_view_angle;
    /* Nonuniform mapping near the horizon to avoid artefacts */
    if (uv.y < 0.5) {
        float coord = 1.0 - (1.0 - 2.0 * uv.y) * (1.0 - 2.0 * uv.y);
        view_zenith_angle = zenith_horizon_angle * coord;
    } else {
        float coord = (uv.y * 2.0 - 1.0) * (uv.y * 2.0 - 1.0);
        view_zenith_angle = zenith_horizon_angle + beta * coord;
    }
    light_view_angle = (uv.x * uv.x) * M_PI;
    return SkyviewParams(view_zenith_angle, light_view_angle);
}

/// Moves to the nearest intersection with top of the atmosphere in the direction specified in
/// world_direction
/// @param world_position - current world position -> will be changed to new pos at the top of
/// 		the atmosphere if there exists such intersection
/// @param world_direction - the direction in which the shift will be done
/// @param atmosphere_bottom - bottom of the atmosphere in km
/// @param atmosphere_top - top of the atmosphere in km
bool move_to_top_atmosphere(inout vec3 world_position, vec3 world_direction,
                            float atmosphere_bottom, float atmosphere_top) {
    vec3 planet_origin = vec3(0.0, 0.0, 0.0);
    /* Check if the world_position is outside of the atmosphere */
    if (length(world_position) > atmosphere_top) {
        float dist_to_top_atmo_intersection = ray_sphere_intersect_nearest(
            world_position, world_direction, planet_origin, atmosphere_top);

        /* No intersection with the atmosphere */
        if (dist_to_top_atmo_intersection == -1.0) {
            return false;
        } else {
            // bias the world position to be slightly inside the sphere
            const float BIAS = uintBitsToFloat(0x3f800040); // uintBitsToFloat(0x3f800040) == 1.00000762939453125
            world_position += world_direction * (dist_to_top_atmo_intersection * BIAS);
            vec3 up_offset = normalize(world_position) * -PLANET_RADIUS_OFFSET;
            world_position += up_offset;
        }
    }
    /* Position is in or at the top of the atmosphere */
    return true;
}

/// @param params - buffer reference to the atmosphere parameters buffer
/// @param position - position in the world where the sample is to be taken
/// @return atmosphere extinction at the desired point
vec3 sample_medium_extinction(daxa_BufferPtr(GpuInput) gpu_input, vec3 position) {
    const float height = length(position) - deref(gpu_input).sky_settings.atmosphere_bottom;

    const float density_mie = exp(deref(gpu_input).sky_settings.mie_density[1].exp_scale * height);
    const float density_ray = exp(deref(gpu_input).sky_settings.rayleigh_density[1].exp_scale * height);
    // const float density_ozo = clamp(height < deref(gpu_input).sky_settings.absorption_density[0].layer_width ?
    //     deref(gpu_input).sky_settings.absorption_density[0].lin_term * height + deref(gpu_input).sky_settings.absorption_density[0].const_term :
    //     deref(gpu_input).sky_settings.absorption_density[1].lin_term * height + deref(gpu_input).sky_settings.absorption_density[1].const_term,
    //     0.0, 1.0);
    const float density_ozo = exp(-max(0.0, 35.0 - height) * (1.0 / 5.0)) * exp(-max(0.0, height - 35.0) * (1.0 / 15.0)) * 2;
    vec3 mie_extinction = deref(gpu_input).sky_settings.mie_extinction * max(density_mie, 0.0);
    vec3 ray_extinction = deref(gpu_input).sky_settings.rayleigh_scattering * max(density_ray, 0.0);
    vec3 ozo_extinction = deref(gpu_input).sky_settings.absorption_extinction * max(density_ozo, 0.0);

    return mie_extinction + ray_extinction + ozo_extinction;
}

/// @param params - buffer reference to the atmosphere parameters buffer
/// @param position - position in the world where the sample is to be taken
/// @return atmosphere scattering at the desired point
vec3 sample_medium_scattering(daxa_BufferPtr(GpuInput) gpu_input, vec3 position) {
    const float height = length(position) - deref(gpu_input).sky_settings.atmosphere_bottom;

    const float density_mie = exp(deref(gpu_input).sky_settings.mie_density[1].exp_scale * height);
    const float density_ray = exp(deref(gpu_input).sky_settings.rayleigh_density[1].exp_scale * height);

    vec3 mie_scattering = deref(gpu_input).sky_settings.mie_scattering * max(density_mie, 0.0);
    vec3 ray_scattering = deref(gpu_input).sky_settings.rayleigh_scattering * max(density_ray, 0.0);
    /* Not considering ozon scattering in current version of this model */
    vec3 ozo_scattering = vec3(0.0, 0.0, 0.0);

    return mie_scattering + ray_scattering + ozo_scattering;
}

struct ScatteringSample {
    vec3 mie;
    vec3 ray;
};
/// @param params - buffer reference to the atmosphere parameters buffer
/// @param position - position in the world where the sample is to be taken
/// @return Scattering sample struct
// TODO(msakmary) Fix this!!
ScatteringSample sample_medium_scattering_detailed(daxa_BufferPtr(GpuInput) gpu_input, vec3 position) {
    const float height = length(position) - deref(gpu_input).sky_settings.atmosphere_bottom;

    const float density_mie = exp(deref(gpu_input).sky_settings.mie_density[1].exp_scale * height);
    const float density_ray = exp(deref(gpu_input).sky_settings.rayleigh_density[1].exp_scale * height);

    vec3 mie_scattering = deref(gpu_input).sky_settings.mie_scattering * max(density_mie, 0.0);
    vec3 ray_scattering = deref(gpu_input).sky_settings.rayleigh_scattering * max(density_ray, 0.0);
    /* Not considering ozon scattering in current version of this model */
    vec3 ozo_scattering = vec3(0.0, 0.0, 0.0);

    return ScatteringSample(mie_scattering, ray_scattering);
}

/// Get skyview LUT uv from skyview parameters
/// @param intersects_ground - true if ray intersects ground false otherwise
/// @param params - SkyviewParams structure
/// @param atmosphere_bottom - bottom of the atmosphere in km
/// @param atmosphere_top - top of the atmosphere in km
/// @param skyview_dimensions - skyViewLUT dimensions
/// @param view_height - view_height in world coordinates -> distance from planet center
/// @return - uv for the skyview LUT sampling
vec2 skyview_lut_params_to_uv(bool intersects_ground, SkyviewParams params,
                              float atmosphere_bottom, float atmosphere_top, vec2 skyview_dimensions, float view_height) {
    vec2 uv;
    float beta = asin(atmosphere_bottom / view_height);
    float zenith_horizon_angle = M_PI - beta;

    if (!intersects_ground) {
        float coord = params.view_zenith_angle / zenith_horizon_angle;
        coord = (1.0 - safe_sqrt(1.0 - coord)) / 2.0;
        uv.y = coord;
    } else {
        float coord = (params.view_zenith_angle - zenith_horizon_angle) / beta;
        coord = (safe_sqrt(coord) + 1.0) / 2.0;
        uv.y = coord;
    }
    uv.x = safe_sqrt(params.light_view_angle / M_PI);
    uv = vec2(from_unit_to_subuv(uv.x, SKY_SKY_RES.x),
              from_unit_to_subuv(uv.y, SKY_SKY_RES.y));
    return uv;
}

vec3 get_sun_illuminance(
    daxa_BufferPtr(GpuInput) gpu_input,
    daxa_ImageViewIndex _transmittance,
    vec3 view_direction,
    float height,
    float zenith_cos_angle,
    float sun_angular_radius_cos) {
    const vec3 sun_direction = deref(gpu_input).sky_settings.sun_direction;
    float cos_theta = dot(view_direction, sun_direction);

    if (cos_theta >= sun_angular_radius_cos) {
        TransmittanceParams transmittance_lut_params = TransmittanceParams(height, zenith_cos_angle);
        vec2 transmittance_texture_uv = transmittance_lut_to_uv(
            transmittance_lut_params,
            deref(gpu_input).sky_settings.atmosphere_bottom,
            deref(gpu_input).sky_settings.atmosphere_top);
        vec3 transmittance_to_sun = texture(
                                        daxa_sampler2D(_transmittance, g_sampler_llc),
                                        transmittance_texture_uv)
                                        .rgb;
        return transmittance_to_sun * sun_color.rgb * SUN_INTENSITY;
    } else {
        return vec3(0.0);
    }
}

vec3 get_atmosphere_illuminance_along_ray(
    daxa_BufferPtr(GpuInput) gpu_input,
    daxa_ImageViewIndex _skyview,
    vec3 ray,
    vec3 world_camera_position,
    vec3 sun_direction,
    out bool intersects_ground) {
    const vec3 world_up = normalize(world_camera_position);

    const float view_zenith_angle = acos(dot(ray, world_up));
    // NOTE(grundlett): Minor imprecision in the dot-product can result in a value
    // just barely outside the valid range of acos (-1.0, 1.0). Sanity check and
    // clamp the
    const float light_view_angle =
        acos(clamp(dot(normalize(vec3(sun_direction.xy, 0.0)),
                       normalize(vec3(ray.xy, 0.0))),
                   -1.0, 1.0));

    const float atmosphere_intersection_distance = ray_sphere_intersect_nearest(
        world_camera_position,
        ray,
        vec3(0.0, 0.0, 0.0),
        deref(gpu_input).sky_settings.atmosphere_bottom);

    intersects_ground = atmosphere_intersection_distance >= 0.0;
    const float camera_height = length(world_camera_position);

    vec2 skyview_uv = skyview_lut_params_to_uv(
        intersects_ground,
        SkyviewParams(view_zenith_angle, light_view_angle),
        deref(gpu_input).sky_settings.atmosphere_bottom,
        deref(gpu_input).sky_settings.atmosphere_top,
        vec2(SKY_SKY_RES.xy),
        camera_height);

    const vec3 unitless_atmosphere_illuminance = texture(daxa_sampler2D(_skyview, g_sampler_llc), skyview_uv).rgb;
    const vec3 sun_color_weighed_atmosphere_illuminance = sun_color.rgb * unitless_atmosphere_illuminance;
    const vec3 atmosphere_scattering_illuminance = sun_color_weighed_atmosphere_illuminance * SUN_INTENSITY;

    return atmosphere_scattering_illuminance;
}

vec3 get_atmosphere_lighting(daxa_BufferPtr(GpuInput) gpu_input, daxa_ImageViewIndex _skyview, daxa_ImageViewIndex _transmittance, vec3 view_direction) {
    const vec3 world_camera_position = get_sky_world_camera_position(gpu_input);
    const vec3 sun_direction = deref(gpu_input).sky_settings.sun_direction;

    bool normal_ray_intersects_ground;
    bool view_ray_intersects_ground;
    const vec3 atmosphere_view_illuminance = get_atmosphere_illuminance_along_ray(
        gpu_input,
        _skyview,
        view_direction,
        world_camera_position,
        sun_direction,
        view_ray_intersects_ground);

    const vec3 direct_sun_illuminance = view_ray_intersects_ground ? vec3(0.0) : get_sun_illuminance(gpu_input, _transmittance, view_direction, length(world_camera_position), dot(sun_direction, normalize(world_camera_position)), deref(gpu_input).sky_settings.sun_angular_radius_cos);

    return atmosphere_view_illuminance + direct_sun_illuminance;
}

vec3 sample_sun_direction(
    daxa_BufferPtr(GpuInput) gpu_input,
    vec2 urand, bool soft) {
    if (soft && PER_VOXEL_NORMALS == 0) {
        float sun_angular_radius_cos = deref(gpu_input).sky_settings.sun_angular_radius_cos;
        if (sun_angular_radius_cos < 1.0) {
            const mat3 basis = build_orthonormal_basis(normalize(SUN_DIRECTION));
            return basis * uniform_sample_cone(urand, sun_angular_radius_cos);
        }
    }
    return SUN_DIRECTION;
}

vec3 sun_color_in_direction(
    daxa_BufferPtr(GpuInput) gpu_input,
    daxa_ImageViewIndex transmittance_lut, vec3 nrm) {
    const vec3 world_camera_position = get_sky_world_camera_position(gpu_input);
    const vec3 sun_direction = deref(gpu_input).sky_settings.sun_direction;

    const float atmosphere_intersection_distance = ray_sphere_intersect_nearest(
        world_camera_position,
        nrm,
        vec3(0.0, 0.0, 0.0),
        deref(gpu_input).sky_settings.atmosphere_bottom);

    bool intersects_ground = atmosphere_intersection_distance >= 0.0;
    const vec3 direct_sun_illuminance = intersects_ground ? vec3(0.0) : get_sun_illuminance(gpu_input, transmittance_lut, nrm, length(world_camera_position), dot(sun_direction, normalize(world_camera_position)), deref(gpu_input).sky_settings.sun_angular_radius_cos);

    return direct_sun_illuminance;
}