// Controls:
// Click and drag with mouse to draw
// Press space to toggle betweem emissive and non-emissive brush
// Press 1 to switch to drawing a temporary light instead of permanent

// A 2D implementation of 
// Radiance Cascades: A Novel Approach to Calculating Global Illumination
// https://drive.google.com/file/d/1L6v1_7HY2X-LV3Ofb6oyTIxgEaP4LOI6/view

// You can set the parameters to the algorithm in the Common tab

// Sky integral formula taken from
// Analytic Direct Illumination - Mathis
// https://www.shadertoy.com/view/NttSW7

// sdBezier() formula taken from
// Quadratic Bezier SDF With L2 - Envy24
// https://www.shadertoy.com/view/7sGyWd

// In this Shadertoy implementation there is a bit of temporal lag which
// is not due to a flaw in the actual algorithm, but rather a limitation
// of Shadertoy - one of the steps in the algorithm is to merge cascades
// in a reverse mipmap-like fashion which would actually be done within
// one frame, but in Shadertoy we have to split that work up over
// multiple frames. Even with this limitation, it still looks good and
// only has an n-frame delay to fully update the lighting, where n is
// the total number of cascades.

// For small point lights, a ringing artefact is visible. I couldn't
// figure out a way to fix this properly :(

// This buffer interpolates the radiance coming from cascade 0

void mainImage(out vec4 fragColor, vec2 fragCoord) {
    screenRes = iResolution.xy;
    ivec2 cubemapRes = textureSize(iChannel0, 0);
    int nPixels = int(float(6 * cubemapRes.x * cubemapRes.y) * cubemapUsage);
    ivec2 c0_sRes = ivec2(sqrt(
        4.0 * float(nPixels) / (4.0 + float(c_dRes * (nCascades - 1))) *
        iResolution.xy / iResolution.yx
    ));
    vec2 p = fragCoord / iResolution.xy * vec2(c0_sRes);
    ivec2 q = ivec2(round(p)) - 1;
    vec2 w = p - vec2(q) - 0.5;
    ivec2 h = ivec2(1, 0);
    vec4 S0 = cascadeFetch(iChannel0, 0, q + h.yy, 0);
    vec4 S1 = cascadeFetch(iChannel0, 0, q + h.xy, 0);
    vec4 S2 = cascadeFetch(iChannel0, 0, q + h.yx, 0);
    vec4 S3 = cascadeFetch(iChannel0, 0, q + h.xx, 0);
    vec3 fluence = mix(mix(S0, S1, w.x), mix(S2, S3, w.x), w.y).rgb * 2.0 * PI;
    // Overlay actual SDF drawing to fix low resolution edges
    vec4 data = sampleDrawing(iChannel1, fragCoord);
    fluence = mix(fluence, data.gba * 2.0 * PI, clamp(3.0 - data.r, 0.0, 1.0));
    // Tonemap
    fragColor = vec4(1.0 - 1.0 / pow(1.0 + fluence, vec3(2.5)), 1.0);
}