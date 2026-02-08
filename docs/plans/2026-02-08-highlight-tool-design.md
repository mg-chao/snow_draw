# Highlight Tool Design

**Date:** 2026-02-08

## Goal
Add a Highlight tool with rectangle/ellipse shapes, highlight styling controls, and a global mask that dims the canvas while cutting out highlight shapes. Highlight elements always use multiply blending and the mask renders only when highlights exist.

## Architecture
- Core: introduce a new Highlight element type (data + renderer + hit tester) in `packages/snow_draw_core`.
- App: add a Highlight tool in `apps/snow_draw` and expose highlight-specific style controls in the style toolbar.
- Config: add highlight defaults (style + shape) and global mask config (color/opacity) to DrawConfig.
- Rendering: render highlight elements using `BlendMode.multiply`. Render the mask as canvas content on the topmost content layer, in static or dynamic painter depending on whether dynamic content is active.

## Components
### Core element
- `HighlightData`
  - Fields: `shape` (rectangle/circle), `color` (fill), `strokeColor`, `strokeWidth`.
  - Implements `ElementStyleConfigurableData` and `ElementStyleUpdatableData`.
  - Maps `ElementStyleConfig.color` to fill color; maps `textStrokeColor` and `textStrokeWidth` to border.
  - Supports `highlightShape` updates from `ElementStyleUpdate`.
- `HighlightRenderer`
  - Draws fill + optional stroke using `BlendMode.multiply`.
  - Rectangle uses `drawRect`; circle uses `drawOval` on the element rect (ellipse).
  - Respects element rotation.
- `HighlightHitTester`
  - Rectangle: reuse rectangle hit logic.
  - Ellipse: use ellipse equation for inside/stroke test.

### Config
- `HighlightConfig`
  - `maskColor` (default black), `maskOpacity` (default 0.0), `defaultShape`.
- `DrawConfig`
  - Add `highlightStyle` (ElementStyleConfig) with default fill color red and default stroke color red (via textStrokeColor) and stroke width 0.
  - Add `highlight` (HighlightConfig) for mask + default shape.

### Rendering (mask)
- Mask renders only if at least one highlight element exists (including creating preview) and mask opacity > 0.
- Mask is topmost content: draw full-viewport rect with mask color/opacity, then clear highlight shapes with `BlendMode.clear` inside a `saveLayer`.
- Static vs dynamic:
  - Static painter draws mask when no dynamic layer split and no creating element.
  - Dynamic painter draws mask when there is a dynamic layer split or creating element.
- This ensures consistent mask placement and avoids double-rendering.

## UI and Data Flow
- Add `ToolType.highlight` and a toolbar button.
- Style toolbar shows highlight properties when highlight tool is active or highlights are selected:
  1) Color (fill)
  2) Highlight Shape (Rectangle/Circle)
  3) Highlight Text Stroke Width (None/Small/Medium/Large)
  4) Highlight Text Stroke Color
  5) Opacity
  6) Mask Color
  7) Mask Opacity
- Color and stroke color use the same quick-pick palette as rectangles.
- Highlight Text Stroke Width maps to values 0/2/3/5, default None.
- Mask Color/Opacity update DrawConfig globally and are shared across all highlights.

## Error Handling
- Missing highlight definition falls back to unknown-element rendering (existing behavior).
- Mask rendering is skipped if opacity is zero or no highlight elements exist.

## Testing
- Core tests for highlight hit testing (ellipse vs rectangle).
- Core tests for HighlightData serialization defaults (shape, colors, stroke width).

## Notes
- Multiply blend mode is fixed for highlight elements (no other blend modes supported).
- Mask applies after highlights are rendered (topmost content layer) so holes reveal highlight shapes.
