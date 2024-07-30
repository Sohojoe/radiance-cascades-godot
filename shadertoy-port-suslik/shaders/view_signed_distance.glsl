#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;

layout(set = 0, binding = 1, rgba32f) readonly uniform image2D emissivity_image;
layout(set = 0, binding = 3, rgba32f) writeonly uniform image2D output_image;
layout(set = 0, binding = 10, rgba32f) readonly uniform image2D cascades_image_0;
layout(set = 0, binding = 11, rgba32f) readonly uniform image2D cascades_image_1;
layout(set = 0, binding = 12, rgba32f) readonly uniform image2D cascades_image_2;
layout(set = 0, binding = 13, rgba32f) readonly uniform image2D cascades_image_3;
layout(set = 0, binding = 14, rgba32f) readonly uniform image2D cascades_image_4;
layout(set = 0, binding = 15, rgba32f) readonly uniform image2D cascades_image_5;


layout(push_constant, std430) uniform Params {
    // int cascade_index; // Current cascade level
    // int prev_cascade_index; // Previous cascade level
    int num_cascades; // Total number of cascades
    int cascade_size_x; // Size of each cascade
    int cascade_size_y; // Size of each cascade
} pc;




void main() {
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord.xy);
    vec4 fragColor = vec4(0.0);

    ivec2 viewport_size = imageSize(output_image).xy;
    float signed_distance = imageLoad(emissivity_image, ifragCoord).r;
    float max_distance = float(max(viewport_size.x, viewport_size.y));
    float pow_signed_distance = pow(abs(signed_distance), 0.31); 
    float normed_distance = pow_signed_distance / pow(max_distance, 0.3);
    normed_distance = 1-normed_distance;
    if (signed_distance >= 0.0) {
        fragColor = vec4(normed_distance, normed_distance, 0., 1.0);
    } else {
        fragColor = vec4(normed_distance, 0., 0., 1.0);
    }
    imageStore(output_image, ifragCoord, fragColor);
    return;
}