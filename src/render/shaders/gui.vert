#version 450

layout(location = 0) in vec2 inPosition; // Screen space (pixels)
layout(location = 1) in vec2 inUV;
layout(location = 2) in vec4 inColor;

layout(push_constant) uniform PushConstants {
    vec2 screenSize;
} pc;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec4 fragColor;

void main() {
    // Map screen pixel coords (0..width, 0..height) to Vulkan NDC (-1..1, -1..1)
    vec2 ndc = (inPosition / pc.screenSize) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
    fragUV = inUV;
    fragColor = inColor;
}
