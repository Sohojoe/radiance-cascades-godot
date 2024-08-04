#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16) in;
layout(set = 0, binding = 2, rgba32f) readonly uniform image2D input_image;
layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D output_image;

void main() {
    // Get the global position of the current thread
    ivec2 output_pos = ivec2(gl_GlobalInvocationID.xy);
    
    // Check if we're within the output image bounds
    if (output_pos.x >= imageSize(output_image).x || output_pos.y >= imageSize(output_image).y) {
        return;
    }
    
    // Calculate the scale factor
    vec2 scale = vec2(imageSize(input_image)) / vec2(imageSize(output_image));
    
    // Calculate the corresponding position in the input image
    vec2 input_pos_float = (vec2(output_pos) + 0.5) * scale - 0.5;
    ivec2 input_pos = ivec2(floor(input_pos_float));
    
    // Calculate the fractional part for interpolation
    vec2 frac = fract(input_pos_float);
    
    // Fetch the 4 neighboring pixels
    vec4 color00 = imageLoad(input_image, clamp(input_pos, ivec2(0), imageSize(input_image) - 1));
    vec4 color10 = imageLoad(input_image, clamp(input_pos + ivec2(1, 0), ivec2(0), imageSize(input_image) - 1));
    vec4 color01 = imageLoad(input_image, clamp(input_pos + ivec2(0, 1), ivec2(0), imageSize(input_image) - 1));
    vec4 color11 = imageLoad(input_image, clamp(input_pos + ivec2(1, 1), ivec2(0), imageSize(input_image) - 1));
    
    // Bilinear interpolation
    vec4 color = mix(
        mix(color00, color10, frac.x),
        mix(color01, color11, frac.x),
        frac.y
    );
    
    // Write the interpolated color to the output image
    imageStore(output_image, output_pos, color);
}