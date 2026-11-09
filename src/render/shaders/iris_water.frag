#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec3 fragTint;
layout(location = 2) in vec2 fragLight;
layout(location = 3) in vec3 fragWorldPos;
layout(location = 4) in vec3 fragNormal;
layout(location = 5) flat in int fragTile;

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
    if (tile < 0) tile = 14;
    float col = float(tile % 16);
    float row = float(tile / 16);

    // Animated water texture coordinates
    vec2 flowUV = fract(fragUV + vec2(iris.frameTimeCounter * 0.05, iris.frameTimeCounter * 0.02));
    vec2 atlasUV = (vec2(col, row) + clamp(flowUV, 0.001, 0.999)) / 16.0;

    vec4 texColor = texture(texSampler, atlasUV);
    vec3 baseColor = texColor.rgb;
    if (fragTint.r > 0.01) {
        baseColor *= fragTint;
    } else {
        baseColor *= vec3(0.24, 0.46, 0.89); // Deep crystal water tint
    }

    vec3 N = normalize(fragNormal);
    vec3 V = normalize(iris.cameraPosition.xyz - fragWorldPos);
    vec3 L = normalize(iris.sunPosition.xyz);

    // Fresnel reflectance
    float NdotV = max(dot(N, V), 0.0);
    float fresnel = 0.02 + 0.98 * pow(1.0 - NdotV, 5.0);

    // Specular highlight from Sun
    vec3 H = normalize(L + V);
    float NdotH = max(dot(N, H), 0.0);
    float specular = pow(NdotH, 64.0) * max(dot(N, L), 0.0) * 1.5;

    // Sky reflection
    vec3 reflectRgb = mix(iris.skyColor.rgb, vec3(1.0), fresnel * 0.5);

    vec3 waterColor = mix(baseColor, reflectRgb, clamp(fresnel, 0.2, 0.85));
    waterColor += vec3(specular);

    // Water transparency (0.65 alpha for clean underwater view)
    outColor = vec4(waterColor, 0.68);
}
