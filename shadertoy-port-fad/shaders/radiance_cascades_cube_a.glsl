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
layout(set = 0, binding = 1, rgba32f) uniform image2D emissivity_image;

layout(push_constant, std430) uniform Params {
    int cascade_index; // Current cascade level
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
    vec2 screenRes = imageSize(emissivity_image).xy;
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
        float d = imageLoad(emissivity_image, ivec2(ro + rd * t)).r;
        t += abs(d);

        if (t >= tMax) {
            break;
        }

        if (0.2 < t && d < 1.0) {
            return tOffset + t;
        }
    }

    return -1.0;
}


struct RayHit
{
    vec4 radiance;
    float dist;
};

vec4 radiance(vec2 ro, vec2 rd, float tMax) {
    // Returns the radiance and visibility term for a ray
    // vec4 p = sampleDrawing(iChannel1, ro);
    vec4 p = imageLoad(emissivity_image, ivec2(ro));

    if (p.r > 0.0) {
        float t = intersect(ro, rd, tMax);
        
        if (t == -1.0) {
            return vec4(0.0, 0.0, 0.0, 1.0);
        }

        // p = sampleDrawing(iChannel1, ro + rd * t);
        p = imageLoad(emissivity_image, ivec2(ro + rd * t));
    }

    return vec4(p.gba, 0.0);
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

//================================================================================================================


// void mainCubemap(out vec4 fragColor, vec2 fragCoord, vec3 fragRO, vec3 fragRD) {
void main() {
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord);
    vec4 fragColor = vec4(1.0, 1.0, 0.0, 1.0);
    // float MAX_FLOAT = uintBitsToFloat(0x7f7fffff);
    // vec3 fragRO, vec3 fragRD;
    int face = pc.cascade_index; // shadertoy had 6 faces but 5 cascades
    // nCascades = pc.num_cascades;
    vec2 screenRes = imageSize(emissivity_image).xy;
    ivec2 cubemapRes = imageSize(cascades_image_0).xy;
    // vec2 iResolution = cubemapRes;
    
    int i =
        int(fragCoord.x) + int(screenRes.x) *
        (int(fragCoord.y) + int(screenRes.y) * face);
    // Figure out which cascade this pixel is in
    int nPixels = int(float(6 * int(screenRes.x) * int(screenRes.y)) * cubemapUsage);
    ivec2 c0_sRes = ivec2(sqrt(
        4.0 * float(nPixels) / (4.0 + float(c_dRes * (nCascades - 1))) *
        screenRes / screenRes.yx
    ));
    int c_size =
        c0_sRes.x * c0_sRes.y +
        c0_sRes.x * c0_sRes.y * c_dRes * (nCascades - 1) / 4;    
    
    if (i >= c_size) {
        return;
    }
    
    int n = i < c0_sRes.x * c0_sRes.y ? 0 : int(
        (4.0 * float(i) / float(c0_sRes.x * c0_sRes.y) - 4.0) / float(c_dRes)
        + 1.0
    );
    // Figure out this pixel's index within its own cascade
    int j = i - (n > 0
        ? c0_sRes.x * c0_sRes.y + (c0_sRes.x * c0_sRes.y * c_dRes * (n - 1)) / 4
        : 0);
    // Calculate this cascades spatial and directional resolution
    ivec2 cn_sRes = c0_sRes >> n;
    int cn_dRes = n == 0 ? 1 : c_dRes << 2 * (n - 1);
    // Calculate this pixel's direction and position indices
    int d = j % cn_dRes;
    j /= cn_dRes;
    ivec2 p = ivec2(j % cn_sRes.x, 0);
    j /= cn_sRes.x;
    p.y = j;
    int nDirs = c_dRes << 2 * n;
    // Calculate this pixel's ray interval
    vec2 ro = (vec2(p) + 0.5) / vec2(cn_sRes) * screenRes;
    float c0_intervalLength = 
        length(screenRes) * 4.0 / (float(1 << 2 * nCascades) - 1.0);
    float t1 = c0_intervalLength;
    float tMin = n == 0 ? 0.0 : t1 * float(1 << 2 * (n - 1));
    float tMax = t1 * float(1 << 2 * n);
    vec4 s = vec4(0.0);
    
    // Calculate radiance intervals and merge with above cascade
    for (int i = 0; i < nDirs / cn_dRes; ++i) {
        int j = 4 * d + i;
        float angle = (float(j) + 0.5) / float(nDirs) * 2.0 * PI;
        vec2 rd = vec2(cos(angle), sin(angle));
        vec4 si = radiance(ro + rd * tMin, rd, tMax - tMin);
        
        // If the visibility term is non-zero
        if (si.a != 0.0) {
            if (n == nCascades - 1) {
                // If we are the top-level cascade, then there's no other
                // cascade to merge with, so instead merge with the sky radiance
                vec2 angle = vec2(j, j + 1) / float(nDirs) * 2.0 * PI;
                si.rgb += integrateSkyRadiance(angle) / (angle.y - angle.x);
            } else {
                // Otherwise, find the radiance coming from the above cascade in
                // this direction by interpolating the above cascades
                vec2 pf = (vec2(p) + 0.5) / 2.0;
                ivec2 q = ivec2(round(pf)) - 1;
                vec2 w = pf - vec2(q) - 0.5;
                ivec2 h = ivec2(1, 0);
                vec4 S0 = cascadeFetch(n + 1, q + h.yy, j);
                vec4 S1 = cascadeFetch(n + 1, q + h.xy, j);
                vec4 S2 = cascadeFetch(n + 1, q + h.yx, j);
                vec4 S3 = cascadeFetch(n + 1, q + h.xx, j);
                vec4 S = mix(mix(S0, S1, w.x), mix(S2, S3, w.x), w.y);
                si.rgb += si.a * S.rgb;
                si.a *= S.a;
            }
        }
        
        s += si;
    }
    
    s /= float(nDirs / cn_dRes);
    fragColor = s;

    switch (face) {
        case 0: imageStore(cascades_image_0, ifragCoord, fragColor); break;
        case 1: imageStore(cascades_image_1, ifragCoord, fragColor); break;
        case 2: imageStore(cascades_image_2, ifragCoord, fragColor); break;
        case 3: imageStore(cascades_image_3, ifragCoord, fragColor); break;
        case 4: imageStore(cascades_image_4, ifragCoord, fragColor); break;
        case 5: imageStore(cascades_image_5, ifragCoord, fragColor); break;
    }    
}