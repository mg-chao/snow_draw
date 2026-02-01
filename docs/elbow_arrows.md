# Elbow Arrows: Routing + Editing Process

This document explains how elbow arrows are routed and edited in `snow_draw_core`.
It mirrors the step-based pipelines in code so each step maps to a specific block
of logic and is easy to verify in tests.

## Key Concepts

- **Elbow route**: an orthogonal polyline (horizontal/vertical segments only).
- **Heading**: the cardinal direction an endpoint or segment moves toward.
- **Binding**: an endpoint attached to an element; routing must avoid its bounds
  and respect arrowhead spacing.
- **Dongle point**: the point where the route exits a bound obstacle, aligned to
  the binding heading.
- **Fixed segment**: a pinned segment whose direction (axis) is preserved during
  edits.

## Inputs and Outputs

Routing entry points:

- `routeElbowArrow`: accepts world-space start/end points and optional bindings,
  returns an orthogonal path in world space plus resolved endpoints.
- `routeElbowArrowForElement`: accepts element-local points, converts to world
  space, routes via `routeElbowArrow`, then returns both local + world points.

Editing entry point:

- `computeElbowEdit`: accepts the current arrow element + edits, returns updated
  local points and fixed segment updates.

## Code Layout (post-refactor)

Routing files:

- `elbow_router.dart`: public API + routing pipeline orchestration.
- `elbow_router_endpoints.dart`: binding resolution + endpoint headings.
- `elbow_router_obstacles.dart`: obstacle padding, overlap splitting, dongles.
- `elbow_router_path.dart`: direct route checks + fallback + post-processing.
- `elbow_router_grid.dart`: sparse grid + A* routing with bend penalties.

Editing files:

- `elbow_editing.dart`: public API + edit pipeline orchestration.
- `elbow_edit_geometry.dart`: orthogonal geometry + simplification helpers.
- `elbow_edit_fixed_segments.dart`: fixed segment mapping + reindexing.
- `elbow_edit_routing.dart`: release routing + local route helpers.
- `elbow_edit_endpoint_drag.dart`: endpoint-drag flow with fixed segments.
- `elbow_edit_perpendicular.dart`: perpendicular bound approach enforcement.

## Implementation Map (refactor guide)

Routing components:

- `_ElbowRoutePipeline`: orchestrates the routing steps.
- `_resolveRouteEndpoints`: resolves bindings, endpoints, and headings.
- `_ObstacleLayoutBuilder`: builds padded obstacle bounds + dongle points.
- `_ElbowRouteEngine`: selects direct vs. grid routing and finalizes the path.
- `_buildGrid` + `_astar`: sparse-grid routing with bend penalties.
- `_ensureOrthogonalPath` + `_removeShortSegments` + `_getCornerPoints`: cleanup.

Editing components:

- `_ElbowEditPipeline`: orchestrates the edit steps.
- `_applyEndpointDragWithFixedSegments`: endpoint-drag flow with fixed segments.
- `_ensurePerpendicularBindings`: enforces perpendicular bound approaches.
- `_applyFixedSegmentsToPoints` / `_reindexFixedSegments` / `_syncFixedSegmentsToPoints`:
  fixed segment enforcement and stability.

## Routing Pipeline (world space)

Entry: `routeElbowArrow` -> `_ElbowRoutePipeline` -> `_ElbowRouteEngine`.

### Step 1: Resolve endpoints (bindings + headings)

- If a binding exists and the target element is present, the endpoint is snapped
  to the elbow binding point via `ArrowBindingUtils.resolveElbowBoundPoint`.
- The anchor on the element boundary is resolved via
  `ArrowBindingUtils.resolveElbowAnchorPoint`.
- The endpoint heading is derived from the anchor position on the element bounds.
- If the endpoint is unbound, the heading falls back to the vector between the
  start and end points.

### Step 2: Build obstacle layout

- Bound element bounds are inflated using heading-aware padding:
  - **Head side**: extra space for arrowhead gap.
  - **Other sides**: standard obstacle padding.
- If the start and end obstacle bounds overlap, they are split so the grid is not
  blocked by a single merged obstacle (avoids a dead-end grid search).
