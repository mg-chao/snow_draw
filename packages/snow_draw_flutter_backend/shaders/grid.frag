#version 460 core

#include <flutter/runtime_effect.glsl>

out vec4 fragColor;

uniform vec2 uResolution;      // Viewport size in pixels
uniform vec2 uCameraPosition;  // Camera offset (translation)
uniform float uScale;          // Zoom scale factor
uniform float uGridSize;       // Base grid cell size in world units
uniform float uMajorEvery;     // Number of minor cells between major lines
uniform float uLineWidth;      // Line width in screen pixels
uniform float uMajorLineWidth; // Major line width in screen pixels
uniform vec4 uMinorColor;      // Minor line color (RGBA, premultiplied alpha)
uniform vec4 uMajorColor;      // Major line color (RGBA, premultiplied alpha)

float gridLine(float coord, float gridStep, float lineWidth) {
    float distToLine = abs(mod(coord + gridStep * 0.5, gridStep) - gridStep * 0.5);
    float screenDist = distToLine * uScale;
    return 1.0 - smoothstep(0.0, lineWidth * 0.5 + 0.5, screenDist);
}

float isMajorLine(float coord, float gridStep, float majorStep) {
    float distToMajor = abs(mod(coord + majorStep * 0.5, majorStep) - majorStep * 0.5);
    return step(distToMajor, gridStep * 0.5);
}

void main() {
    vec2 fragCoord = FlutterFragCoord().xy;

    vec2 worldPos = (fragCoord - uCameraPosition) / uScale;

    float minorStep = uGridSize;
    float majorStep = uGridSize * uMajorEvery;

    float minorLineX = gridLine(worldPos.x, minorStep, uLineWidth);
    float minorLineY = gridLine(worldPos.y, minorStep, uLineWidth);
    float majorLineX = gridLine(worldPos.x, majorStep, uMajorLineWidth);
    float majorLineY = gridLine(worldPos.y, majorStep, uMajorLineWidth);

    float minorIntensity = max(minorLineX, minorLineY);
    float majorIntensity = max(majorLineX, majorLineY);

    float isMajorX = isMajorLine(worldPos.x, minorStep, majorStep);
    float isMajorY = isMajorLine(worldPos.y, minorStep, majorStep);
    float onMajorLine = max(isMajorX * majorLineX, isMajorY * majorLineY);

    vec4 minorResult = uMinorColor * minorIntensity;
    vec4 majorResult = uMajorColor * majorIntensity;

    // This ensures major lines are drawn on top of minor lines
    fragColor = mix(minorResult, majorResult, onMajorLine);
}
