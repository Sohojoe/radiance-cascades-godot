#[compute]
#version 450

// based on https://www.shadertoy.com/view/4ctXD8 / https://www.shadertoy.com/view/mtlBzX 
// by Suslik / fad 

// The OG shadertoy implementation of Radiance Cascades by fad: https://www.shadertoy.com/view/mtlBzX

// The goal of this implementation is to show useful design patterns for working with radiance
// cascades: interpolation, packing, handy abstractions, etc. They become increasingly important
// when working with more advanced versions of the algorithm

// Note: I only implmented Fix 4:
// MERGE_FIX = 0 -- vanilla
// MERGE_FIX = 1 -- bilinear fix
// MERGE_FIX = 2 -- bilinear fix with a midpoint
// MERGE_FIX = 3 -- the Dolkar fix
// MERGE_FIX = 4 -- parallax corrected fix

// A 2D implementation of 
// Radiance Cascades: A Novel Approach to Calculating Global Illumination
// https://drive.google.com/file/d/1L6v1_7HY2X-LV3Ofb6oyTIxgEaP4LOI6/view

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;


layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;
// layout(set = 0, binding = 1, rgba32f) readonly uniform image2D emissivity_image;
// layout(set = 0, binding = 3, rgba32f) writeonly uniform image2D output_image;
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
#define MERGE_FIX 4

// Number of cascades all together
const int nCascades = 6;

// Brush radius used for drawing, measured as fraction of iResolution.y
const float brushRadius = 0.02;

// const float MAX_FLOAT = uintBitsToFloat(0x7f7fffffu);
const float PI = 3.1415927;
const float MAGIC = 1e25;

#define probe_center vec2(0.5f)

#define BRANCHING_FACTOR 2
#define SPATIAL_SCALE_FACTOR 1

struct CascadeSize
{
    ivec2 probes_count;
    int dirs_count;
};
CascadeSize GetC0Size(ivec2 viewport_size)
{
    CascadeSize c0_size;
    #if BRANCHING_FACTOR == 0
        c0_size.probes_count = ivec2(256) * ivec2(1, viewport_size.y) / ivec2(1, viewport_size.x);//viewport_size / 10;
        c0_size.dirs_count = 64;
    #elif BRANCHING_FACTOR == 1
        c0_size.probes_count = ivec2(256) * ivec2(1, viewport_size.y) / ivec2(1, viewport_size.x);//viewport_size / 10;
        c0_size.dirs_count = 32;
    #elif BRANCHING_FACTOR == 2
        c0_size.probes_count = ivec2(512) * ivec2(1, viewport_size.y) / ivec2(1, viewport_size.x);//viewport_size / 10;
        c0_size.dirs_count = 4;
    #endif
    return c0_size;
}

float GetC0IntervalLength(ivec2 viewport_size)
{
    #if BRANCHING_FACTOR == 0
        return float(viewport_size.x) * 10.0f * 1e-2f;
    #elif BRANCHING_FACTOR == 1
        return float(viewport_size.x) * 15.0f * 1e-3f;
    #elif BRANCHING_FACTOR == 2
        return float(viewport_size.x) * 1.5f * 1e-3f;
    #endif
}

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

ivec2 roundSDim(ivec2 v) {
    // return v - (v & ivec2((1 << nCascades) - 1));
    return v - (v & ivec2((1 << pc.num_cascades) - 1));
}

float GetCascadeIntervalStartScale(int cascade_index)
{
    #if BRANCHING_FACTOR == 0
        return float(cascade_index);
    #else
        return cascade_index == 0 ? 0.0f : float(1 << (BRANCHING_FACTOR * cascade_index));
    #endif
}

vec2 GetCascadeIntervalScale(int cascade_index)
{
    return vec2(GetCascadeIntervalStartScale(cascade_index), GetCascadeIntervalStartScale(cascade_index + 1));
}

struct BilinearSamples
{
    ivec2 base_index;
    vec2 ratio;
};

vec4 GetBilinearWeights(vec2 ratio)
{
    return vec4(
        (1.0f - ratio.x) * (1.0f - ratio.y),
        ratio.x * (1.0f - ratio.y),
        (1.0f - ratio.x) * ratio.y,
        ratio.x * ratio.y);
}

