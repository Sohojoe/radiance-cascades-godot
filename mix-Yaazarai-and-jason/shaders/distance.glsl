#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;

void main(){
    vec2 fragCoord=gl_GlobalInvocationID.xy;
    ivec2 ifragCoord=ivec2(fragCoord.xy);
    ivec2 input_image_size=imageSize(input_image).xy;
    vec2 vUv=fragCoord.xy/input_image_size;

    vec2 nearestSeed = imageLoad(input_image, ifragCoord).xy;
    // float distance = clamp(distance(fragCoord, nearestSeed*input_image_size)/ length(input_image_size), 0.0, 1.0);
    float distance = distance(fragCoord, nearestSeed*input_image_size) / length(input_image_size);
    vec4 fragColor = vec4(vec3(distance), 1.0);
    imageStore(output_image,ifragCoord,fragColor);

    // vec4 nearestSeed = imageLoad(input_image, ifragCoord);
    // float squaredDistance = nearestSeed.z;
    // float distance = sqrt(squaredDistance);
    // // float distance = clamp(distance, 0.0, 1.0); // Optional clamping if needed
    // vec4 fragColor = vec4(vec3(distance), 1.0);
    // imageStore(output_image, ifragCoord, fragColor);

}