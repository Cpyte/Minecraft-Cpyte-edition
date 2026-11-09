#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec3 fragTint;
layout(location = 2) in float fragShade;
layout(location = 3) in float fragAO;
layout(location = 4) in vec2 fragLight;
layout(location = 5) in vec3 fragWorldPos;
layout(location = 6) in vec3 fragNormal;
layout(location = 7) flat in int fragTile;

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

layout(set = 0, binding = 1) uniform sampler2D texSampler;

layout(location = 0) out vec4 outColor;

void main() {
    int tile = fragTile;
    if (tile < 0) tile = 0;
    float col = float(tile % 16);
    float row = float(tile / 16);

    vec2 tileUV = fract(fragUV);
    vec2 atlasUV = (vec2(col, row) + clamp(tileUV, 0.001, 0.999)) / 16.0;

    vec4 texColor = texture(texSampler, atlasUV);
    if (texColor.a < 0.1) {
        discard;
    }

    vec3 albedo = texColor.rgb;
    if (fragTint.r > 0.01 || fragTint.g > 0.01 || fragTint.b > 0.01) {
        albedo *= fragTint;
    }

    // Iris PBR lighting:
    // 1. Directional Sun/Moon lighting
    vec3 N = normalize(fragNormal);
    vec3 L = normalize(iris.sunPosition.xyz);
    float NdotL = max(dot(N, L), 0.0);

    // Directional face shade & smooth AO
    float ao = 0.45 + 0.183 * fragAO;
    float shade = clamp(fragShade, 0.4, 1.0);

    // Light levels
    float skyL = fragLight.x / 240.0;
    float blkL = fragLight.y / 240.0;
    float sunBrightness = clamp(L.y * 1.5, 0.0, 1.0);

    // Sunlight direct illumination with ambient occlusion
    vec3 sunLightColor = vec3(1.0, 0.95, 0.85) * (NdotL * 0.8 + 0.2) * (skyL * sunBrightness);

    // Block/torch light (warm orange-yellow)
    float blkCurve = blkL / (2.5 - 1.5 * blkL);
    vec3 blockLightColor = vec3(1.15, 0.85, 0.55) * blkCurve;

    // Ambient skylight
    vec3 ambientColor = iris.skyColor.rgb * (skyL * 0.35 + 0.06);

    vec3 totalLight = (sunLightColor + blockLightColor + ambientColor) * ao * shade;

    // Specular reflection for sunlight
    vec3 V = normalize(iris.cameraPosition.xyz - fragWorldPos);
    vec3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float specular = pow(NdotH, 32.0) * NdotL * (skyL * sunBrightness) * 0.25;

    vec3 finalRgb = albedo * totalLight + vec3(specular);

    // Distance fog (Iris atmospheric blending)
    float dist = length(fragWorldPos - iris.cameraPosition.xyz);
    float fogFactor = clamp((dist - 40.0) / 60.0, 0.0, 1.0);
    finalRgb = mix(finalRgb, iris.fogColor.rgb, fogFactor);

    outColor = vec4(finalRgb, texColor.a);
}
