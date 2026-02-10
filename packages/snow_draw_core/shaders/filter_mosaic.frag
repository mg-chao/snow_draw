#include <flutter/runtime_effect.glsl>

uniform vec2 uTextureSize;
uniform float uBlockSize;
uniform vec2 uRegionOffset;
uniform sampler2D uTextureInput;

out vec4 fragColor;

vec2 pixelate(vec2 coord, float size) {
    return floor(coord / size) * size;
}

void main() {
    vec2 coord = FlutterFragCoord().xy;

#ifdef IMPELLER_TARGET_OPENGLES
    coord.y = uTextureSize.y - coord.y;
#endif

    float blockSize = max(1.0, uBlockSize);
    vec2 worldCoord = coord + uRegionOffset;
    vec2 pixelCoord = pixelate(worldCoord, blockSize);
    vec2 localCoord = pixelCoord - uRegionOffset;
    vec2 sampleCoord = clamp(
        localCoord + vec2(blockSize * 0.5),
        vec2(0.5),
        uTextureSize - vec2(0.5)
    );
    vec2 sampleUv = sampleCoord / uTextureSize;
    fragColor = texture(uTextureInput, sampleUv);
}
