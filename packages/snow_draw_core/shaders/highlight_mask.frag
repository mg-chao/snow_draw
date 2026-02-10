#version 460 core

#include <flutter/runtime_effect.glsl>

// Output color
out vec4 fragColor;

// Uniforms
uniform vec2 uResolution;      // Viewport size in pixels
uniform vec4 uMaskColor;       // Mask color (premultiplied alpha)
uniform float uHighlightCount; // Number of active highlights (max 32)

// Combined screen-space AABB of all highlights (minX, minY, maxX, maxY).
// Fragments outside this box skip the per-highlight loop entirely.
uniform vec4 uBounds;

// Each highlight: centerX, centerY, halfWidth, halfHeight, cosRot, sinRot,
//                 inflateX, inflateY, shape (0=rect, 1=ellipse)
// Packed as 9 floats per highlight, 32 highlights max = 288 floats.
uniform float uHighlights[288];

/// Axis-aligned rectangle test after rotating the sample point into
/// the highlight's local frame.  Receives precomputed cos/sin to
/// avoid per-fragment trigonometry.
float insideRect(vec2 p, vec2 center, vec2 half_size, float cosR,
                 float sinR, vec2 inflate) {
    vec2 d = p - center;
    vec2 local = vec2(d.x * cosR - d.y * sinR, d.x * sinR + d.y * cosR);
    vec2 expanded = half_size + inflate;
    vec2 q = abs(local) - expanded;
    // 1.0 if inside, 0.0 if outside, with 0.5px AA at the edge.
    return 1.0 - smoothstep(-0.5, 0.5, max(q.x, q.y));
}

/// Ellipse test in the highlight's local frame.  Receives precomputed
/// cos/sin to avoid per-fragment trigonometry.
float insideEllipse(vec2 p, vec2 center, vec2 half_size, float cosR,
                    float sinR, vec2 inflate) {
    vec2 d = p - center;
    vec2 local = vec2(d.x * cosR - d.y * sinR, d.x * sinR + d.y * cosR);
    vec2 expanded = half_size + inflate;
    // Normalise to unit circle space.
    vec2 n = local / expanded;
    float dist = length(n) - 1.0;
    // Approximate pixel-space distance for AA.
    float pixelDist = dist * min(expanded.x, expanded.y);
    return 1.0 - smoothstep(-0.5, 0.5, pixelDist);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    int count = int(uHighlightCount + 0.5);
    if (count <= 0) {
        fragColor = uMaskColor;
        return;
    }

    // Early-out: if this fragment is outside the combined AABB of all
    // highlights (with a small margin for AA), it is definitely in the
    // masked region — no need to test individual highlights.
    if (fragCoord.x < uBounds.x || fragCoord.x > uBounds.z ||
        fragCoord.y < uBounds.y || fragCoord.y > uBounds.w) {
        fragColor = uMaskColor;
        return;
    }

    // Accumulate "clear" coverage from all highlights.
    // Each highlight punches a hole; overlapping holes stay clear.
    float cleared = 0.0;
    for (int i = 0; i < 32; i++) {
        if (i >= count) break;
        int base = i * 9;
        vec2 center   = vec2(uHighlights[base],     uHighlights[base + 1]);
        vec2 halfSize = vec2(uHighlights[base + 2],  uHighlights[base + 3]);
        float cosR    = uHighlights[base + 4];
        float sinR    = uHighlights[base + 5];
        vec2 inflate  = vec2(uHighlights[base + 6],  uHighlights[base + 7]);
        float shape   = uHighlights[base + 8];

        float inside;
        if (shape < 0.5) {
            inside = insideRect(fragCoord, center, halfSize, cosR, sinR,
                                inflate);
        } else {
            inside = insideEllipse(fragCoord, center, halfSize, cosR, sinR,
                                   inflate);
        }
        cleared = max(cleared, inside);
    }

    // Mask is fully opaque outside highlights, fully transparent inside.
    fragColor = uMaskColor * (1.0 - cleared);
}
