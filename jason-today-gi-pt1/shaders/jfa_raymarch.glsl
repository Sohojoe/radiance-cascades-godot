#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;
layout(set=0,binding=3,rgba32f)readonly uniform image2D distance_image;
// layout(set=0,binding=4,rgba32f)readonly uniform image2D output_prev_image;

layout(push_constant,std430)uniform Params{
    vec2 size;
    float time;
    float sunAngle;
    int rayCount;
    int maxSteps;
    bool showNoise;
    bool showGrain;
    bool enableSun;
    bool useTemporalAccum;
}pc;

vec2 vUv;
vec2 fragCoord;
ivec2 ifragCoord;

const float PI = 3.14159265;
const float TAU = 2.0 * PI;
const float ONE_OVER_TAU = 1.0 / TAU;
const float PAD_ANGLE = 0.01;
const float EPS = 0.001f;

const vec3 skyColor = vec3(0.02, 0.08, 0.2);
const vec3 sunColor = vec3(0.95, 0.95, 0.9);
const float goldenAngle = PI * 0.7639320225;

// Popular rand function
float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}

vec3 sunAndSky(float rayAngle, float sunAngle) {
    // Get the sun / ray relative angle
    float angleToSun = mod(rayAngle - sunAngle, TAU);
    
    // Sun falloff based on the angle
    float sunIntensity = smoothstep(1.0, 0.0, angleToSun);
    
    // And that's our sky radiance
    return sunColor * sunIntensity + skyColor;
}

bool outOfBounds(vec2 uv) {
return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
}

void main() {
    fragCoord=gl_GlobalInvocationID.xy;
    ifragCoord=ivec2(fragCoord.xy);
    vUv=fragCoord.xy/pc.size;
    vec4 fragColor;

    int rayCount = pc.rayCount;
    int maxSteps = pc.maxSteps;
    float time = pc.time;
    float sunAngle = pc.sunAngle;
    bool showNoise = pc.showNoise;
    bool showGrain = pc.showGrain;
    bool enableSun = pc.enableSun;
    bool useTemporalAccum = pc.useTemporalAccum;


    vec2 uv = vUv;

    // vec4 light = texture(sceneTexture, uv);
    vec4 light = imageLoad(input_image,ifragCoord);

    vec4 radiance = vec4(0.0);

    float oneOverRayCount = 1.0 / float(rayCount);
    float angleStepSize = TAU * oneOverRayCount;

    float coef = useTemporalAccum ? time : 0.0;
    float offset = showNoise ? rand(uv + coef) : 0.0;
    float rayAngleStepSize = showGrain ? angleStepSize + offset * TAU : angleStepSize;
      
    // Not light source or occluder
    if (light.a < 0.1) {    
        // Shoot rays in "rayCount" directions, equally spaced, with some randomness.
        for(int i = 0; i < rayCount; i++) {
            float angle = rayAngleStepSize * (float(i) + offset) + sunAngle;
            vec2 rayDirection = vec2(cos(angle), -sin(angle));
            
            vec2 sampleUv = uv;
            vec4 radDelta = vec4(0.0);
            bool hitSurface = false;
            
            // We tested uv already (we know we aren't an object), so skip step 0.
            for (int step = 1; step < maxSteps; step++) {
                // How far away is the nearest object?
                // float dist = texture(distanceTexture, sampleUv).r;
                float dist = imageLoad(distance_image, ivec2(sampleUv*pc.size)).r;
                
                // Go the direction we're traveling (with noise)
                sampleUv += rayDirection * dist;
                
                if (outOfBounds(sampleUv)) break;
                
                if (dist < EPS) {
                    // vec4 sampleColor = texture(sceneTexture, sampleUv);
                    vec4 sampleColor = imageLoad(input_image, ivec2(sampleUv*pc.size));

                    radDelta += sampleColor;
                    hitSurface = true;
                    break;
                }
            }

            // If we didn't find an object, add some sky + sun color
            if (!hitSurface && enableSun) {
            radDelta += vec4(sunAndSky(angle, sunAngle), 1.0);
            }

            // Accumulate total radiance
            radiance += radDelta;
        }
    } else if (length(light.rgb) >= 0.1) {
        radiance = light;
    }


    // Bring up all the values to have an alpha of 1.0.
    vec4 finalRadiance = vec4(max(light, radiance * oneOverRayCount).rgb, 1.0);
    if (useTemporalAccum && time > 0.0) {
        // vec4 prevRadiance = texture(lastFrameTexture, vUv);
        // vec4 prevRadiance = imageLoad(output_prev_image, ifragCoord);
        // fragColor = mix(finalRadiance, prevRadiance, 0.9);
        fragColor = vec4(1,1,0,1);
    } else {
        fragColor = finalRadiance;
    }
    imageStore(output_image,ifragCoord,fragColor);
}