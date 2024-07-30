#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;

layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D output_image;


layout(push_constant, std430) uniform Params {
    uint add_data;
} pc;


void main() {
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord.xy);

    ivec2 screen_size = imageSize(output_image).xy;
    vec4 fragColor = vec4(ifragCoord.x / float(screen_size.x), ifragCoord.y / float(screen_size.y), 0.0, 1.0);
    imageStore(output_image, ifragCoord, fragColor);
}