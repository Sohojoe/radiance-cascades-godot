// This buffer calculates and merges radiance cascades. Normally the
// merging would happen within one frame (like a mipmap calculation),
// meaning this technique actually has no termporal lag - but since
// Shadertoy has no way of running a pass multiple times per frame, we 
// have to resort to spreading out the merging of cascades over multiple
// frames.

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
    screenRes = vec2(textureSize(iChannel1, 0));
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
        float d = sdDrawing(iChannel1, ro + rd * t);
        
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
#if MERGE_FIX != 3 //Dolkar fix works better if miss rays terminate instead of being infinite
RayHit radiance(vec2 ro, vec2 rd, float tMax) {
    // Returns the radiance and visibility term for a ray
    vec4 p = sampleDrawing(iChannel1, ro);
    float t = 1e6f;
    if (p.r > 0.0) {
        t = intersect(ro, rd, tMax);
        
        if (t == -1.0) {
            return RayHit(vec4(0.0, 0.0, 0.0, 1.0), 1e5f);
        }

        p = sampleDrawing(iChannel1, ro + rd * t);
    }

    return RayHit(vec4(p.gba, 0.0), t);
}
#else
RayHit radiance(vec2 ro, vec2 rd, float tMax) {
    // Returns the radiance and visibility term for a ray
    vec4 p = sampleDrawing(iChannel1, ro);
    if (p.r > 0.0) {
        float t = intersect(ro, rd, tMax);
        
        if (t == -1.0) {
            return RayHit(vec4(0.0, 0.0, 0.0, 1.0), 1e5f);
        }

        p = sampleDrawing(iChannel1, ro + rd * t);
        return RayHit(vec4(p.gba, 0.0), t);
    } else {
        return RayHit(vec4(0.0), 0.0);
    }
}
#endif

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
    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        if(prev_cascade_index < nCascades)
            prev_interval = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);

        prev_interp_interval += prev_interval * weights[i];
    }
    return MergeIntervals(ray_hit.radiance, prev_interp_interval);
}

vec4 InterpProbeDir(ivec2 probe_index, int cascade_index, float dir_indexf)
{
    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        
        vec4 prev_interval = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);
        interp_interval += prev_interval * weights[i];
    }
    return interp_interval;
}

vec4 CastMergedIntervalParallaxFix(vec2 screen_pos, vec2 dir, vec2 interval_length, int prev_cascade_index, int prev_dir_index)
{
    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        if(prev_cascade_index < nCascades)
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
    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        if(prev_cascade_index < nCascades)
            prev_interval = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);

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

    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        if(prev_cascade_index < nCascades)
            prev_interval = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);

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

    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        if(prev_cascade_index < nCascades)
            prev_interval = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);
        prev_interp_interval += prev_interval * weights[i];
    }
    return MergeIntervals(ray_interval, prev_interp_interval);
}

vec4 CastInterpProbeDir(ivec2 probe_index, int cascade_index, vec2 interval_length, float dir_indexf)
{
    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
    ivec2 face_size = textureSize(iChannel0, 0);    
    ivec2 viewport_size = textureSize(iChannel1, 0);
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
        if(prev_cascade_index < nCascades)
            prev_interval = cubemapFetch(iChannel0, texel_index.z, texel_index.xy);

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


void mainCubemap(out vec4 fragColor, vec2 fragCoord, vec3 fragRO, vec3 fragRD) {
    // Calculate the index for this cubemap texel
    int face;
    
    if (abs(fragRD.x) > abs(fragRD.y) && abs(fragRD.x) > abs(fragRD.z)) {
        face = fragRD.x > 0.0 ? 0 : 1;
    } else if (abs(fragRD.y) > abs(fragRD.z)) {
        face = fragRD.y > 0.0 ? 2 : 3;
    } else {
        face = fragRD.z > 0.0 ? 4 : 5;
    }
    
    ivec2 face_size = textureSize(iChannel0, 0);
    
    ivec2 face_pixel = ivec2(fragCoord.xy);
    int face_index = face;
    int pixel_index = face_pixel.x + face_pixel.y * face_size.x + face_index * (face_size.x * face_size.y);
    
    ivec2 viewport_size = textureSize(iChannel1, 0);
    CascadeSize c0_size = GetC0Size(viewport_size);
    ProbeLocation probe_location = PixelIndexToProbeLocation(pixel_index, c0_size);
    
    if(probe_location.cascade_index >= nCascades)
    {
        fragColor = vec4(0.0f, 0.0f, 0.0f, 1.0f);
        return;
    }
    vec2 interval_overlap = vec2(1.0f, 1.0f);
    #if MERGE_FIX == 4 || MERGE_FIX == 5 //parallax fix works better with overlapping intervals
        interval_overlap = vec2(1.0f, 1.1f);
    #endif
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
        
        #if MERGE_FIX == 0
            vec4 merged_inteval = CastMergedInterval(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        #elif MERGE_FIX == 1
            vec4 merged_inteval = CastMergedIntervalBilinearFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        #elif MERGE_FIX == 2
            vec4 merged_inteval = CastMergedIntervalMidpointBilinearFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        #elif MERGE_FIX == 3
            vec4 merged_inteval = CastMergedIntervalMaskFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        #elif MERGE_FIX == 4
            vec4 merged_inteval = CastMergedIntervalParallaxFix(screen_pos, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        #elif MERGE_FIX == 5
            vec4 merged_inteval = CastMergedIntervalInnerParallaxFix(probe_location.probe_index, ray_dir, interval_length, prev_cascade_index, prev_dir_index);
        #endif
        merged_avg_interval += merged_inteval / float(avg_dirs_count);  
    }
    fragColor = merged_avg_interval;
}