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

layout(std140, set = 0, binding = 0) uniform IrisUniforms {
    mat4 gbufferModelView;
    mat4 gbufferModelViewInverse;
    mat4 gbufferProjection;
    mat4 gbufferProjectionInverse;
    vec4 cameraPosition;
    vec4 upPosition;
    vec4 sunPosition;
    vec4 moonPosition;
    vec4 skyColor;
    vec4 fogColor;
    float frameTimeCounter;
    float rainStrength;
    float viewWidth;
    float viewHeight;
    float near;
    float far;
    int worldTime;
    int isEyeInWater;
    int flags;
    int pad;
    int tileMap[768];
} iris;

layout(location = 0) out vec2 fragUV;
layout(location = 1) out vec3 fragTint;
layout(location = 2) out float fragShade;
layout(location = 3) out float fragAO;
layout(location = 4) out vec2 fragLight;
layout(location = 5) out vec3 fragWorldPos;
layout(location = 6) out vec3 fragNormal;
layout(location = 7) flat out int fragTile;

void main() {
    vec3 worldPos = inPosition;

    // Foliage waving if leaves or grass cross (inFace == 6 or layer == 19)
    if (inFace == 6u || inLayer == 19u) {
        float wave = sin(iris.frameTimeCounter * 2.5 + worldPos.x * 1.5 + worldPos.z * 1.5) * 0.05;
        worldPos.x += wave;
    }

    vec4 viewPos = iris.gbufferModelView * vec4(worldPos, 1.0);
    gl_Position = iris.gbufferProjection * viewPos;

    fragUV = inUV;
    fragTint = inTint;
    fragShade = inShade;
    fragAO = inAO;
    fragLight = inLight;
    fragWorldPos = worldPos;
    fragNormal = inNormal;

    uint face = (inFace < 6u) ? inFace : 0u;
    uint idx = inLayer * 6u + face;
    if (idx < 768u) {
        fragTile = iris.tileMap[idx];
    } else {
        fragTile = 0;
    }
}
