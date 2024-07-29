#[compute]
#version 450

// based on https://www.shadertoy.com/view/4ctXD8 / https://www.shadertoy.com/view/mtlBzX 
// by Suslik / fad 

// A 2D implementation of 
// Radiance Cascades: A Novel Approach to Calculating Global Illumination
// https://drive.google.com/file/d/1L6v1_7HY2X-LV3Ofb6oyTIxgEaP4LOI6/view

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;

layout(set = 0, binding = 1, rgba32f) readonly uniform image2D emissivity_image;
layout(set = 0, binding = 3, rgba32f) writeonly uniform image2D output_image;
layout(set = 0, binding = 10, rgba32f) readonly uniform image2D cascades_image_0;
layout(set = 0, binding = 11, rgba32f) readonly uniform image2D cascades_image_1;
layout(set = 0, binding = 12, rgba32f) readonly uniform image2D cascades_image_2;
layout(set = 0, binding = 13, rgba32f) readonly uniform image2D cascades_image_3;
layout(set = 0, binding = 14, rgba32f) readonly uniform image2D cascades_image_4;
layout(set = 0, binding = 15, rgba32f) readonly uniform image2D cascades_image_5;


layout(push_constant, std430) uniform Params {
    // int cascade_index; // Current cascade level
    // int prev_cascade_index; // Previous cascade level
    int num_cascades; // Total number of cascades
    int cascade_size_x; // Size of each cascade
    int cascade_size_y; // Size of each cascade
} pc;

//================================================================================================================
// From Common

// The shader automatically calculates the maximum spatial resolution
// possible for the cascades such that they can still fit within the
// cubemap buffer with the c_dRes and nCascades parameters below. But if
// you have a low end device, that might be too much, so decrease the
// proportion of the cubemap buffer actually used here:
const float cubemapUsage = 1.0;

// Number of directions in cascade 0
const int c_dRes = 16;
// Number of cascades all together
const int nCascades = 5;

// Brush radius used for drawing, measured as fraction of iResolution.y
const float brushRadius = 0.01;

// const float MAX_FLOAT = uintBitsToFloat(0x7f7fffffu);
const float PI = 3.1415927;
const float MAGIC = 1e25;

// vec2 screenRes;

// vec4 cubemapFetch(samplerCube sampler, int face, ivec2 P) {
vec4 cubemapFetch(int face, ivec2 P) {
    // Look up a single texel in a cubemap
    // ivec2 cubemapRes = textureSize(sampler, 0);
    ivec2 cubemapRes = imageSize(cascades_image_0).xy;
    if (clamp(P, ivec2(0), cubemapRes - 1) != P || face < 0 || face > 5) {
        return vec4(0.0);
    }

    // vec2 p = (vec2(P) + 0.5) / vec2(cubemapRes) * 2.0 - 1.0;
    // vec3 c;
    
    // switch (face) {
    //     case 0: c = vec3( 1.0, -p.y, -p.x); break;
    //     case 1: c = vec3(-1.0, -p.y,  p.x); break;
    //     case 2: c = vec3( p.x,  1.0,  p.y); break;
    //     case 3: c = vec3( p.x, -1.0, -p.y); break;
    //     case 4: c = vec3( p.x, -p.y,  1.0); break;
    //     case 5: c = vec3(-p.x, -p.y, -1.0); break;
    // }
    
    // return texture(sampler, normalize(c));
    vec4 data = ivec4(0);
    switch (face) {
        case 0: data = imageLoad(cascades_image_0, P); break;
        case 1: data = imageLoad(cascades_image_1, P); break;
        case 2: data = imageLoad(cascades_image_2, P); break;
        case 3: data = imageLoad(cascades_image_3, P); break;
        case 4: data = imageLoad(cascades_image_4, P); break;
        case 5: data = imageLoad(cascades_image_5, P); break;
    }
    return data;
}

vec4 cascadeFetch(int n, ivec2 p, int d) {
    // Look up the radiance interval at position p in direction d of cascade n
    // ivec2 cubemapRes = textureSize(cascadeTex, 0);
    ivec2 cubemapRes = imageSize(cascades_image_0).xy;
    ivec2 screenRes = imageSize(emissivity_image).xy;
    int nPixels = int(float(6 * cubemapRes.x * cubemapRes.y) * cubemapUsage);
    ivec2 c0_sRes = ivec2(sqrt(
        4.0 * float(nPixels) / (4.0 + float(c_dRes * (nCascades - 1))) *
        screenRes / screenRes.yx
    ));
    int cn_offset = n > 0
        ? c0_sRes.x * c0_sRes.y + (c0_sRes.x * c0_sRes.y * c_dRes * (n - 1)) / 4
        : 0;
    int cn_dRes = n == 0 ? 1 : c_dRes << 2 * (n - 1);
    ivec2 cn_sRes = c0_sRes >> n;
    p = clamp(p, ivec2(0), cn_sRes - 1);
    int i = cn_offset + d + cn_dRes * (p.x + cn_sRes.x * p.y);
    int x = i % cubemapRes.x;
    i /= cubemapRes.x;
    int y = i % cubemapRes.y;
    i /= cubemapRes.y;
    return cubemapFetch(i, ivec2(x, y));
}

