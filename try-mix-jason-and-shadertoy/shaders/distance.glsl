#[compute]
#version 450

layout(local_size_x=16,local_size_y=16)in;

layout(set=0,binding=0,std430)buffer ConstBuffer{
    uint add_data;
}consts;

layout(set=0,binding=1,rgba32f)writeonly uniform image2D output_image;
layout(set=0,binding=2,rgba32f)readonly uniform image2D input_image;


layout(push_constant,std430)uniform Params{
    float distance_scale_hack;
}pc;

void main(){
    vec2 fragCoord=gl_GlobalInvocationID.xy;
    ivec2 ifragCoord=ivec2(fragCoord.xy);
    ivec2 input_image_size=imageSize(input_image).xy;
    vec2 vUv=fragCoord.xy/input_image_size;


    // float alpha = texture(surfaceTexture, vUv).a;
    float alpha = imageLoad(input_image, ifragCoord).a;

    // vec2 nearestSeed = imageLoad(input_image, ifragCoord).xy;
    // float distance = clamp(distance(vUv, nearestSeed), 0.0, 1.0);

    vec2 nearestSeed = imageLoad(input_image, ifragCoord).xy;
    nearestSeed *= vec2(input_image_size);
    float distance = length(nearestSeed - fragCoord);
    distance *= pc.distance_scale_hack; // HACK: scale down the distance
    distance = clamp(distance, 0.0, length(input_image_size));

    // Normalize and visualize the distance
    vec4 fragColor = vec4(vec3(distance), 1.0);
    imageStore(output_image,ifragCoord,fragColor);

}