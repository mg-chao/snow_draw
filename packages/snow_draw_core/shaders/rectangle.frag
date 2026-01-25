#version 460 core

#include <flutter/runtime_effect.glsl>

// Output color
out vec4 fragColor;

// Geometry uniforms
uniform vec2 uResolution;       // Rectangle size in pixels (width, height)
uniform vec2 uCenter;           // Rectangle center in screen coordinates
uniform float uRotation;        // Rotation angle in radians
uniform float uCornerRadius;    // Corner radius in pixels

// Fill uniforms
uniform float uFillStyle;       // 0=solid, 1=line, 2=crossLine
uniform vec4 uFillColor;        // Fill color (premultiplied alpha)
uniform float uFillLineWidth;   // Line width for pattern fills
uniform float uFillLineSpacing; // Spacing between pattern lines

// Stroke uniforms
uniform float uStrokeStyle;     // 0=solid, 1=dashed, 2=dotted
uniform vec4 uStrokeColor;      // Stroke color (premultiplied alpha)
uniform float uStrokeWidth;     // Stroke width in pixels
uniform float uDashLength;      // Dash length for dashed stroke
uniform float uGapLength;       // Gap length for dashed stroke
uniform float uDotSpacing;      // Dot spacing for dotted stroke
uniform float uDotRadius;       // Dot radius for dotted stroke

// Anti-aliasing
uniform float uAAWidth;         // Anti-aliasing width (typically 1.0-1.5 pixels)

// Constants
const float PI = 3.14159265359;
const float SQRT2 = 1.41421356237;
const float HALF_PI = 1.57079632679;

