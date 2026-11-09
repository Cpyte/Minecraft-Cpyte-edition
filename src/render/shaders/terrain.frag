#version 450

layout(location = 0) in vec2 fragUV;
layout(location = 1) in vec3 fragTint;
layout(location = 2) in float fragShade;
layout(location = 3) in float fragAO;
layout(location = 4) in vec2 fragLight;
layout(location = 5) in float fragDist;
layout(location = 6) flat in int fragTile;

layout(set = 0, binding = 0) uniform UniformBufferObject {
    mat4 model;
    mat4 view;
    mat4 proj;
    vec4 cameraPos;
    vec4 skyColor;
    vec4 fogColor;
    float skyBrightness;
    float time;
    float fogStart;
    float fogEnd;
    int tileMap[768];
} ubo;

layout(set = 0, binding = 1) uniform sampler2D texSampler;

layout(location = 0) out vec4 outColor;

void main() {
    // Atlas layout: 16x16 grid of tiles
    int tile = fragTile;
    if (tile < 0) tile = 0;
    float col = float(tile % 16);
    float row = float(tile / 16);

    // Compute repeating coordinates within the tile with sub-texel clamp to avoid bleeding
    vec2 tileUV = fract(fragUV);
    // 16 pixels per tile in a 256x256 atlas
    vec2 atlasUV = (vec2(col, row) + clamp(tileUV, 0.001, 0.999)) / 16.0;

    vec4 texColor = texture(texSampler, atlasUV);
    if (texColor.a < 0.1) {
        discard;
    }

    // Biome tinting: if fragTint has a color, multiply texture RGB by tint
    vec3 baseColor = texColor.rgb;
    if (fragTint.r > 0.01 || fragTint.g > 0.01 || fragTint.b > 0.01) {
        baseColor *= fragTint;
    }

    // Directional shading (0.5..1.0 from face direction)
    float shade = clamp(fragShade, 0.4, 1.0);

    // Ambient occlusion factor: AO 0..3 -> 0.46..1.0
    float aoFactor = 0.46 + 0.18 * fragAO;

    // Minecraft light calculation:
    // fragLight.x = sky light (0..240), fragLight.y = block light (0..240)
    float skyL = fragLight.x / 240.0;
    float blkL = fragLight.y / 240.0;
    float effectiveSky = skyL * ubo.skyBrightness;
    float lightLevel = max(effectiveSky, blkL);

    // Realistic Minecraft gamma / light curve
    float lightCurve = lightLevel / (3.0 - 2.0 * lightLevel);
    float ambient = 0.06;
    float finalLight = ambient + (1.0 - ambient) * lightCurve;

    // Slight warm tint for block torch light
    vec3 lightColor = vec3(1.0);
    if (blkL > effectiveSky + 0.05) {
        lightColor = vec3(1.05, 0.95, 0.82);
    }

    vec3 shadedColor = baseColor * shade * aoFactor * finalLight * lightColor;

    // Atmospheric distance fog (Minecraft render distance fog)
    // The renderer sets the range from the server's view distance, so the haze
    // arrives where the world stops being sent rather than at a fixed 96.
    float fogFactor = clamp((fragDist - ubo.fogStart) / (ubo.fogEnd - ubo.fogStart), 0.0, 1.0);
    vec3 finalColor = mix(shadedColor, ubo.fogColor.rgb, fogFactor);

    outColor = vec4(finalColor, texColor.a);
}
