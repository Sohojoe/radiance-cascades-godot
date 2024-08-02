#[compute]
#version 450

// based on https://www.shadertoy.com/view/4ctXD8 / https://www.shadertoy.com/view/mtlBzX 
// by Suslik / fad 


// This buffer calculates and merges radiance cascades. Normally the
// merging would happen within one frame (like a mipmap calculation),
// meaning this technique actually has no termporal lag - but since
// Shadertoy has no way of running a pass multiple times per frame, we 
// have to resort to spreading out the merging of cascades over multiple
// frames.


layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;

// cascades was iChannel0
layout(set = 0, binding = 10, rgba32f) uniform image2D cascades_image_0;
layout(set = 0, binding = 11, rgba32f) uniform image2D cascades_image_1;
layout(set = 0, binding = 12, rgba32f) uniform image2D cascades_image_2;
layout(set = 0, binding = 13, rgba32f) uniform image2D cascades_image_3;
layout(set = 0, binding = 14, rgba32f) uniform image2D cascades_image_4;
layout(set = 0, binding = 15, rgba32f) uniform image2D cascades_image_5;
// emissivity was iChannel1
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;
layout(set=0,binding=3,rgba32f)readonly uniform image2D distance_image;

layout(push_constant, std430) uniform Params {
    int cascade_index; // Current cascade level
    int num_cascades; // Total number of cascades
    int cascade_size_x; // Size of each cascade
    int cascade_size_y; // Size of each cascade
    int merge_fix; // MERGE_FIX
} pc;

//================================================================================================================
// From Common
// #define MERGE_FIX 4

// Number of cascades all together
// const int nCascades = 6;

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
// from  cube
vec2 intersectAABB(vec2 ro, vec2 rd, vec2 a, vec2 b) {
    // Return the two intersection t-values for the intersection between a ray
    // and an axis-aligned bounding box
    vec2 ta = (a - ro) / rd;
    vec2 tb = (b - ro) / rd;
    vec2 t1 = min(ta, tb);
    vec2 t2 = max(ta, tb);
    vec2 t = vec2(max(t1.x, t1.y), min(t2.x, t2.y));
    return t.x > t.y ? vec2(-1.0) : t;
}



float intersect(vec2 ro, vec2 rd, float tMax) {
    // Return the intersection t-value for the intersection between a ray and
    // the SDF drawing from Buffer B
    // screenRes = vec2(textureSize(iChannel1, 0));
    vec2 screenRes = vec2(imageSize(input_image)).xy;
    screenRes.y = screenRes.x;  // HACK: wants a square viewport
    float tOffset = 0.0;
    // First clip the ray to the screen rectangle
    vec2 tAABB = intersectAABB(ro, rd, vec2(0.0001), screenRes - 0.0001);
    
    if (tAABB.x > tMax || tAABB.y < 0.0) {
        return -1.0;
    }
    
    if (tAABB.x > 0.0) {
        ro += tAABB.x * rd;
        tOffset += tAABB.x;
        tMax -= tAABB.x;
    }
    
    if (tAABB.y < tMax) {
        tMax = tAABB.y;
    }

    float t = 0.0;

    for (int i = 0; i < 100; i++) {
        // float d = sdDrawing(iChannel1, ro + rd * t);
        ivec2 draw_pos = ivec2(ro + rd * t);
        float d = imageLoad(distance_image, draw_pos).r;

        t += (d);
        if ((d) < 0.01)
            return t;

        if (t >= tMax) {
            break;
        }
    }

    return -1.0;
}


struct RayHit
{
    vec4 radiance;
    float dist;
};