const int KEY_SPACE = 32;
const int KEY_1 = 49;

// #ifndef HW_PERFORMANCE
// uniform vec4 iMouse;
// uniform sampler2D iChannel2;
// uniform float iTime;
// #endif

// bool keyToggled(int keyCode) {
//     return texelFetch(iChannel2, ivec2(keyCode, 2), 0).r > 0.0;
// }

vec3 hsv2rgb(vec3 c) {
    vec3 rgb = clamp(
        abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
        0.0,
        1.0
    );
	return c.z * mix(vec3(1.0), rgb, c.y);
}

// vec3 getEmissivity() {
//     // return !keyToggled(KEY_SPACE)
//     //     ? pow(hsv2rgb(vec3(iTime * 0.2 + 0.0f, 1.0, 2.5)), vec3(2.2))
//     //     : vec3(0.0);
//     // TODO: implement keyToggled
//     if (false){
//         return vec3(0.0);
//     }
//     else{
//         return pow(hsv2rgb(vec3(iTime * 0.2 + 0.0f, 1.0, 2.5)), vec3(2.2));
//     }
// }

float sdCircle(vec2 p, vec2 c, float r) {
    return distance(p, c) - r;
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 ap = p - a;
    vec2 ab = b - a;
    return distance(ap, ab * clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0));
}

vec4 sampleDrawing(image2D drawingTex, vec2 P) {
    // Return the drawing (in the format listed at the top of Buffer B) at P
    // vec4 data = texture(drawingTex, P / vec2(textureSize(drawingTex, 0)));
    vec4 data = imageLoad(drawingTex, ivec2(P));

    // if (keyToggled(KEY_1) && iMouse.z > 0.0) {
    //     float radius = brushRadius * screenRes.y;
    //     //float sd = sdCircle(P, iMouse.xy + 0.5, radius);
    //     float sd = sdSegment(P, abs(iMouse.zw) + 0.5, iMouse.xy + 0.5) - radius;
        
    //     if (sd <= max(data.r, 0.0)) {
    //         data = vec4(min(sd, data.r), getEmissivity());
    //     }
    // }

    return data;
}

float sdDrawing(image2D drawingTex, vec2 P) {
    // Return the signed distance for the drawing at P
    return sampleDrawing(drawingTex, P).r;
}
//================================================================================================================

void main() {
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord);
    vec4 fragColor = vec4(0.0);
    ivec2 _cascade_size = ivec2(pc.cascade_size_x, pc.cascade_size_y);
    // nCascades = pc.num_cascades; 
    ivec2 screenRes = imageSize(output_image).xy;
    // ivec2 cubemapRes = textureSize(iChannel0, 0);
    ivec2 cubemapRes = imageSize(cascades_image_0).xy;
    // vec2 iResolution = cubemapRes;

    int nPixels = int(float(6 * cubemapRes.x * cubemapRes.y) * cubemapUsage);
    ivec2 c0_sRes = ivec2(sqrt(
        4.0 * float(nPixels) / (4.0 + float(c_dRes * (nCascades - 1))) *
        screenRes / screenRes.yx
    ));
    // vec2 p = fragCoord / iResolution.xy * vec2(c0_sRes);
    vec2 p = fragCoord / screenRes.xy * vec2(c0_sRes);
    ivec2 q = ivec2(round(p)) - 1;
    vec2 w = p - vec2(q) - 0.5;
    ivec2 h = ivec2(1, 0);
    vec4 S0 = cascadeFetch(0, q + h.yy, 0);
    vec4 S1 = cascadeFetch(0, q + h.xy, 0);
    vec4 S2 = cascadeFetch(0, q + h.yx, 0);
    vec4 S3 = cascadeFetch(0, q + h.xx, 0);
    vec3 fluence = mix(mix(S0, S1, w.x), mix(S2, S3, w.x), w.y).rgb * 2.0 * PI;
    // Overlay actual SDF drawing to fix low resolution edges
    // vec4 data = sampleDrawing(emissivity_image, fragCoord);
    vec4 data = imageLoad(emissivity_image, ifragCoord);
    fluence = mix(fluence, data.gba * 2.0 * PI, clamp(3.0 - data.r, 0.0, 1.0));
    // Tonemap
    fragColor = vec4(1.0 - 1.0 / pow(1.0 + fluence, vec3(2.5)), 1.0);
    imageStore(output_image, ifragCoord, fragColor);
}