ivec2 GetBilinearOffset(int offset_index)
{
    ivec2 offsets[4] = ivec2[4](ivec2(0, 0), ivec2(1, 0), ivec2(0, 1), ivec2(1, 1));
    return offsets[offset_index];
}
BilinearSamples GetBilinearSamples(vec2 pixel_index2f)
{
    BilinearSamples samples;
    samples.base_index = ivec2(floor(pixel_index2f));
    samples.ratio = fract(pixel_index2f);
    return samples;
}

struct LinearSamples
{
    int base_index;
    float ratio;
};
vec2 GetLinearWeights(float ratio)
{
    return vec2(1.0f - ratio, ratio);
}
LinearSamples GetLinearSamples(float indexf)
{
    LinearSamples samples;
    samples.base_index = int(floor(indexf));
    samples.ratio = fract(indexf);
    return samples;
}

CascadeSize GetCascadeSize(int cascade_index, CascadeSize c0_size)
{
    CascadeSize cascade_size;
    cascade_size.probes_count = max(ivec2(1), c0_size.probes_count >> (SPATIAL_SCALE_FACTOR * cascade_index));
    cascade_size.dirs_count = c0_size.dirs_count * (1 << (BRANCHING_FACTOR * cascade_index));
    return cascade_size;
}

int GetCascadeLinearOffset(int cascade_index, CascadeSize c0_size)
{
    int c0_pixels_count = c0_size.probes_count.x * c0_size.probes_count.y * c0_size.dirs_count;
    int offset = 0;
    
    for(int i = 0; i < cascade_index; i++)
    {
        CascadeSize cascade_size = GetCascadeSize(i, c0_size);
        offset += cascade_size.probes_count.x * cascade_size.probes_count.y * cascade_size.dirs_count;
    }
    return offset;
    /*#if BRANCHING_FACTOR == 2
        return c0_pixels_count * cascade_index;
    #elif BRANCHING_FACTOR == 1
        return cascade_index == 0 ? 0 : (c0_pixels_count * ((1 << cascade_index) - 1) / (1 << (cascade_index - 1)));
    #endif*/
    
}


struct ProbeLocation
{
    ivec2 probe_index;
    int dir_index;
    int cascade_index;
};
int ProbeLocationToPixelIndex(ProbeLocation probe_location, CascadeSize c0_size)
{
    CascadeSize cascade_size = GetCascadeSize(probe_location.cascade_index, c0_size);
    int probe_linear_index = probe_location.probe_index.x + probe_location.probe_index.y * cascade_size.probes_count.x;
    int offset_in_cascade = probe_linear_index * cascade_size.dirs_count + probe_location.dir_index;
    return GetCascadeLinearOffset(probe_location.cascade_index, c0_size) + offset_in_cascade ;
}

ProbeLocation PixelIndexToProbeLocation(int pixel_index, CascadeSize c0_size)
{
    ProbeLocation probe_location;

    for(
        probe_location.cascade_index = 0;
        GetCascadeLinearOffset(probe_location.cascade_index + 1, c0_size) <= pixel_index && probe_location.cascade_index < 10;
        probe_location.cascade_index++);

    int offset_in_cascade = pixel_index - GetCascadeLinearOffset(probe_location.cascade_index, c0_size);
    CascadeSize cascade_size = GetCascadeSize(probe_location.cascade_index, c0_size);
    
    probe_location.dir_index = offset_in_cascade % cascade_size.dirs_count;
    int probe_linear_index = offset_in_cascade / cascade_size.dirs_count;
    probe_location.probe_index = ivec2(probe_linear_index % cascade_size.probes_count.x, probe_linear_index / cascade_size.probes_count.x);
    return probe_location;
}
ivec3 PixelIndexToCubemapTexel(ivec2 face_size, int pixel_index)
{
    int face_pixels_count = face_size.x * face_size.y;
    int face_index = pixel_index / face_pixels_count;
    int face_pixel_index = pixel_index - face_pixels_count * face_index;
    ivec2 face_pixel = ivec2(face_pixel_index % face_size.x, face_pixel_index / face_size.x);
    return ivec3(face_pixel, face_index);
}

vec2 GetProbeScreenSize(int cascade_index, CascadeSize c0_size)
{
    vec2 c0_probe_screen_size = vec2(1.0f) / vec2(c0_size.probes_count);
    return c0_probe_screen_size * float(1 << (SPATIAL_SCALE_FACTOR * cascade_index));
}