// #if MERGE_FIX != 3 //Dolkar fix works better if miss rays terminate instead of being infinite
RayHit radiance_fix_not_3(vec2 ro, vec2 rd, float tMax) {
    // Returns the radiance and visibility term for a ray
    // vec4 p = sampleDrawing(iChannel1, ro);
    vec4 p = imageLoad(input_image, ivec2(ro));
    float d = imageLoad(distance_image, ivec2(ro)).r;
    float t = 1e6f;
    if (d > 0.0) {
        t = intersect(ro, rd, tMax);
        
        if (t == -1.0) {
            return RayHit(vec4(0.0, 0.0, 0.0, 1.0), 1e5f);
        }

        // p = sampleDrawing(iChannel1, ro + rd * t);
        p = imageLoad(input_image, ivec2(ro + rd * t));
    }

    return RayHit(vec4(p.rgb, 0.0), t);
}
// #else
RayHit radiance_fix_3(vec2 ro, vec2 rd, float tMax) {
    // Returns the radiance and visibility term for a ray
    // vec4 p = sampleDrawing(iChannel1, ro);
    vec4 p = imageLoad(input_image, ivec2(ro));
    float d = imageLoad(distance_image, ivec2(ro)).r;
    if (d > 0.0) {
        float t = intersect(ro, rd, tMax);
        
        if (t == -1.0) {
            return RayHit(vec4(0.0, 0.0, 0.0, 1.0), 1e5f);
        }

        // p = sampleDrawing(iChannel1, ro + rd * t);
        p = imageLoad(input_image, ivec2(ro + rd * t));
        return RayHit(vec4(p.rgb, 0.0), t);
    } else {
        return RayHit(vec4(0.0), 0.0);
    }
}
// #endif
RayHit radiance(vec2 ro, vec2 rd, float tMax) {
    if (pc.merge_fix == 3) {
        return radiance_fix_3(ro, rd, tMax);
    } else {
        return radiance_fix_not_3(ro, rd, tMax);
    }
}

vec3 integrateSkyRadiance_(vec2 angle) {
    // Sky radiance helper function
    float a1 = angle[1];
    float a0 = angle[0];
    
    // Sky integral formula taken from
    // Analytic Direct Illumination - Mathis
    // https://www.shadertoy.com/view/NttSW7
    const vec3 SkyColor = vec3(0.2,0.5,1.);
    const vec3 SunColor = vec3(1.,0.7,0.1)*10.;
    const float SunA = 2.0;
    const float SunS = 64.0;
    const float SSunS = sqrt(SunS);
    const float ISSunS = 1./SSunS;
    vec3 SI = SkyColor*(a1-a0-0.5*(cos(a1)-cos(a0)));
    SI += SunColor*(atan(SSunS*(SunA-a0))-atan(SSunS*(SunA-a1)))*ISSunS;
    return SI / 6.0;
}

vec3 integrateSkyRadiance(vec2 angle) {
    // Integrate the radiance from the sky over an interval of directions
    if (angle[1] < 2.0 * PI) {
        return integrateSkyRadiance_(angle);
    }
    
    return
        integrateSkyRadiance_(vec2(angle[0], 2.0 * PI)) +
        integrateSkyRadiance_(vec2(0.0, angle[1] - 2.0 * PI));
}

#define RAYS_FORK_POW 2


vec4 CastMergedInterval(vec2 screen_pos, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{
    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);

    vec2 ray_start = screen_pos * vec2(viewport_size) + dir * interval_length.x;
    vec2 ray_end = screen_pos * vec2(viewport_size) + dir * interval_length.y;                

    RayHit ray_hit = radiance(ray_start, normalize(ray_end - ray_start), length(ray_end - ray_start));

    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, prev_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    vec4 prev_interp_interval = vec4(0.0f);
    for(int i = 0; i < 4; i++)
    {
        ProbeLocation prev_probe_location;
        prev_probe_location.cascade_index = prev_cascade_index;
        prev_probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        prev_probe_location.dir_index = prev_dir_index;


        int pixel_index = ProbeLocationToPixelIndex(prev_probe_location, c0_size);
        ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);

        vec4 prev_interval = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        // if(prev_cascade_index < nCascades)
        if(prev_cascade_index < pc.num_cascades)
            prev_interval = cubemapFetch(texel_index.z, texel_index.xy);

        prev_interp_interval += prev_interval * weights[i];
    }
    return MergeIntervals(ray_hit.radiance, prev_interp_interval);
}

