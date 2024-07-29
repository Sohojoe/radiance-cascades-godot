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

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    vec4 data = texelFetch(iChannel1, ivec2(fragCoord), 0);
    float sd = iFrame != 0 ? data.r : MAX_FLOAT;
    vec3 emissivity = iFrame != 0 ? data.gba : vec3(0.0);
    vec4 mouseA = iFrame > 0 ? texelFetch(iChannel0, ivec2(0, 0), 0) : vec4(0.0);
    vec4 mouseB = iFrame > 0 ? texelFetch(iChannel0, ivec2(1, 0), 0) : vec4(0.0);
    vec4 mouseC = iFrame > 0 ? texelFetch(iChannel0, ivec2(2, 0), 0) : iMouse;
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
    
    if (
        d < max(0.0, sd) && !keyToggled(KEY_1) &&
        (mouseC.z != MAGIC || cos(iTime * 20.0) > 0.5)
    ) {
        sd = min(d, sd);
        emissivity = getEmissivity() * float(mouseC.z != MAGIC || cos(iTime * 10.0) > 0.5);
    }
    
    fragColor = vec4(sd, emissivity);
}