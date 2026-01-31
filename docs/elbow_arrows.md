# Elbow Arrows: Routing + Editing Process

This document explains how elbow arrows are routed and edited in `snow_draw_core`, with
step-by-step notes that match the code flow.

## Key Concepts

- **Elbow route**: an orthogonal polyline (horizontal/vertical segments only).
- **Heading**: the cardinal direction the endpoint or segment is moving toward.
- **Binding**: an endpoint attached to an element; the route must avoid its bounds
  and respect arrowhead spacing.
- **Fixed segment**: a pinned segment whose direction is preserved during edits.

## Routing Pipeline (world space)

Entry point: `routeElbowArrow` in `elbow_router.dart`.

1) Resolve endpoints and headings
   - Bindings are resolved via `ArrowBindingUtils.resolveElbowBoundPoint`.
   - Endpoints store their final position, heading, and whether they are bound.
   - Unbound endpoints fall back to the vector between start and end points.

2) Build padded obstacles
   - Bound elements are expanded by a heading-dependent padding and arrowhead gap.
   - If start/end padded bounds overlap, they are split to avoid a dead-end grid.
   - A common bounding box is built to clamp routing search space.

3) Attempt direct route
   - If the endpoints are aligned and headings are compatible, attempt a straight
     segment that does not intersect any obstacle bounds.

4) Route via grid (A*)
   - A sparse grid is built from obstacle bounds, endpoints, and common bounds.
   - A* is run with Manhattan distance + bend penalties to minimize kinks.
   - Traversal is constrained at the start/end if those endpoints are bound.

5) Post-process path
   - Enforce orthogonality and insert missing elbows when needed.
   - Remove tiny segments and keep only corner points.
   - Clamp coordinates to avoid runaway positions.

## Editing Pipeline (local space)

Entry point: `computeElbowEdit` in `elbow_editing.dart`.

1) Resolve base points
   - Normalize the stored points into local space for the current element.

2) Sanitize fixed segments
   - Fixed segments are validated against the current path and reindexed.

3) No fixed segments
   - A fresh route is produced with `routeElbowArrowForElement`.

4) Fixed segment release
   - When a segment is unpinned, the remaining fixed segments are preserved and
     the path is re-routed only where needed.

5) Endpoint drag with fixed segments
   - If the user drags an endpoint but fixed segments are unchanged, only the
     affected part of the route is recomputed.

6) Apply fixed segments
   - The path is updated to honor fixed segment directions and keep them orthogonal.

7) Simplify + reindex
   - Redundant points are removed while preserving pinned points.
   - Fixed segments are reindexed to match the simplified path.

## Shared Geometry Helpers

`elbow_geometry.dart` provides shared geometry routines, such as determining which
side of a bound rect a point belongs to. This keeps routing and editing logic in sync.

## Tests

Coverage focuses on routing orthogonality, obstacle avoidance, bindings, and editing
with fixed segments.

- `elbow_router_anchor_test.dart`: validates bound approaches for each side.
- `elbow_router_behavior_test.dart`: validates fallback routing, direct routes, and
  obstacle avoidance.
- `elbow_binding_gap_test.dart`: validates arrowhead-dependent binding offsets.
- `elbow_fixed_segments_test.dart`: validates fixed-segment editing flows.

Run core tests:

```
cd e:\snow_draw
flutter test packages/snow_draw_core/test
```