vec4 InterpProbeDir(ivec2 probe_index, int cascade_index, float dir_indexf)
{
    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize cascade_size = GetCascadeSize(cascade_index, c0_size);
    
    vec4 interp_interval = vec4(0.0f);
    LinearSamples dir_samples = GetLinearSamples(dir_indexf);
    vec2 weights = GetLinearWeights(dir_samples.ratio);
    for(int i = 0; i < 2; i++)
    {
        ProbeLocation probe_location;
        probe_location.cascade_index = cascade_index;
        probe_location.probe_index = probe_index;
        probe_location.dir_index = (dir_samples.base_index + i + cascade_size.dirs_count) % cascade_size.dirs_count;
        
        int pixel_index = ProbeLocationToPixelIndex(probe_location, c0_size);
        ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);
        
        vec4 prev_interval = cubemapFetch(texel_index.z, texel_index.xy);
        interp_interval += prev_interval * weights[i];
    }
    return interp_interval;
}

vec4 CastMergedIntervalParallaxFix(vec2 screen_pos, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{
    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);
    
    vec2 ray_start = screen_pos * vec2(viewport_size) + dir * interval_length.x;
    vec2 ray_end = screen_pos * vec2(viewport_size) + dir * interval_length.y;                

    RayHit ray_hit = radiance(ray_start, normalize(ray_end - ray_start), length(ray_end - ray_start));

    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, prev_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    vec4 prev_interp_interval = vec4(0.0f);
    for(int i = 0; i < 4; i++)
    {
        ivec2 prev_probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        vec2 prev_screen_pos = GetProbeScreenPos(vec2(prev_probe_index), prev_cascade_index, c0_size);
        float prev_dir_indexf = GetDirIndexf(ray_end - prev_screen_pos * vec2(viewport_size), prev_cascade_size.dirs_count);
        vec4 prev_interval = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        // if(prev_cascade_index < nCascades)
        if(prev_cascade_index < pc.num_cascades)
            prev_interval = InterpProbeDir(
                prev_probe_index,
                prev_cascade_index,
                prev_dir_indexf);

        prev_interp_interval += prev_interval * weights[i];
    }
    return MergeIntervals(ray_hit.radiance, prev_interp_interval);
}

vec4 CastMergedIntervalBilinearFix(vec2 screen_pos, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{
    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);
    
    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, prev_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    vec4 merged_interval = vec4(0.0f);
    for(int i = 0; i < 4; i++)
    {
        ProbeLocation prev_probe_location;
        prev_probe_location.cascade_index = prev_cascade_index;
        prev_probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        prev_probe_location.dir_index = prev_dir_index;


        int pixel_index = ProbeLocationToPixelIndex(prev_probe_location, c0_size);
        ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);

        vec4 prev_interval = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        // if(prev_cascade_index < nCascades)
        if(prev_cascade_index < pc.num_cascades)
            prev_interval = cubemapFetch(texel_index.z, texel_index.xy);

        vec2 prev_screen_pos = GetProbeScreenPos(vec2(prev_probe_location.probe_index), prev_probe_location.cascade_index, c0_size);

        vec2 ray_start = screen_pos * vec2(viewport_size) + dir * interval_length.x;
        vec2 ray_end = prev_screen_pos * vec2(viewport_size) + dir * interval_length.y;                

        RayHit ray_hit = radiance(ray_start, normalize(ray_end - ray_start), length(ray_end - ray_start));
        merged_interval += MergeIntervals(ray_hit.radiance, prev_interval) * weights[i];
    }
    return merged_interval;
}

