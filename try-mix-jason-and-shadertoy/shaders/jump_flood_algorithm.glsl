#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
// layout(set=0,binding=1,rgba32f)uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;

layout(push_constant,std430)uniform Params{
    vec2 oneOverSize;
    float uOffset;
    bool skip;
}pc;

const float FLT_MAX = 3.4028235e38;

const vec2 offsets[9] = vec2[9](
    vec2(-1.0, -1.0),
    vec2(-1.0, 0.0),
    vec2(-1.0, 1.0),
    vec2(0.0, -1.0),
    vec2(0.0, 0.0),
    vec2(0.0, 1.0),
    vec2(1.0, -1.0),
    vec2(1.0, 0.0),
    vec2(1.0, 1.0)
);


void main(){
    vec2 fragCoord=gl_GlobalInvocationID.xy;
    ivec2 ifragCoord=ivec2(fragCoord.xy);
    ivec2 input_image_size=imageSize(input_image).xy;
    vec2 vUv=fragCoord.xy/input_image_size;

    float closest_dist = FLT_MAX;
    vec4 closest_data = vec4(0.0);

    for(int i = 0; i < 9; i++) {
        ivec2 jump = ifragCoord + ivec2(offsets[i] * pc.uOffset);
        if (any(lessThan(jump, ivec2(0))) || any(greaterThanEqual(jump, input_image_size))) {
            continue;
        }     
        vec4 seed = imageLoad(input_image, jump);
        vec2 seedpos = seed.xy;
        if (seedpos == vec2(0.0)) continue;
        vec2 diff =(seedpos * input_image_size) - fragCoord;
        float dist=dot(diff,diff);
        
        if (dist < closest_dist) {
            closest_dist = dist;
            closest_data = seed;
        }
    }

    imageStore(output_image, ifragCoord, closest_data);

}

