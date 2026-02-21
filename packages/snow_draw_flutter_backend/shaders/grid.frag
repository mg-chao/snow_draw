#version 460 core

#include <flutter/runtime_effect.glsl>

// Output color
out vec4 fragColor;

// Uniforms
uniform vec2 uResolution;      // Viewport size in pixels
uniform vec2 uCameraPosition;  // Camera offset (translation)
uniform float uScale;          // Zoom scale factor
uniform float uGridSize;       // Base grid cell size in world units
uniform float uMajorEvery;     // Number of minor cells between major lines
uniform float uLineWidth;      // Line width in screen pixels
uniform float uMajorLineWidth; // Major line width in screen pixels
uniform vec4 uMinorColor;      // Minor line color (RGBA, premultiplied alpha)
uniform vec4 uMajorColor;      // Major line color (RGBA, premultiplied alpha)

// Calculate the distance from a point to the nearest grid line
float gridLine(float coord, float gridStep, float lineWidth) {
    // Distance to nearest grid line
    float distToLine = abs(mod(coord + gridStep * 0.5, gridStep) - gridStep * 0.5);
    // Convert to screen pixels and apply anti-aliasing
    float screenDist = distToLine * uScale;
    // Smooth step for anti-aliased edges
    return 1.0 - smoothstep(0.0, lineWidth * 0.5 + 0.5, screenDist);
}

// Check if coordinate is on a major grid line
float isMajorLine(float coord, float gridStep, float majorStep) {
    float distToMajor = abs(mod(coord + majorStep * 0.5, majorStep) - majorStep * 0.5);
    // Threshold for considering it a major line (half a minor grid step)
    return step(distToMajor, gridStep * 0.5);
}

void main() {
    // Get fragment position in screen coordinates
    vec2 fragCoord = FlutterFragCoord().xy;

    // Transform screen coordinates to world coordinates
    // Screen to world: (screen - cameraPosition) / scale
    vec2 worldPos = (fragCoord - uCameraPosition) / uScale;

    // Calculate grid steps
    float minorStep = uGridSize;
    float majorStep = uGridSize * uMajorEvery;

    // Calculate line intensities for both axes
    float minorLineX = gridLine(worldPos.x, minorStep, uLineWidth);
    float minorLineY = gridLine(worldPos.y, minorStep, uLineWidth);
    float majorLineX = gridLine(worldPos.x, majorStep, uMajorLineWidth);
    float majorLineY = gridLine(worldPos.y, majorStep, uMajorLineWidth);

    // Combine minor lines (union of X and Y)
    float minorIntensity = max(minorLineX, minorLineY);

    // Combine major lines (union of X and Y)
    float majorIntensity = max(majorLineX, majorLineY);

    // Check if we're on a major line position
    float isMajorX = isMajorLine(worldPos.x, minorStep, majorStep);
    float isMajorY = isMajorLine(worldPos.y, minorStep, majorStep);
    float onMajorLine = max(isMajorX * majorLineX, isMajorY * majorLineY);

    // Blend colors: major lines take precedence over minor lines
    vec4 minorResult = uMinorColor * minorIntensity;
    vec4 majorResult = uMajorColor * majorIntensity;

    // Use major color where we're on a major line, otherwise use minor
    // This ensures major lines are drawn on top of minor lines
    fragColor = mix(minorResult, majorResult, onMajorLine);
}