vec4 CastMergedIntervalMidpointBilinearFix(vec2 screen_pos, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{

    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);
    vec2 probe_screen_size = GetProbeScreenSize(prev_cascade_index, c0_size);

    float midpoint_length = max(interval_length.x, interval_length.y - probe_screen_size.x * float(viewport_size.x) * 1.5f);
    
    vec2 ray_start_1 = screen_pos * vec2(viewport_size) + dir * interval_length.x;
    vec2 ray_end_1 = screen_pos * vec2(viewport_size) + dir * midpoint_length;                

    RayHit ray_hit_1 = radiance(ray_start_1, normalize(ray_end_1 - ray_start_1), length(ray_end_1 - ray_start_1));

    
    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, prev_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    vec4 merged_interval = vec4(0.0f);
    for(int i = 0; i < 4; i++)
    {
        ProbeLocation prev_probe_location;
        prev_probe_location.cascade_index = prev_cascade_index;
        prev_probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        prev_probe_location.dir_index = prev_dir_index;


        int pixel_index = ProbeLocationToPixelIndex(prev_probe_location, c0_size);
        ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);

        vec4 prev_interval = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        // if(prev_cascade_index < nCascades)
        if(prev_cascade_index < pc.num_cascades)
            prev_interval = cubemapFetch(texel_index.z, texel_index.xy);

        vec2 prev_screen_pos = GetProbeScreenPos(vec2(prev_probe_location.probe_index), prev_probe_location.cascade_index, c0_size);

        vec2 ray_start_2 = ray_end_1;
        vec2 ray_end_2 = prev_screen_pos * vec2(viewport_size) + dir * interval_length.y;                

        RayHit ray_hit_2 = radiance(ray_start_2, normalize(ray_end_2 - ray_start_2), length(ray_end_2 - ray_start_2));
        
        vec4 combined_interval = MergeIntervals(ray_hit_1.radiance, ray_hit_2.radiance);
        merged_interval += MergeIntervals(combined_interval, prev_interval) * weights[i];
    }
    return merged_interval;
}

vec4 CastMergedIntervalMaskFix(vec2 screen_pos, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{

    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);
    vec2 probe_screen_size = GetProbeScreenSize(prev_cascade_index, c0_size);

    vec2 ray_start = screen_pos * vec2(viewport_size) + dir * interval_length.x;
    vec2 ray_end = screen_pos * vec2(viewport_size) + dir * (interval_length.y + probe_screen_size.x * float(viewport_size.x) * 3.0f); 

    vec2 ray_dir = normalize(ray_end - ray_start);
    RayHit ray_hit = radiance(ray_start, ray_dir, length(ray_end - ray_start));

    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, prev_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    
    vec4 masks;
    for(int i = 0; i < 4; i++)
    {
        ivec2 prev_probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        vec2 prev_screen_pos = GetProbeScreenPos(vec2(prev_probe_index), prev_cascade_index, c0_size);
        
        float max_hit_dist = dot(prev_screen_pos * vec2(viewport_size) + ray_dir * interval_length.y - ray_start, ray_dir);
        masks[i] = ray_hit.dist > max_hit_dist ? 0.0f : 1.0f;
    }
    
    float interp_mask = dot(masks, weights);
    
    vec4 ray_interval = ray_hit.radiance;
    // https://www.desmos.com/calculator/2oxzmwlwhi
    ray_interval.a = 1.0 - (1.0 - ray_interval.a) * interp_mask;
    ray_interval.rgb *= 1.0 - ray_interval.a * (1.0 - interp_mask);
    
    vec4 prev_interp_interval = vec4(0.0f);
    for(int i = 0; i < 4; i++)
    {
        ProbeLocation prev_probe_location;
        prev_probe_location.cascade_index = prev_cascade_index;
        prev_probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        prev_probe_location.dir_index = prev_dir_index;


        int pixel_index = ProbeLocationToPixelIndex(prev_probe_location, c0_size);
        ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);

        vec4 prev_interval = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        // if(prev_cascade_index < nCascades)
        if(prev_cascade_index < pc.num_cascades)
            prev_interval = cubemapFetch(texel_index.z, texel_index.xy);
        prev_interp_interval += prev_interval * weights[i];
    }
    return MergeIntervals(ray_interval, prev_interp_interval);
}

