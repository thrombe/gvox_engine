#pragma once

// Based on https://github.com/sebh/HLSL-Spherical-Harmonics/

#include "math_const.glsl"

vec4 sh_eval(vec3 dir) {
	vec4 result;
	result.x = 0.28209479177387814347403972578039f;
	result.y =-0.48860251190291992158638462283836f * dir.y;
	result.z = 0.48860251190291992158638462283836f * dir.z;
	result.w =-0.48860251190291992158638462283836f * dir.x;
	return result;
}

vec4 sh_eval_cosine_lobe(vec3 dir) {
	vec4 result;
	result.x = 0.8862269254527580137f;
	result.y =-1.0233267079464884885f * dir.y;
	result.z = 1.0233267079464884885f * dir.z;
	result.w =-1.0233267079464884885f * dir.x;
	return result;
}

vec4 sh_diffuse_convolution(vec4 sh) {
	vec4 result = sh;
	// L0
	result.x   *= M_PI;
	// L1
	result.yzw *= 2.0943951023931954923f;
	return result;
}
