#[compute]
#version 450

// based on https://www.shadertoy.com/view/4ctXD8 / https://www.shadertoy.com/view/mtlBzX 
// by Suslik / fad 

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;

// Output Buffer
// layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D emissivity_image;
layout(set = 0, binding = 1, rgba32f) uniform image2D emissivity_image;

// input buffer
// layout(set = 0, binding = 2, rgba32f) readonly uniform image2D iChannel1;
// // layout(binding = 2, rgba32f) uniform sampler2D iChannel1;

layout(push_constant, std430) uniform Params {
    vec4 iMouse;
    vec4 mouseA;
    vec4 mouseB;
    vec4 mouseC;
    int iFrame; // used to determine if the buffer is being initialized
	int brush_type;
	int clear_screen;
    float iTime;
    vec2 iResolution;
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

vec3 getEmissivity(float iTime) {
//     // return !keyToggled(KEY_SPACE)
//     //     ? pow(hsv2rgb(vec3(iTime * 0.2 + 0.0f, 1.0, 2.5)), vec3(2.2))
//     //     : vec3(0.0);
//     // TODO: implement keyToggled
//     if (false){
//         return vec3(0.0);
//     }
//     else{
        return pow(hsv2rgb(vec3(iTime * 0.2, 1.0, 0.8)), vec3(2.2));
//     }
}

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
// From beffer b

// This buffer draws the SDF:
// .r stores signed distance
// .gba stores emissivity

// SDF drawing logic from 
// Smooth Mouse Drawing - fad
// https://www.shadertoy.com/view/dldXR7

// solveQuadratic(), solveCubic(), solve() and sdBezier() are from
// Quadratic Bezier SDF With L2 - Envy24
// https://www.shadertoy.com/view/7sGyWd
// with modification. Thank you! I tried a lot of different sdBezier()
// implementations from across Shadertoy (including trying to make it
// myself) and all of them had bugs and incorrect edge case handling
// except this one.

int solveQuadratic(float a, float b, float c, out vec2 roots) {
    // Return the number of real roots to the equation
    // a*x^2 + b*x + c = 0 where a != 0 and populate roots.
    float discriminant = b * b - 4.0 * a * c;

    if (discriminant < 0.0) {
        return 0;
    }

    if (discriminant == 0.0) {
        roots[0] = -b / (2.0 * a);
        return 1;
    }

    float SQRT = sqrt(discriminant);
    roots[0] = (-b + SQRT) / (2.0 * a);
    roots[1] = (-b - SQRT) / (2.0 * a);
    return 2;
}

int solveCubic(float a, float b, float c, float d, out vec3 roots) {
    // Return the number of real roots to the equation
    // a*x^3 + b*x^2 + c*x + d = 0 where a != 0 and populate roots.
    const float TAU = 6.2831853071795862;
    float A = b / a;
    float B = c / a;
    float C = d / a;
    float Q = (A * A - 3.0 * B) / 9.0;
    float R = (2.0 * A * A * A - 9.0 * A * B + 27.0 * C) / 54.0;
    float S = Q * Q * Q - R * R;
    float sQ = sqrt(abs(Q));
    roots = vec3(-A / 3.0);

    if (S > 0.0) {
        roots += -2.0 * sQ * cos(acos(R / (sQ * abs(Q))) / 3.0 + vec3(TAU, 0.0, -TAU) / 3.0);
        return 3;
    }
    
    if (Q == 0.0) {
        roots[0] += -pow(C - A * A * A / 27.0, 1.0 / 3.0);
        return 1;
    }
    
    if (S < 0.0) {
        float u = abs(R / (sQ * Q));
        float v = Q > 0.0 ? cosh(acosh(u) / 3.0) : sinh(asinh(u) / 3.0);
        roots[0] += -2.0 * sign(R) * sQ * v;
        return 1;
    }
    
    roots.xy += vec2(-2.0, 1.0) * sign(R) * sQ;
    return 2;
}

int solve(float a, float b, float c, float d, out vec3 roots) {
    // Return the number of real roots to the equation
    // a*x^3 + b*x^2 + c*x + d = 0 and populate roots.
    if (a == 0.0) {
        if (b == 0.0) {
            if (c == 0.0) {
                return 0;
            }
            
            roots[0] = -d/c;
            return 1;
        }
        
        vec2 r;
        int num = solveQuadratic(b, c, d, r);
        roots.xy = r;
        return num;
    }
    
    return solveCubic(a, b, c, d, roots);
}

float sdBezier(vec2 p, vec2 a, vec2 b, vec2 c) {
    vec2 A = a - 2.0 * b + c;
    vec2 B = 2.0 * (b - a);
    vec2 C = a - p;
    vec3 T;
    int num = solve(
        2.0 * dot(A, A),
        3.0 * dot(A, B),
        2.0 * dot(A, C) + dot(B, B),
        dot(B, C),
        T
    );
    T = clamp(T, 0.0, 1.0);
    float best = 1e30;
    
    for (int i = 0; i < num; ++i) {
        float t = T[i];
        float u = 1.0 - t;
        vec2 d = u * u * a + 2.0 * t * u * b + t * t * c - p;
        best = min(best, dot(d, d));
    }
    
    return sqrt(best);
}


void main() {
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord);
    vec4 fragColor = vec4(0.0);
    float MAX_FLOAT = uintBitsToFloat(0x7f7fffff);

    if (pc.clear_screen == 1) {
        fragColor = vec4(MAX_FLOAT, vec3(0.0));
        imageStore(emissivity_image, ifragCoord, fragColor);
        return;
    }    
    vec2 screenRes = imageSize(emissivity_image).xy;
    ivec3 iResolution = ivec3(screenRes, 1);
    vec4 mouseA = pc.mouseA;
    vec4 mouseB = pc.mouseB;
    vec4 mouseC = pc.mouseC;
    int iFrame = pc.iFrame;
    bool key_1 = false; // TODO: implement keyToggled
    float iTime = pc.iTime;

    // vec4 data = texelFetch(iChannel1, ivec2(fragCoord), 0);
    // vec4 data = texelFetch(iChannel1, fragCoord, 0);
    vec4 data = imageLoad(emissivity_image, ifragCoord);
    
    float sd = iFrame != 0 ? data.r : MAX_FLOAT;
    vec3 emissivity = iFrame != 0 ? data.gba : vec3(0.0);
    // vec4 mouseA = iFrame > 0 ? texelFetch(iChannel0, ivec2(0, 0), 0) : vec4(0.0);
    // vec4 mouseB = iFrame > 0 ? texelFetch(iChannel0, ivec2(1, 0), 0) : vec4(0.0);
    // vec4 mouseC = iFrame > 0 ? texelFetch(iChannel0, ivec2(2, 0), 0) : iMouse;
    mouseA.xy += 0.5;
    mouseB.xy += 0.5;
    mouseC.xy += 0.5;
    float d = MAX_FLOAT;
    
    if (mouseB.z <= 0.0 && mouseC.z > 0.0) {
        d = distance(fragCoord, mouseC.xy);
    } else if (mouseA.z <= 0.0 && mouseB.z > 0.0 && mouseC.z > 0.0) {
        d = sdSegment(fragCoord, mouseB.xy, mix(mouseB.xy, mouseC.xy, 0.5));
    } else if (mouseA.z > 0.0 && mouseB.z > 0.0 && mouseC.z > 0.0) {
        d = sdBezier(
            fragCoord,
            mix(mouseA.xy, mouseB.xy, 0.5),
            mouseB.xy,
            mix(mouseB.xy, mouseC.xy, 0.5)
        );
    } else if (mouseA.z > 0.0 && mouseB.z > 0.0 && mouseC.z <= 0.0) {
        d = sdSegment(fragCoord, mix(mouseA.xy, mouseB.xy, 0.5), mouseB.xy);
    }
    
    d -= brushRadius * iResolution.y;
    
    if (d < max(0.0, sd)) {
        emissivity = getEmissivity(iTime);
        switch (pc.brush_type) {
            default:
            case 0:
                sd = min(d, sd);
                emissivity = getEmissivity(iTime);
                break;
            case 1:
                sd = d;
                emissivity = vec3(0.0);
                break;
            // case 2:
            //     sd = MAX_FLOAT;
            //     emissivity = vec3(0.0);
            //     break;
        }

    }

    fragColor = vec4(sd, emissivity);


    // Output the final color to the storage image
    imageStore(emissivity_image, ifragCoord, fragColor);

}