vec4 CastInterpProbeDir(ivec2 probe_index, int cascade_index, vec2 interval_length, float dir_indexf)
{
    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize cascade_size = GetCascadeSize(cascade_index, c0_size);
    
    vec2 probe_screen_pos = GetProbeScreenPos(vec2(probe_index), cascade_index, c0_size);

    vec4 interp_interval = vec4(0.0f);
    LinearSamples dir_samples = GetLinearSamples(dir_indexf);
    vec2 weights = GetLinearWeights(dir_samples.ratio);
    for(int i = 0; i < 2; i++)
    {
        int dir_index = (dir_samples.base_index + i + cascade_size.dirs_count) % cascade_size.dirs_count;
        vec2 ray_dir = GetProbeDir(float(dir_index), cascade_size.dirs_count);
        
        vec2 ray_start = probe_screen_pos * vec2(viewport_size) + ray_dir * interval_length.x;
        vec2 ray_end = probe_screen_pos * vec2(viewport_size) + ray_dir * interval_length.y;                

        RayHit ray_hit = radiance(ray_start, normalize(ray_end - ray_start), length(ray_end - ray_start));
        interp_interval += ray_hit.radiance * weights[i];
    }
    return interp_interval;
}

vec4 CastMergedIntervalInnerParallaxFix(ivec2 probe_index, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{
    // ivec2 face_size = textureSize(iChannel0, 0);    
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);
    int cascade_index = prev_cascade_index - 1;
    CascadeSize cascade_size = GetCascadeSize(cascade_index, c0_size);
    vec2 probe_screen_pos = GetProbeScreenPos(vec2(probe_index), cascade_index, c0_size);
    BilinearSamples bilinear_samples = GetProbeBilinearSamples(probe_screen_pos, prev_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    vec4 merged_interval = vec4(0.0f);
    for(int i = 0; i < 4; i++)
    {
        ProbeLocation prev_probe_location;
        prev_probe_location.cascade_index = prev_cascade_index;
        prev_probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), prev_cascade_size.probes_count - ivec2(1));
        prev_probe_location.dir_index = prev_dir_index;


        int pixel_index = ProbeLocationToPixelIndex(prev_probe_location, c0_size);
        ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);

        vec4 prev_interval = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        // if(prev_cascade_index < nCascades)
        if(prev_cascade_index < pc.num_cascades)
            prev_interval = cubemapFetch(texel_index.z, texel_index.xy);

        vec2 prev_screen_pos = GetProbeScreenPos(vec2(prev_probe_location.probe_index), prev_probe_location.cascade_index, c0_size);

        vec2 ray_start = probe_screen_pos * vec2(viewport_size) + dir * interval_length.x;
        vec2 ray_end = prev_screen_pos * vec2(viewport_size) + dir * interval_length.y;
        
        vec2 ray_dir = normalize(ray_end - ray_start);
        float dir_indexf = GetDirIndexf(ray_dir, cascade_size.dirs_count);

        vec4 ray_hit_radiance = CastInterpProbeDir(probe_index, cascade_index, interval_length, dir_indexf);
        merged_interval += MergeIntervals(ray_hit_radiance, prev_interval) * weights[i];
    }
    return merged_interval;
}

//================================================================================================================

// uniform int cascade_index; // Current cascade level
// uniform int prev_cascade_index; // Previous cascade level
// uniform ivec2 cascade_size; // Size of each cascade
// uniform int num_cascades; // Total number of cascades

// void debug_main() {
//     ivec2 fragCoord = ivec2(gl_GlobalInvocationID.xy);
//     int cascade_index = pc.cascade_index;
//     vec4 fragColor = vec4(0.2, 1.0, 0.7608, 1.0);
//     imageStore(cascades_image_0, fragCoord, fragColor);
// }

