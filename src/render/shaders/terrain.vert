#version 450

layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec2 inUV;
layout(location = 2) in uint inLayer;
layout(location = 3) in vec3 inNormal;
layout(location = 4) in float inAO;
layout(location = 5) in vec2 inLight;
layout(location = 6) in vec3 inTint;
layout(location = 7) in float inShade;
layout(location = 8) in uint inFace;

layout(set = 0, binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 proj;
    vec4 cameraPos;
    vec4 skyColor;
    vec4 fogColor;
    float skyBrightness;
    float time;
    int tileMap[768]; // (layer * 6 + face) -> tile_index
} ubo;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec3 fragTint;
layout(location = 2) out float fragShade;
layout(location = 3) out float fragAO;
layout(location = 4) out vec2 fragLight;
layout(location = 5) out float fragDist;
layout(location = 6) flat out int fragTile;

void main() {
    vec4 worldPos = ubo.model * vec4(inPosition, 1.0);
    gl_Position = ubo.proj * ubo.view * worldPos;

    fragUV = inUV;
    fragTint = inTint;
    fragShade = inShade;
    fragAO = inAO;
    fragLight = inLight;
    fragDist = length(worldPos.xyz - ubo.cameraPos.xyz);

    uint face = (inFace < 6u) ? inFace : 0u;
    uint idx = inLayer * 6u + face;
    if (idx < 768u) {
        fragTile = ubo.tileMap[idx];
    } else {
        fragTile = 0;
    }
}
