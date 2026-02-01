# Elbow Arrow Implementation

## Overview
Elbow arrows are routed as orthogonal polylines that avoid bound element
obstacles and respect arrowhead spacing. Editing preserves orthogonality
and keeps user-pinned (fixed) segments stable while endpoints move.

This document describes the step-by-step routing and editing pipelines,
key invariants, and the test coverage that verifies expected behavior.

## File Map
Routing
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_router.dart
  Public API and routing result types.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_router_endpoints.dart
  Binding resolution, anchor/heading computation.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_router_obstacles.dart
  Obstacle padding, overlap splitting, exit point computation.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_router_grid.dart
  Sparse grid build + A* routing with bend penalties.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_router_path.dart
  Direct-route checks, fallback paths, orthogonal post-processing.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_router_pipeline.dart
  Step-by-step routing orchestration.

Editing
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_editing.dart
  Public API for edit computation.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_edit_pipeline.dart
  Step-by-step edit orchestration and branching.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_edit_fixed_segments.dart
  Fixed segment sanitization, mapping, and reindexing.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_edit_endpoint_drag.dart
  Endpoint drag flow with fixed segments.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_edit_perpendicular.dart
  Perpendicular endpoint enforcement for bound elements.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_edit_routing.dart
  Routing helpers used by the edit pipeline.

Shared
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_constants.dart
  Shared tolerances and padding values.
- packages/snow_draw_core/lib/draw/elements/types/arrow/elbow/elbow_geometry.dart
  Shared geometry utilities.

## Routing Data Flow (Key Types)
- _ElbowRouteRequest: raw world-space inputs from `routeElbowArrow`.
- _ElbowRouteContext: request + resolved endpoints and a `hasAnyBinding` flag.
- _ResolvedEndpoint(s): concrete point, heading, bound element bounds, and
  arrowhead metadata for each endpoint.
- _ElbowObstacleLayoutBuilder: expands bounds, resolves overlaps, and yields
  obstacles + exit points for routing.
- _ElbowGridRouter: A* search on a sparse grid with bend penalties.
- _AxisAlignment: alignment helper for direct-route eligibility checks.

## Editing Data Flow (Key Types)
- _ElbowEditContext: resolved inputs + derived flags used to pick edit mode.
- _FixedSegmentPathResult: points + fixed segments emitted by intermediate steps.
- _EndpointDragContext / _EndpointDragState: endpoint drag inputs + working state.

## Routing Pipeline (routeElbowArrow)
1) Resolve endpoints and headings
   - Resolve bindings to concrete points (including arrowhead gaps).
   - Compute anchor headings based on bound element faces.
   - Produce a uniform endpoint model for bound and unbound cases.

2) Early fallback (unbound endpoints)
   - If both endpoints are unbound, use a deterministic fallback elbow:
     a) Direct line if aligned.
     b) Stable midpoint elbow if short or diagonal.

3) Plan obstacles and exits
   - Inflate bound element bounds with heading-aware padding.
   - Split overlapping obstacles so the grid has viable gaps.
   - Compute exit points where the route leaves each obstacle.

4) Direct orthogonal route (when aligned)
   - If endpoints are axis-aligned, headings are compatible, and the
     segment does not intersect obstacles, return a 2-point path.

5) Sparse grid routing (A*)
   - Build a sparse grid from obstacle edges and endpoints.
   - Run A* with bend penalties to prefer fewer elbows.
   - If A* fails, fall back to a stable midpoint elbow.

6) Post-process path
   - Ensure all segments are orthogonal.
   - Remove tiny segments and keep only corner points.
   - Clamp coordinates to avoid runaway values.

7) Return result
   - Provide routed world-space points and resolved endpoints.

## Editing Pipeline (computeElbowEdit)
1) Resolve inputs
   - Resolve base local points from element geometry.
   - Apply incoming point overrides.
   - Sanitize fixed segments and apply binding overrides.

2) Select edit mode
   - No fixed segments: re-route a fresh elbow path.
   - Fixed segment release: re-route only the released region.
   - Endpoint drag: preserve fixed segments while endpoints move.
   - Fixed segment update: re-apply fixed axes and simplify.

### Edit Mode Decision
- fixedSegments.isEmpty → routeFresh
- releaseRequested → releaseFixedSegments
- pointsChanged && !fixedSegmentsChanged → dragEndpoints
- otherwise → applyFixedSegments

3) Fresh routing (no fixed segments)
   - Route in world space, convert back to local points.

4) Fixed segment release
   - Identify removed fixed indices.
   - Re-route only the released span (respecting bindings when present).
   - Re-apply fixed segments, simplify, and reindex.

5) Endpoint drag with fixed segments
   - Apply endpoint overrides to a stable reference path.
   - Adopt a bound-aware baseline route when bindings exist.
   - Enforce fixed segment axes, reroute diagonals if unbound.
   - Snap neighbors to preserve orthogonality.
   - Enforce perpendicular segments at bound endpoints.

6) Fixed segment updates
   - Apply axes changes to the current points.
   - Simplify and reindex to keep the path stable.

7) Return result
   - Local points and updated fixed segments (or null if none remain).

## Invariants
- Routed and edited paths are orthogonal.
- Bound endpoints respect the bound element heading.
- Arrowhead gaps are preserved for bound endpoints.
- Fixed segments keep their axis position after edits.
- Points are deduplicated and stabilized after edits.

## Test Matrix
Routing
- elbow_router_behavior_test.dart
  Fallback routing (aligned, short, and incompatible headings).
- elbow_router_anchor_test.dart
  Bound endpoint approach direction and obstacle avoidance.
- elbow_router_grid_test.dart
  Sparse grid routing around obstacles + corner-only cleanup.
- elbow_router_element_route_test.dart
  Local/world mapping consistency for routed elements.

Editing
- elbow_edit_pipeline_test.dart
  Fixed segment release, endpoint drag, and binding enforcement.
- elbow_fixed_segments_test.dart
  Fixed segment mapping and reindexing behavior.
- elbow_transform_fixed_segments_test.dart
  Fixed segment transforms across element changes.

Shared
- elbow_binding_gap_test.dart
  Arrowhead gap behavior for bindings.
- elbow_geometry_test.dart
  Geometry helper correctness.
- elbow_edge_cases_test.dart
  Missing bindings, sanitization, and early-return conditions.
