#include <flutter/runtime_effect.glsl>

uniform vec2 uTextureSize;
uniform float uBlockSize;
uniform sampler2D uTextureInput;

out vec4 fragColor;

void main() {
    vec2 coord = FlutterFragCoord().xy;

#ifdef IMPELLER_TARGET_OPENGLES
    coord.y = uTextureSize.y - coord.y;
#endif

    float blockSize = max(1.0, uBlockSize);
    vec2 blockCenter =
        floor(coord / blockSize) * blockSize + vec2(blockSize * 0.5);
    vec2 sampleCoord = clamp(blockCenter, vec2(0.5), uTextureSize - vec2(0.5));
    vec2 sampleUv = sampleCoord / uTextureSize;
    fragColor = texture(uTextureInput, sampleUv);
}
