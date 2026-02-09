#version 460 core

#include <flutter/runtime_effect.glsl>

uniform vec2 uTextureSize;
uniform float uBlockCount;
uniform sampler2D uTextureInput;

out vec4 fragColor;

void main() {
    vec2 uv = FlutterFragCoord().xy / uTextureSize;

#ifdef IMPELLER_TARGET_OPENGLES
    uv.y = 1.0 - uv.y;
#endif

    float blocks = max(1.0, uBlockCount);
    vec2 pixelatedUv = (floor(uv * blocks) + 0.5) / blocks;
    fragColor = texture(uTextureInput, pixelatedUv);
}
