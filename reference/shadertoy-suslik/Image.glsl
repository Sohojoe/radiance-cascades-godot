// The OG shadertoy implementation of Radiance Cascades by fad: https://www.shadertoy.com/view/mtlBzX

// The goal of this implementation is to show useful design patterns for working with radiance
// cascades: interpolation, packing, handy abstractions, etc. They become increasingly important
// when working with more advanced versions of the algorithm

// This implementation supports multiple versions of ringing fixes in Common:
// MERGE_FIX = 0 -- vanilla
// MERGE_FIX = 1 -- bilinear fix
// MERGE_FIX = 2 -- bilinear fix with a midpoint
// MERGE_FIX = 3 -- the Dolkar fix
// MERGE_FIX = 4 -- parallax corrected fix

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


// This buffer interpolates the radiance coming from cascade 0

void mainImage(out vec4 fragColor, vec2 fragCoord) {
   
    ivec2 viewport_size = ivec2(iResolution.xy);
    ivec2 face_size = textureSize(iChannel0, 0);
    
    vec2 screen_pos = fragCoord.xy / vec2(viewport_size);
    CascadeSize c0_size = GetC0Size(viewport_size);
    int src_cascade_index = 0;
    
    CascadeSize cascade_size = GetCascadeSize(src_cascade_index, c0_size);
    
    BilinearSamples bilinear_samples = GetProbeBilinearSamples(screen_pos, src_cascade_index, c0_size);
    vec4 weights = GetBilinearWeights(bilinear_samples.ratio);
    
    vec4 fluence = vec4(0.0f);
    for(int dir_index = 0; dir_index < cascade_size.dirs_count; dir_index++)
    {
        for(int i = 0; i < 4; i++)
        {
            ProbeLocation probe_location;
            probe_location.cascade_index = src_cascade_index;
            probe_location.probe_index = clamp(bilinear_samples.base_index + GetBilinearOffset(i), ivec2(0), cascade_size.probes_count- ivec2(1));
            probe_location.dir_index = dir_index;
            
            int pixel_index = ProbeLocationToPixelIndex(probe_location, c0_size);
            ivec3 texel_index = PixelIndexToCubemapTexel(face_size, pixel_index);
            vec4 src_radiance = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);
            fluence += src_radiance * weights[i] / float(cascade_size.dirs_count);
        }
    }
    
    // Overlay actual SDF drawing to fix low resolution edges
    //vec4 data = sampleDrawing(iChannel1, fragCoord);
    //fluence = mix(fluence, data * 2.0 * PI, clamp(3.0 - data.r, 0.0, 1.0));
    // Tonemap
    //fragColor = vec4(pow(fluence / (fluence + 1.0), vec3(1.0/2.5)), 1.0);
    fragColor = vec4(1.0 - 1.0 / pow(1.0 + fluence.rgb, vec3(2.5)), 1.0);
}