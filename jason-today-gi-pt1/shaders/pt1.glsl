#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16) in;

layout(set = 0, binding = 0, std430) buffer ConstBuffer {
    uint add_data;
} consts;

// layout(set = 0, binding = 1, rgba32f) writeonly uniform image2D output_image;
layout(set = 0, binding = 1, rgba32f) uniform image2D output_image;


layout(push_constant, std430) uniform Params {
    uint add_data;
} pc;

// Draw a line shape!
float sdfLineSquared(vec2 p, vec2 from, vec2 to) {
  vec2 toStart = p - from;
  vec2 line = to - from;
  float lineLengthSquared = dot(line, line);
  float t = clamp(dot(toStart, line) / lineLengthSquared, 0.0, 1.0);
  vec2 closestVector = toStart - line * t;
  return dot(closestVector, closestVector);
}


void main() {
    vec2 fragCoord = gl_GlobalInvocationID.xy;
    ivec2 ifragCoord = ivec2(fragCoord.xy);

    ivec2 screen_size = imageSize(output_image).xy;
    vec4 fragColor = vec4(ifragCoord.x / float(screen_size.x), ifragCoord.y / float(screen_size.y), 0.0, 1.0);

    // vec4 current = texture(inputTexture, vUv);
    vec4 current = imageLoad(output_image, ifragCoord);
    vec2 from = vec2(25, 25);
    vec2 to = vec2(75, 75);
    float radius = 5.0;
    float radiusSquared = radius * radius;
    // vec3 color = fragColor.rgb;
    vec3 color = vec3(1.0, 1.0, 0.0);

    // If we aren't actively drawing (or on mobile) no-op!
    if (true) {
        // vec2 coord = vUv * resolution;
        vec2 coord = fragCoord;
        if (sdfLineSquared(coord, from, to) <= radiusSquared) {
        current = vec4(color, 1.0);
        }
    }
    fragColor = current;


    imageStore(output_image, ifragCoord, fragColor);
}