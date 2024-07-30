#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

// layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
layout(set=0,binding=1,rgba32f) uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;

layout(push_constant,std430)uniform Params{
    float radiusSquared;
    bool drawing;
    vec2 from;
    vec2 to;
    vec2 resolution;
    vec3 color;
}pc;

vec2 vUv;

// Draw a line shape!
float sdfLineSquared(vec2 p,vec2 from,vec2 to){
    vec2 toStart=p-from;
    vec2 line=to-from;
    float lineLengthSquared=dot(line,line);
    float t=clamp(dot(toStart,line)/lineLengthSquared,0.,1.);
    vec2 closestVector=toStart-line*t;
    return dot(closestVector,closestVector);
}

void main(){
    vec2 fragCoord=gl_GlobalInvocationID.xy;
    ivec2 ifragCoord=ivec2(fragCoord.xy);
    ivec2 screen_size=imageSize(output_image).xy;
    vUv=fragCoord.xy/pc.resolution;

    vec4 fragColor=imageLoad(output_image, ifragCoord);
    
    // If we aren't actively drawing (or on mobile) no-op!
    if(pc.drawing){
        if(sdfLineSquared(fragCoord,pc.from,pc.to)<=pc.radiusSquared){
            fragColor=vec4(pc.color,1.);
        }
    }
    
    imageStore(output_image,ifragCoord,fragColor);
}