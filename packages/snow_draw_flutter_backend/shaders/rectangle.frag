#version 460 core

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uResolution;       // Rectangle size in pixels (width, height)
uniform vec2 uCenter;           // Rectangle center in screen coordinates
uniform float uRotation;        // Rotation angle in radians
uniform float uCornerRadius;    // Corner radius in pixels

uniform float uFillStyle;       // 0=solid, 1=line, 2=crossLine
uniform vec4 uFillColor;        // Fill color (premultiplied alpha)
uniform float uFillLineWidth;   // Line width for pattern fills
uniform float uFillLineSpacing; // Spacing between pattern lines

uniform float uStrokeStyle;     // 0=solid, 1=dashed, 2=dotted
uniform vec4 uStrokeColor;      // Stroke color (premultiplied alpha)
uniform float uStrokeWidth;     // Stroke width in pixels
uniform float uDashLength;      // Dash length for dashed stroke
uniform float uGapLength;       // Gap length for dashed stroke
uniform float uDotSpacing;      // Dot spacing for dotted stroke
uniform float uDotRadius;       // Dot radius for dotted stroke

uniform float uAAWidth;         // Anti-aliasing width (typically 1.0-1.5 pixels)

const float PI = 3.14159265359;
const float SQRT2 = 1.41421356237;
const float HALF_PI = 1.57079632679;

vec2 rotate2D(vec2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return vec2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// Rounded rectangle SDF (signed distance field)
// Returns negative inside, positive outside, zero on edge
float sdRoundedRect(vec2 p, vec2 halfSize, float radius) {
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 q = abs(p) - halfSize + r;
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
}

// Diagonal line pattern (-45 degrees)
// Returns 0.0 on line, 1.0 in gap
float linePattern(vec2 p, float lineWidth, float spacing) {
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
    return min(line1, line2);
}

// Calculate approximate arc length along rounded rectangle perimeter
// This is used for dashed/dotted stroke patterns
float calcArcLength(vec2 p, vec2 halfSize, float radius) {
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 cornerCenter = halfSize - r;

    vec2 q = abs(p);

    // Total perimeter calculation for reference:
    // 4 corners (quarter circles): 4 * (PI/2 * r) = 2 * PI * r
    // 4 edges: 2 * (2 * cornerCenter.x) + 2 * (2 * cornerCenter.y)
    //        = 4 * (cornerCenter.x + cornerCenter.y)

    float straightX = cornerCenter.x * 2.0; // Half of horizontal edges
    float straightY = cornerCenter.y * 2.0; // Half of vertical edges
    float cornerArc = HALF_PI * r;          // Quarter circle arc

    if (q.x > cornerCenter.x && q.y > cornerCenter.y) {
        vec2 toCorner = q - cornerCenter;
        float angle = atan(toCorner.y, toCorner.x);
        return straightY * 0.5 + angle * r;
    } else if (q.x >= cornerCenter.x) {
        return q.y;
    } else if (q.y >= cornerCenter.y) {
        return straightY * 0.5 + cornerArc + (cornerCenter.x - q.x);
    } else {
        if (q.y * cornerCenter.x > q.x * cornerCenter.y) {
            return straightY * 0.5 + cornerArc + (cornerCenter.x - q.x);
        } else {
            return q.y;
        }
    }
}

// Dashed stroke pattern with rounded caps
// Returns 1.0 for dash, 0.0 for gap
// perpDist is the perpendicular distance from the stroke centerline
float dashedPattern(float arcLength, float dashLen, float gapLen, float perpDist, float strokeWidth) {
    float period = dashLen + gapLen;
    float t = mod(arcLength, period);

    if (t > dashLen) {
        return 0.0;
    }

    float halfStroke = strokeWidth * 0.5;

    if (t < halfStroke) {
        float distToCapCenter = halfStroke - t;
        float dist2D = sqrt(distToCapCenter * distToCapCenter + perpDist * perpDist);
        return 1.0 - smoothstep(halfStroke - 0.5, halfStroke + 0.5, dist2D);
    }

    if (t > dashLen - halfStroke) {
        float distToCapCenter = t - (dashLen - halfStroke);
        float dist2D = sqrt(distToCapCenter * distToCapCenter + perpDist * perpDist);
        return 1.0 - smoothstep(halfStroke - 0.5, halfStroke + 0.5, dist2D);
    }

    return 1.0;
}

// Dotted stroke pattern with circular dots
// Returns 1.0 for dot, 0.0 for gap
// perpDist is the perpendicular distance from the stroke centerline
float dottedPattern(float arcLength, float dotSpacing, float dotRadius, float perpDist) {
    float dotIndex = floor(arcLength / dotSpacing + 0.5);
    float dotCenter = dotIndex * dotSpacing;
    float arcDist = arcLength - dotCenter;

    float dist2D = sqrt(arcDist * arcDist + perpDist * perpDist);

    return 1.0 - smoothstep(dotRadius - 0.5, dotRadius + 0.5, dist2D);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    vec2 localPos = fragCoord - uCenter;
    localPos = rotate2D(localPos, -uRotation);

    vec2 halfSize = uResolution * 0.5;

    float cornerRadius = min(uCornerRadius, min(halfSize.x, halfSize.y));

    float dist = sdRoundedRect(localPos, halfSize, cornerRadius);

    // Early discard: skip pixels clearly outside the rectangle + stroke + AA
    float maxDist = uStrokeWidth * 0.5 + uAAWidth;
    if (dist > maxDist) {
        fragColor = vec4(0.0);
        return;
    }

    vec4 color = vec4(0.0);

    if (uFillColor.a > 0.001) {
        float fillMask = 1.0 - smoothstep(-uAAWidth, uAAWidth, dist);

        if (fillMask > 0.001) {
            float patternMask = 1.0;

            int fillStyle = int(uFillStyle + 0.5);
            if (fillStyle == 1) {
                patternMask = 1.0 - linePattern(localPos, uFillLineWidth, uFillLineSpacing);
            } else if (fillStyle == 2) {
                patternMask = 1.0 - crossLinePattern(localPos, uFillLineWidth, uFillLineSpacing);
            }

            color = uFillColor * fillMask * patternMask;
        }
    }

    if (uStrokeColor.a > 0.001 && uStrokeWidth > 0.001) {
        float halfStroke = uStrokeWidth * 0.5;

        float strokeInner = dist + halfStroke;
        float strokeOuter = dist - halfStroke;

        // Center the AA transition on the stroke edges to match CPU rendering width
        float halfAA = uAAWidth * 0.5;
        float outerMask = smoothstep(halfAA, -halfAA, strokeOuter);
        float innerMask = smoothstep(-halfAA, halfAA, strokeInner);
        float strokeMask = outerMask * innerMask;

        if (strokeMask > 0.001) {
            int strokeStyle = int(uStrokeStyle + 0.5);

            if (strokeStyle == 1) {
                float arcLen = calcArcLength(localPos, halfSize, cornerRadius);
                float dashMask = dashedPattern(arcLen, uDashLength, uGapLength, abs(dist), uStrokeWidth);
                strokeMask *= dashMask;
            } else if (strokeStyle == 2) {
                float arcLen = calcArcLength(localPos, halfSize, cornerRadius);
                float dotMask = dottedPattern(arcLen, uDotSpacing, uDotRadius, dist);
                strokeMask *= dotMask;
            }

            // Using premultiplied alpha blending: result = src + dst * (1 - src.a)
            vec4 strokeResult = uStrokeColor * strokeMask;
            color = strokeResult + color * (1.0 - strokeResult.a);
        }
    }

    fragColor = color;
}
