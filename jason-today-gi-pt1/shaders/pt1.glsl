#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

// layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D output_image;
layout(set=0,binding=1,rgba32f)uniform image2D output_image;

layout(push_constant,std430)uniform Params{
    int rayCount;
    int maxSteps;
    bool showNoise;
    bool accumRadiance;
    vec2 size;
}pc;

vec2 vUv;

const float PI = 3.14159265;
const float TAU = 2.0 * PI;

float rand(vec2 co) {
    return fract(sin(dot(co.xy ,vec2(12.9898,78.233))) * 43758.5453);
}



bool outOfBounds(vec2 uv){
    return uv.x<0.||uv.x>1.||uv.y<0.||uv.y>1.;
}

vec4 raymarch(){
    vec4 light=texture(sceneTexture,vUv);
    
    if(light.a>.1){
        return light;
    }
    
    float oneOverRayCount=1./float(rayCount);
    float tauOverRayCount=TAU*oneOverRayCount;
    
    // Distinct random value for every pixel
    float noise=rand(vUv);
    
    vec4 radiance=vec4(0.);
    
    for(int i=0;i<rayCount;i++){
        float angle=tauOverRayCount+(float(i)+noise);
        vec2 rayDirectionUv=vec2(cos(angle),-sin(angle))/size;
        
        // Our current position, plus one step.
        vec2 sampleUv=vUv+rayDirectionUv;
        
        for(int step=0;step<maxSteps;step++){
            if(outOfBounds(sampleUv))break;
            
            vec4 sampleLight=texture(sceneTexture,sampleUv);
            if(sampleLight.a>.1){
                radiance+=sampleLight;
                break;
            }
            
            sampleUv+=rayDirectionUv;
            
        }
    }
    return radiance*oneOverRayCount;
}

void main(){
    vec2 fragCoord=gl_GlobalInvocationID.xy;
    ivec2 ifragCoord=ivec2(fragCoord.xy);
    
    ivec2 screen_size=imageSize(output_image).xy;
    vec4 fragColor=vec4(ifragCoord.x/float(screen_size.x),ifragCoord.y/float(screen_size.y),0.,1.);
    
    // vec4 current = texture(inputTexture, vUv);
    vec4 current=imageLoad(output_image,ifragCoord);
    vec2 from=vec2(25,25);
    vec2 to=vec2(75,75);
    float radius=5.;
    float radiusSquared=radius*radius;
    // vec3 color = fragColor.rgb;
    vec3 color=vec3(1.,1.,0.);
    
    // If we aren't actively drawing (or on mobile) no-op!
    if(true){
        // vec2 coord = vUv * resolution;
        vec2 coord=fragCoord;
        if(sdfLineSquared(coord,from,to)<=radiusSquared){
            current=vec4(color,1.);
        }
    }
    fragColor=current;
    
    imageStore(output_image,ifragCoord,fragColor);
}