#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;
layout(set=0,binding=3,rgba32f)readonly uniform image2D distance_image;

layout(push_constant,std430)uniform Params{
    vec2 size;
    int rayCount;
    int maxSteps;
    bool showNoise;
    bool accumRadiance;
}pc;

vec2 vUv;
vec2 fragCoord;
ivec2 ifragCoord;

const float PI=3.14159265;
const float TAU=2.*PI;
const float EPS = 0.001f;

float rand(vec2 co){
    return fract(sin(dot(co.xy,vec2(12.9898,78.233)))*43758.5453);
}

bool outOfBounds(vec2 uv) {
    return uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0;
}

vec4 raymarch(){
    //vec4 light = texture(sceneTexture, vUv);
    vec4 light=imageLoad(input_image,ifragCoord);
    
    if(light.a>.1){
        return light;
    }
    
    float oneOverRayCount=1./float(pc.rayCount);
    float tauOverRayCount=TAU*oneOverRayCount;
    
    // Different noise every pixel
    float noise=pc.showNoise?rand(vUv):.1;
    
    vec4 radiance=vec4(0.);
    
    // Shoot rays in "rayCount" directions, equally spaced, with some randomness.
    for(int i=0;i<pc.rayCount;i++){
        // float angle=tauOverRayCount+(float(i)+noise);
        // vec2 rayDirectionUv=vec2(cos(angle),-sin(angle))/pc.size;
        // vec2 traveled=vec2(0.);
        
        // int initialStep=pc.accumRadiance?0:max(0,pc.maxSteps-1);
        // for(int step=initialStep;step<pc.maxSteps;step++){
        //     // Go the direction we're traveling (with noise)
        //     vec2 sampleUv=vUv+rayDirectionUv*float(step);
            
        //     if(sampleUv.x<0.||sampleUv.x>1.||sampleUv.y<0.||sampleUv.y>1.){
        //         break;
        //     }
            
        //     //   vec4 sampleLight = texture(sceneTexture, sampleUv);
        //     vec4 sampleLight=imageLoad(input_image,ivec2(sampleUv*pc.size));
        //     if(sampleLight.a>.5){
        //         radiance+=sampleLight;
        //         break;
        //     }
        // }

            // float angle = rayAngleStepSize * (float(i) + offset) + sunAngle;
            float angle=tauOverRayCount+(float(i)+noise);
            vec2 rayDirection = vec2(cos(angle), -sin(angle));
            
            vec2 sampleUv = vUv;
            vec4 radDelta = vec4(0.0);
            bool hitSurface = false;
            
            // We tested uv already (we know we aren't an object), so skip step 0.
            for (int step = 1; step < pc.maxSteps; step++) {
                // How far away is the nearest object?
                // float dist = texture(distanceTexture, sampleUv).r;
                float dist = imageLoad(distance_image, ivec2(sampleUv*pc.size)).r;
                
                // Go the direction we're traveling (with noise)
                sampleUv += rayDirection * dist;
                
                if (outOfBounds(sampleUv)) break;
                
                if (dist < EPS) {
                //   vec4 sampleColor = texture(sceneTexture, sampleUv);
                  vec4 sampleColor=imageLoad(input_image,ivec2(sampleUv*pc.size));
                  radDelta += sampleColor;
                  hitSurface = true;
                  break;
                }
            }

            // // If we didn't find an object, add some sky + sun color
            // if (!hitSurface && enableSun) {
            //   radDelta += vec4(sunAndSky(angle), 1.0);
            // }

            // Accumulate total radiance
            radiance += radDelta;
    }
    
    // Average radiance
    return radiance*oneOverRayCount;
}

void main(){
    fragCoord=gl_GlobalInvocationID.xy;
    ifragCoord=ivec2(fragCoord.xy);
    vUv=fragCoord.xy/pc.size;

    // ivec2 screen_size=imageSize(output_image).xy;
    
    // Bring up all the values to have an alpha of 1.0.
    vec4 fragColor=vec4(raymarch().rgb,1.);
    
    imageStore(output_image,ifragCoord,fragColor);
}