- A shared routing bounds box is built by unioning the obstacles and inflating by
  a base padding. This clamps the search space for the grid route.
- Dongle points are placed on the obstacle boundary in the heading direction.

### Step 3: Try a direct orthogonal segment

- A direct segment is possible only when the endpoints are aligned on X or Y.
- The segment must respect the endpoint heading constraints (if bound).
- The segment must not intersect any obstacle bounds.

### Step 4: Route via grid (A*)

- A sparse grid is built from obstacle edges, endpoint coordinates, and the
  shared routing bounds.
- Axis nodes are added to ensure the first/last move can match bound headings.
- A* uses Manhattan distance plus bend penalties to reduce unnecessary elbows.
- Neighbor traversal rejects:
  - Segments intersecting obstacles.
  - Immediate reversals.
  - Disallowed headings when endpoints are constrained.
- If A* fails to find a path, a midpoint elbow fallback is used.

### Step 5: Post-process path

- Insert midpoints to guarantee orthogonality if a diagonal appears.
- Remove tiny segments and keep only corner points.
- Clamp coordinates to avoid runaway values.

## Editing Pipeline (local space)

Entry: `computeElbowEdit` -> `_ElbowEditPipeline`.

### Step 1: Resolve base + incoming points

- Current element points are resolved into local space.
- Incoming overrides are applied if present.

### Step 2: Sanitize fixed segments

- Invalid indices are removed.
- Non-orthogonal or tiny segments are dropped.
- Duplicates are removed and indices are sorted.

### Step 3: No fixed segments

- A full re-route is performed via `routeElbowArrowForElement`.

### Step 4: Fixed segment release

- When a segment is unpinned, only the portion between the surrounding fixed
  segments is re-routed; the rest of the path is preserved.

### Step 5: Endpoint drag with fixed segments

- If endpoints move but fixed segments are unchanged, only the affected portion
  is re-routed and then re-aligned to fixed segments.
- Sub-steps inside `_applyEndpointDragWithFixedSegments`:
  - Apply endpoint overrides to a stable reference path.
  - Optionally adopt a bound-aware baseline route.
  - Reapply fixed segments and correct diagonal drift.
  - Snap unbound endpoint neighbors to preserve orthogonality.
  - Merge collinear tail segments when fully unbound.
  - Enforce perpendicular approach for bound endpoints.

### Step 6: Apply fixed segments

- Fixed segments force their axis (horizontal/vertical) on the path.
- Endpoint bindings are adjusted to stay perpendicular to bound elements.

### Step 7: Simplify + reindex

- Collinear points are removed while pinned points are preserved.
- Fixed segments are reindexed to match the simplified path.

## Edge Cases and Safeguards

- Overlapping bound elements are split into separate obstacles for routing.
- Very short arrows still generate a stable midpoint elbow.
- Diagonal drift is corrected to maintain orthogonality.
- Bound endpoints enforce perpendicular approach even during edits.
- Arrowhead gaps are reflected in obstacle padding and binding offsets.
- Aligned endpoints with incompatible headings still route with an elbow.

## Tests

Routing coverage:

- `elbow_router_anchor_test.dart`: bound approach from each side.
- `elbow_router_behavior_test.dart`: fallback routing, short arrows, heading
  mismatch, overlapping obstacles, and obstacle avoidance.
- `elbow_router_grid_test.dart`: grid routing around obstacles and heading
  constraints.
- `elbow_router_element_route_test.dart`: local/world routing consistency.

Editing coverage:

- `elbow_fixed_segments_test.dart`: fixed-segment editing flows.
- `elbow_edit_pipeline_test.dart`: release and endpoint-drag scenarios with
  fixed segments, binding perpendicular adjustments, and new axis/drag cases.
- `elbow_transform_fixed_segments_test.dart`: verifies fixed segments transform
  with element changes. (new)

Binding coverage:

- `elbow_binding_gap_test.dart`: arrowhead-dependent binding offsets.

## Running Tests

```
cd e:\snow_draw
flutter test packages/snow_draw_core/test
```
