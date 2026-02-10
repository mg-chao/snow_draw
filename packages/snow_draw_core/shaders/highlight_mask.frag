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

// Highlight data split into three vec4 arrays so every array access
// uses the loop index directly — a constant-index-expression that
// SkSL (Impeller) accepts.  The previous layout packed 9 floats per
// highlight into a single float[288] and indexed with `i * 9 + n`,
// which SkSL rejected as a non-constant index.
//
// Per-highlight layout:
//   uHiA[i] = (centerX, centerY, halfWidth, halfHeight)
//   uHiB[i] = (cosRot,  sinRot,  inflateX,  inflateY)
//   uHiC[i] = (shape,   0,       0,         0)
uniform vec4 uHiA[32];
uniform vec4 uHiB[32];
uniform vec4 uHiC[32];

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

        vec4 a = uHiA[i];
        vec4 b = uHiB[i];
        float shape = uHiC[i].x;

        vec2 center   = a.xy;
        vec2 halfSize = a.zw;
        float cosR    = b.x;
        float sinR    = b.y;
        vec2 inflate  = b.zw;

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