BilinearSamples GetProbeBilinearSamples(vec2 screen_pos, int cascade_index, CascadeSize c0_size)
{
    vec2 probe_screen_size = GetProbeScreenSize(cascade_index, c0_size);
    
    vec2 prev_probe_index2f = screen_pos / probe_screen_size - probe_center;    
    return GetBilinearSamples(prev_probe_index2f);
}

vec2 GetProbeScreenPos(vec2 probe_index2f, int cascade_index, CascadeSize c0_size)
{
    vec2 probe_screen_size = GetProbeScreenSize(cascade_index, c0_size);
    
    return (probe_index2f + probe_center) * probe_screen_size;
}

vec2 GetProbeDir(float dir_indexf, int dirs_count)
{
    float ang_ratio = (dir_indexf + 0.5f) / float(dirs_count);
    float ang = ang_ratio * 2.0f * PI;
    return vec2(cos(ang), sin(ang));
}

float GetDirIndexf(vec2 dir, int dirs_count)
{
    float ang = atan(dir.y, dir.x);
    float ang_ratio = ang / (2.0f * PI);
    return ang_ratio * float(dirs_count) - 0.5f;
}

vec4 MergeIntervals(vec4 near_interval, vec4 far_interval)
{
    //return near_interval + far_interval;
    return vec4(near_interval.rgb + near_interval.a * far_interval.rgb, near_interval.a * far_interval.a);
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
    // fragCoord is the pixel coordinate, this is same for shadertoy and for compute shaders
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord.xy);
    vec4 fragColor = vec4(0.0);
    ivec2 _cascade_size = ivec2(pc.cascade_size_x, pc.cascade_size_y); // validated this to return the correct size 1024x1024

    ivec2 viewport_size = imageSize(input_image).xy; // validated this to return the correct size 1280x720
    ivec2 face_size = imageSize(cascades_image_0).xy; // validated this to return the correct size 1024x1024

    vec2 screen_pos = fragCoord.xy / vec2(viewport_size); // normalized screen position (0-1 for x and y)
    CascadeSize c0_size = GetC0Size(viewport_size);
        // c0_size.probes_count = (512, 288). 
        // c0_size.dirs_count = 4;
    int src_cascade_index = 0;


    CascadeSize cascade_size = GetCascadeSize(src_cascade_index, c0_size);
        // cascade_size.probes_count = max(ivec2(1), c0_size.probes_count >> (SPATIAL_SCALE_FACTOR * cascade_index));
        //                                                     (512, 288) >> (1 * 0) = (512, 288)
        // cascade_size.dirs_count = c0_size.dirs_count * (1 << (BRANCHING_FACTOR * cascade_index));
        //                                             4 * (1 << (2 * 0)) = 4 * 1 = 4
        // cascade_size.probes_count = (512, 288)
        // cascade_size.dirs_count = 4

    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, src_cascade_index, c0_size);
        // vec2 probe_screen_size = GetProbeScreenSize(cascade_index, c0_size);
        //     vec2 c0_probe_screen_size = vec2(1.0f) / vec2(c0_size.probes_count);
        //                                   (1.,1.) / (512, 288)  = so is this 1/512, 1/288
        //     return c0_probe_screen_size * float(1 << (SPATIAL_SCALE_FACTOR * cascade_index));
        //                           (1/512, 1/288?)  * 1 <<    1 * 0 = 1 = (1/512, 1/288)
        // so c0_probe_screen_size = (1/512, 1/288)
        // vec2 prev_probe_index2f = screen_pos / probe_screen_size - probe_center;    
        //                             normalized screen position /  (1/512, 1/288) -  vec2(0.5f)
        //  so if screen_pos = (0.5, 0.5) then prev_probe_index2f = (0.5, 0.5) / (1/512, 1/288) - (0.5, 0.5)
        //  so prev_probe_index2f = (0.5 / (1/512) -.5), 0.5 / (1/288) -.5
        //  so prev_probe_index2f = (255.5, 143.5)
        // return GetBilinearSamples(prev_probe_index2f);
        //     BilinearSamples samples;
        //     samples.base_index = ivec2(floor(pixel_index2f));
        //          so samples.base_index = (255, 143)
        //     samples.ratio = fract(pixel_index2f);
        //          so samples.ratio = (0.5, 0.5)   
        //     return samples;
        // so when screen pos is 50% of x,y screen space, the bilinear samples are
        //    bilinear_samples.base_index = (255, 143)
        //    bilinear_samples.ratio = (0.5, 0.5)

    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
        // vec4(
        //     (1.0f - ratio.x) * (1.0f - ratio.y),
        //     ratio.x * (1.0f - ratio.y),
        //     (1.0f - ratio.x) * ratio.y,
        //     ratio.x * ratio.y);
        // so when screen pos is 50% of x,y screen space, 
        //    weights = (0.25, 0.25, 0.25, 0.25)

    vec4 fluence = vec4(0.0f);
    for(int dir_index = 0; dir_index < cascade_size.dirs_count; dir_index++) // so looping from 0 to 3
    {
        for(int i = 0; i < 4; i++)
        {
            ProbeLocation probe_location;
            probe_location.cascade_index = src_cascade_index;
            probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), cascade_size.probes_count- ivec2(1));
            probe_location.dir_index = dir_index;
            // so probe_location is sampling the 4 sub points; cascade_index always 0, dir_index is 0 to 3
            // so cascade is zero because we only sample for last cascade where as dir_index is out projection into the cube nonsense
            
            int pixel_index = ProbeLocationToPixelIndex(probe_location, c0_size);
            ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);
            vec4 src_radiance = cubemapFetch(texel_index.z, texel_index.xy);
            fluence += src_radiance * weights[i] / float(cascade_size.dirs_count);
        }
    }

    // Overlay actual SDF drawing to fix low resolution edges
    //vec4 data = imageLoad(emissivity_image, fragCoord);
    //fluence = mix(fluence, data * 2.0 * PI, clamp(3.0 - data.r, 0.0, 1.0));
    // Tonemap
    //fragColor = vec4(pow(fluence / (fluence + 1.0), vec3(1.0/2.5)), 1.0);
    fragColor = vec4(1.0 - 1.0 / pow(1.0 + fluence.rgb, vec3(2.5)), 1.0);

    // // debug: show emissive layer
    // vec4 emissivity = imageLoad(emissivity_image, fragCoord);
    // fragColor = vec4(emissivity);

    // // debug: show cascades
    // if (fragCoord.x < _cascade_size.x && fragCoord.y < _cascade_size.y) {
    //     vec4 cascade = imageLoad(cascades_image_0, fragCoord);
    //     if (cascade == vec4(0.0)) {
    //         cascade = imageLoad(cascades_image_1, fragCoord);
    //     } 
    //     if (cascade == vec4(0.0)) {
    //         cascade = imageLoad(cascades_image_2, fragCoord);
    //     } 
    //     if (cascade == vec4(0.0)) {
    //         cascade = imageLoad(cascades_image_3, fragCoord);
    //     } 
    //     if (cascade == vec4(0.0)) {
    //         cascade = imageLoad(cascades_image_4, fragCoord);
    //     } 
    //     if (cascade == vec4(0.0)) {
    //         cascade = imageLoad(cascades_image_5, fragCoord);
    //     }
    //     if (cascade == vec4(0.0)) {
    //         cascade = vec4(0.3843, 1.0, 0.0, 1.0);
    //     }                                            
    //     fragColor = cascade;
    //     // fragColor = vec4(0.2,0.5,1.,1);
    // }


    // ivec3 texel_index=ivec3(fragCoord, 0);
    // fragColor = imageLoad(cascades_image_0, ifragCoord);
    // fragColor.a = 1.0;
    // fragColor = vec4(0.2,0.5,1.,1);
    // if (cascade_size.dirs_count == 4) {
    // // if (cascade_size == _cascade_size)) {
    //     fragColor = vec4(1.0, 0.0, 0.0, 1.0);
    // } else if (cascade_size.probes_count.y > 6) {
    //     fragColor = vec4(0.0, 1.0, 0.0, 1.0);
    // }
    // fragColor = vec4(fragCoord.x/ float(face_size.x), fragCoord.y/float(face_size.y),1.,1);
    // fragColor = vec4(screen_pos.x, screen_pos.y,  1.,1);fragColor
    imageStore(output_image, ifragCoord, fragColor);
}