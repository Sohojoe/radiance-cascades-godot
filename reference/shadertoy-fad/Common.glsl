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

const float MAX_FLOAT = uintBitsToFloat(0x7f7fffffu);
const float PI = 3.1415927;
const float MAGIC = 1e25;

vec2 screenRes;

vec4 cubemapFetch(samplerCube sampler, int face, ivec2 P) {
    // Look up a single texel in a cubemap
    ivec2 cubemapRes = textureSize(sampler, 0);
    if (clamp(P, ivec2(0), cubemapRes - 1) != P || face < 0 || face > 5) {
        return vec4(0.0);
    }

    vec2 p = (vec2(P) + 0.5) / vec2(cubemapRes) * 2.0 - 1.0;
    vec3 c;
    
    switch (face) {
        case 0: c = vec3( 1.0, -p.y, -p.x); break;
        case 1: c = vec3(-1.0, -p.y,  p.x); break;
        case 2: c = vec3( p.x,  1.0,  p.y); break;
        case 3: c = vec3( p.x, -1.0, -p.y); break;
        case 4: c = vec3( p.x, -p.y,  1.0); break;
        case 5: c = vec3(-p.x, -p.y, -1.0); break;
    }
    
    return texture(sampler, normalize(c));
}

vec4 cascadeFetch(samplerCube cascadeTex, int n, ivec2 p, int d) {
    // Look up the radiance interval at position p in direction d of cascade n
    ivec2 cubemapRes = textureSize(cascadeTex, 0);
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
    return cubemapFetch(cascadeTex, i, ivec2(x, y));
}

const int KEY_SPACE = 32;
const int KEY_1 = 49;

#ifndef HW_PERFORMANCE
uniform vec4 iMouse;
uniform sampler2D iChannel2;
uniform float iTime;
#endif

bool keyToggled(int keyCode) {
    return texelFetch(iChannel2, ivec2(keyCode, 2), 0).r > 0.0;
}

vec3 hsv2rgb(vec3 c) {
    vec3 rgb = clamp(
        abs(mod(c.x * 6.0 + vec3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
        0.0,
        1.0
    );
	return c.z * mix(vec3(1.0), rgb, c.y);
}

vec3 getEmissivity() {
    return !keyToggled(KEY_SPACE)
        ? pow(hsv2rgb(vec3(iTime * 0.2, 1.0, 0.8)), vec3(2.2))
        : vec3(0.0);
}

float sdCircle(vec2 p, vec2 c, float r) {
    return distance(p, c) - r;
}

float sdSegment(vec2 p, vec2 a, vec2 b) {
    vec2 ap = p - a;
    vec2 ab = b - a;
    return distance(ap, ab * clamp(dot(ap, ab) / dot(ab, ab), 0.0, 1.0));
}

vec4 sampleDrawing(sampler2D drawingTex, vec2 P) {
    // Return the drawing (in the format listed at the top of Buffer B) at P
    vec4 data = texture(drawingTex, P / vec2(textureSize(drawingTex, 0)));
    
    if (keyToggled(KEY_1) && iMouse.z > 0.0) {
        float radius = brushRadius * screenRes.y;
        //float sd = sdCircle(P, iMouse.xy + 0.5, radius);
        float sd = sdSegment(P, abs(iMouse.zw) + 0.5, iMouse.xy + 0.5) - radius;
        
        if (sd <= max(data.r, 0.0)) {
            data = vec4(min(sd, data.r), getEmissivity());
        }
    }

    return data;
}

float sdDrawing(sampler2D drawingTex, vec2 P) {
    // Return the signed distance for the drawing at P
    return sampleDrawing(drawingTex, P).r;
}