// SDF drawing logic from 
// Smooth Mouse Drawing - fad
// https://www.shadertoy.com/view/dldXR7

// This buffer tracks smoothed mouse positions over multiple frames.

// See https://lazybrush.dulnan.net/ for what these mean:
#define RADIUS (iResolution.y * 0.015)
#define FRICTION 0.05

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    if (fragCoord.y != 0.5 || fragCoord.x > 3.0) {
        return;
    }

    if (iFrame == 0) {
        if (fragCoord.x == 2.5) {
            fragColor = iMouse;
        } else {
            fragColor = vec4(0.0);
        }
        
        return;
    }
    
    vec4 iMouse = iMouse;
    
    if (iMouse == vec4(0.0)) {
        float t = iTime * 3.0;
        iMouse.xy = vec2(
            cos(3.14159 * t) + sin(0.72834 * t + 0.3),
            sin(2.781374 * t + 3.47912) + cos(t)
        ) * 0.25 + 0.5;
        iMouse.xy *= iResolution.xy;
        iMouse.z = MAGIC;
    }
    
    vec4 mouseA = texelFetch(iChannel0, ivec2(1, 0), 0);
    vec4 mouseB = texelFetch(iChannel0, ivec2(2, 0), 0);
    vec4 mouseC;
    mouseC.zw = iMouse.zw;
    float dist = distance(mouseB.xy, iMouse.xy);
    
    if (mouseB.z > 0.0 && (mouseB.z != MAGIC || iMouse.z == MAGIC) && dist > 0.0) {
        vec2 dir = (iMouse.xy - mouseB.xy) / dist;
        float len = max(dist - RADIUS, 0.0);
        float ease = 1.0 - pow(FRICTION, iTimeDelta * 10.0);
        mouseC.xy = mouseB.xy + dir * len * ease;
    } else {
        mouseC.xy = iMouse.xy;
    }
    
    if (fragCoord.x == 0.5) {
        fragColor = mouseA;
    } else if (fragCoord.x == 1.5) {
        fragColor = mouseB.z == MAGIC && iMouse.z != MAGIC ? vec4(0.0) : mouseB;
    } else {
        fragColor = mouseC;
    }
}