// Rotate point around origin
vec2 rotate2D(vec2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Rounded rectangle SDF (signed distance field)
// Returns negative inside, positive outside, zero on edge
float sdRoundedRect(vec2 p, vec2 halfSize, float radius) {
    // Clamp radius to valid range
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Diagonal line pattern (-45 degrees)
// Returns 0.0 on line, 1.0 in gap
float linePattern(vec2 p, float lineWidth, float spacing) {
    // Project onto diagonal direction (perpendicular to line direction)
    float d = (p.x + p.y) / SQRT2;
    float pattern = mod(d + spacing * 0.5, spacing);
    float distToLine = abs(pattern - spacing * 0.5);
    return smoothstep(lineWidth * 0.5 - 0.5, lineWidth * 0.5 + 0.5, distToLine);
}

// Cross-hatch pattern (both +45 and -45 degrees)
// Returns 0.0 on line, 1.0 in gap
float crossLinePattern(vec2 p, float lineWidth, float spacing) {
    float line1 = linePattern(p, lineWidth, spacing);
    float line2 = linePattern(vec2(-p.x, p.y), lineWidth, spacing);
    return min(line1, line2); // Union of both patterns (min = more coverage)
}

// Calculate approximate arc length along rounded rectangle perimeter
// This is used for dashed/dotted stroke patterns
float calcArcLength(vec2 p, vec2 halfSize, float radius) {
    // Clamp radius
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 cornerCenter = halfSize - r;

    // Work in first quadrant (absolute coordinates)
    vec2 q = abs(p);

    // Total perimeter calculation for reference:
    // 4 corners (quarter circles): 4 * (PI/2 * r) = 2 * PI * r
    // 4 edges: 2 * (2 * cornerCenter.x) + 2 * (2 * cornerCenter.y)
    //        = 4 * (cornerCenter.x + cornerCenter.y)

    float straightX = cornerCenter.x * 2.0; // Half of horizontal edges
    float straightY = cornerCenter.y * 2.0; // Half of vertical edges
    float cornerArc = HALF_PI * r;          // Quarter circle arc

    // Determine which segment we're on and calculate arc length
    // Starting from right edge center, going counter-clockwise

    if (q.x > cornerCenter.x && q.y > cornerCenter.y) {
        // In corner region
        vec2 toCorner = q - cornerCenter;
        float angle = atan(toCorner.y, toCorner.x);
        return straightY * 0.5 + angle * r;
    } else if (q.x >= cornerCenter.x) {
        // Right edge
        return q.y;
    } else if (q.y >= cornerCenter.y) {
        // Top edge
        return straightY * 0.5 + cornerArc + (cornerCenter.x - q.x);
    } else {
        // Determine by angle from center
        if (q.y * cornerCenter.x > q.x * cornerCenter.y) {
            // Closer to top
            return straightY * 0.5 + cornerArc + (cornerCenter.x - q.x);
        } else {
            // Closer to right
            return q.y;
        }
    }
}

// Dashed stroke pattern
// Returns 1.0 for dash, 0.0 for gap
float dashedPattern(float arcLength, float dashLen, float gapLen) {
    float period = dashLen + gapLen;
    float t = mod(arcLength, period);
    // Smooth transitions at dash edges
    float dashStart = smoothstep(0.0, 1.0, t);
    float dashEnd = smoothstep(dashLen - 1.0, dashLen + 1.0, t);
    return dashStart * (1.0 - dashEnd);
}

// Dotted stroke pattern
// Returns 1.0 for dot, 0.0 for gap
float dottedPattern(float arcLength, float dotSpacing, float dotRadius) {
    float t = mod(arcLength, dotSpacing);
    float distToCenter = abs(t - dotSpacing * 0.5);
    return 1.0 - smoothstep(dotRadius - 1.0, dotRadius + 1.0, distToCenter);
}

void main() {
    // Get fragment position in screen coordinates
    vec2 fragCoord = FlutterFragCoord().xy;

    // Transform to rectangle-local coordinates (centered, rotated)
    vec2 localPos = fragCoord - uCenter;
    localPos = rotate2D(localPos, -uRotation);

    vec2 halfSize = uResolution * 0.5;

    // Clamp corner radius to valid range
    float cornerRadius = min(uCornerRadius, min(halfSize.x, halfSize.y));

    // Calculate signed distance to rectangle edge
    float dist = sdRoundedRect(localPos, halfSize, cornerRadius);

    // Early discard: skip pixels clearly outside the rectangle + stroke + AA
    float maxDist = uStrokeWidth * 0.5 + uAAWidth;
    if (dist > maxDist) {
        fragColor = vec4(0.0);
        return;
    }

    // Initialize output color
    vec4 color = vec4(0.0);

    // === FILL ===
    if (uFillColor.a > 0.001) {
        // Anti-aliased fill mask (1.0 inside, 0.0 outside)
        float fillMask = 1.0 - smoothstep(-uAAWidth, uAAWidth, dist);

        if (fillMask > 0.001) {
            float patternMask = 1.0;

            int fillStyle = int(uFillStyle + 0.5);
            if (fillStyle == 1) {
                // Line pattern (-45 degrees)
                patternMask = 1.0 - linePattern(localPos, uFillLineWidth, uFillLineSpacing);
            } else if (fillStyle == 2) {
                // Cross-line pattern
                patternMask = 1.0 - crossLinePattern(localPos, uFillLineWidth, uFillLineSpacing);
            }
            // else: solid fill (patternMask = 1.0)

            color = uFillColor * fillMask * patternMask;
        }
    }

    // === STROKE ===
    if (uStrokeColor.a > 0.001 && uStrokeWidth > 0.001) {
        float halfStroke = uStrokeWidth * 0.5;

        // Stroke band: centered on the edge
        // Inner edge at dist = -halfStroke, outer edge at dist = +halfStroke
        float strokeInner = dist + halfStroke;
        float strokeOuter = dist - halfStroke;

        // Anti-aliased stroke mask
        // Center the AA transition on the stroke edges to match CPU rendering width
        float halfAA = uAAWidth * 0.5;
        float outerMask = smoothstep(halfAA, -halfAA, strokeOuter);
        float innerMask = smoothstep(-halfAA, halfAA, strokeInner);
        float strokeMask = outerMask * innerMask;

        if (strokeMask > 0.001) {
            int strokeStyle = int(uStrokeStyle + 0.5);

            if (strokeStyle == 1) {
                // Dashed stroke
                float arcLen = calcArcLength(localPos, halfSize, cornerRadius);
                float dashMask = dashedPattern(arcLen, uDashLength, uGapLength);
                strokeMask *= dashMask;
            } else if (strokeStyle == 2) {
                // Dotted stroke
                float arcLen = calcArcLength(localPos, halfSize, cornerRadius);
                float dotMask = dottedPattern(arcLen, uDotSpacing, uDotRadius);
                strokeMask *= dotMask;
            }
            // else: solid stroke (strokeMask unchanged)

            // Blend stroke over fill (stroke on top)
            // Using premultiplied alpha blending: result = src + dst * (1 - src.a)
            vec4 strokeResult = uStrokeColor * strokeMask;
            color = strokeResult + color * (1.0 - strokeResult.a);
        }
    }

    fragColor = color;
}