// void mainCubemap(out vec4 fragColor, vec2 fragCoord, vec3 fragRO, vec3 fragRD) {
void main() {
    // debug_main();
    // return;
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord.xy);
    vec4 fragColor = vec4(1.0, 1.0, 0.0, 1.0);
    // float MAX_FLOAT = uintBitsToFloat(0x7f7fffff);
    // vec3 fragRO, vec3 fragRD;
    int face = pc.cascade_index;
    int num_cascades = pc.num_cascades;
    
    // ivec2 face_size = textureSize(iChannel0, 0);
    ivec2 face_size = imageSize(cascades_image_0).xy;
    ivec2 face_pixel = ivec2(fragCoord.xy);
    int face_index = face;
    int pixel_index = face_pixel.x + face_pixel.y * face_size.x + face_index * (face_size.x * face_size.y);
    // ivec2 viewport_size = textureSize(iChannel1, 0);
    ivec2 viewport_size = imageSize(input_image).xy;
    viewport_size.y = viewport_size.x;  // HACK: wants a square viewport
    CascadeSize c0_size = GetC0Size(viewport_size);
    ProbeLocation probe_location = PixelIndexToProbeLocation(pixel_index, c0_size);
    
    if(probe_location.cascade_index >= num_cascades)
    {
        return;
    }
    vec2 interval_overlap = vec2(1.0f, 1.0f);
    // #if MERGE_FIX == 4 || MERGE_FIX == 5 //parallax fix works better with overlapping intervals
    if (pc.merge_fix == 4 || pc.merge_fix == 5)
        interval_overlap = vec2(1.0f, 1.1f);
    // #endif
    vec2 interval_length = GetCascadeIntervalScale(probe_location.cascade_index) * GetC0IntervalLength(viewport_size) * interval_overlap;
    CascadeSize cascade_size = GetCascadeSize(probe_location.cascade_index, c0_size);
    int prev_cascade_index = probe_location.cascade_index + 1;
    CascadeSize prev_cascade_size = GetCascadeSize(prev_cascade_index, c0_size);
   
    
    vec2 screen_pos = GetProbeScreenPos(vec2(probe_location.probe_index), probe_location.cascade_index, c0_size);
    
    int avg_dirs_count = prev_cascade_size.dirs_count / cascade_size.dirs_count;
    
    vec4 merged_avg_interval = vec4(0.0f);
    for(int dir_number = 0; dir_number < avg_dirs_count; dir_number++)
    {
        int prev_dir_index = probe_location.dir_index * avg_dirs_count + dir_number;
        vec2 ray_dir = GetProbeDir(float(prev_dir_index), prev_cascade_size.dirs_count);

        vec4 merged_inteval;
        if (pc.merge_fix == 0)
            merged_inteval = CastMergedInterval(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        else if (pc.merge_fix == 1)
            merged_inteval = CastMergedIntervalBilinearFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        else if (pc.merge_fix == 2)
            merged_inteval = CastMergedIntervalMidpointBilinearFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        else if (pc.merge_fix == 3)
            merged_inteval = CastMergedIntervalMaskFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        else if (pc.merge_fix == 4)
            merged_inteval = CastMergedIntervalParallaxFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        else if (pc.merge_fix == 5)
            merged_inteval = CastMergedIntervalInnerParallaxFix(probe_location.probe_index, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        merged_avg_interval += merged_inteval / float(avg_dirs_count); 
    }
    fragColor = merged_avg_interval;
    //fragColor = vec4(0.2,0.5,1.,1);
    // imageStore(cascades_image_0, fragCoord, fragColor);
    switch (face) {
        case 0: imageStore(cascades_image_0, ifragCoord, fragColor); break;
        case 1: imageStore(cascades_image_1, ifragCoord, fragColor); break;
        case 2: imageStore(cascades_image_2, ifragCoord, fragColor); break;
        case 3: imageStore(cascades_image_3, ifragCoord, fragColor); break;
        case 4: imageStore(cascades_image_4, ifragCoord, fragColor); break;
        case 5: imageStore(cascades_image_5, ifragCoord, fragColor); break;
    }    
}