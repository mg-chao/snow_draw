# Orthogonal Connector (Elbow Arrow) Greenfield Rewrite Design

Date: 2026-02-06
Owner: Codex
Status: Draft (approved in conversation)

## Summary
We will rebuild the elbow arrow feature as a new, pure-geometry core in
`packages/snow_draw_core`, with a redesigned public API and routing/editing
engine. The new implementation must match user-facing behavior of Excalidraw’s
orthogonal connectors while not reusing existing code structures, utilities, or
coordinate logic. The engine will be deterministic, immutable, and optimized for
routing between two axis-aligned bounding boxes. It will prioritize human-
intuitive paths (minimal length, minimal bends, proper orientation, and obstacle
avoidance) while supporting pinned segments and stable topology transitions.

## Goals
- Produce orthogonal routes that feel human-drawn (short, clean, readable).
- Enforce strict axis alignment and obstacle avoidance.
- Maintain stable bindings to elements across movement/resize/rotate.
- Support segment dragging (pinned segments) and endpoint dragging.
- Preserve path topology when possible and transition smoothly when needed.
- Pass all existing elbow tests and add coverage for the new spec.

## Non-goals
- Support more than two obstacles (source + target only).
- Provide UI or rendering changes in the app layer.
- Introduce a third-party state management or routing library.

## Constraints and principles
- Pure geometry: no rendering context or display transforms in core logic.
- Immutable route state: updates return new plans.
- Lazy, infinite-grid routing: do not precompute global fields.
- Use only conceptual guidance from Excalidraw, not code/utility reuse.

## Public API (new)
All types live under `draw/elements/types/arrow/orthogonal/` (new folder).

- `OrthogonalRoutePlan`:
  - `points` (world-space `List<DrawPoint>`)
  - `segments` (axis, length, pinned flag)
  - `start`, `end` (resolved anchors)
  - `status` (ok / fallback / degraded)

- `AnchorSpec`:
  - element id, normalized anchor, arrowhead info

- `ResolvedAnchor`:
  - world point, preferred departure axis + direction, clearance distance

- `PinnedSegment`:
  - axis (horizontal/vertical), fixed coordinate, index

- Core functions (pure):
  - `routeOrthogonal(...)` (main routing entry)
  - `routeOrthogonalForElement(...)` (world/local conversion helper)
  - `reRouteWithPinnedSegments(...)` (used by edit flows)
  - `translateSegment(...)` (used by UI, returns pinned constraints + plan)

## Data model and state
- Route plans are immutable and self-describing.
- Editing operations work by producing new plans with updated pinned segments.
- The app stores `OrthogonalRoutePlan` in arrow data and reuses it across edits.

## Routing pipeline
1) Resolve anchors
   - Convert `AnchorSpec` + element bounds into `ResolvedAnchor`.
   - Compute a preferred departure direction based on side and arrowhead.
   - Compute clearance distance (arrowhead gap + binding gap).

2) Build obstacle field
   - Create two axis-aligned obstacle boxes with padding.
   - If an anchor overlaps its own bound element, mark that obstacle as
     non-blocking for that endpoint only.

3) Fast paths
   - Short arrow path: for small Manhattan distance, return a 1-bend stable
     midpoint route to avoid meandering.
   - Aligned path: if start/end align and departure directions are compatible,
     return a straight segment.

4) Sparse-grid A* (lazy)
   - Search nodes are intersections of candidate x/y coordinates generated on
     demand. Candidate coordinates are derived from:
     - start/end x/y
     - obstacle edges +/- padding
     - pinned segment coordinates
     - heading-aligned extension lines
   - Expansion: from a node, extend along the current axis until the next
     “interesting” coordinate or obstacle boundary is reached.

5) Cleanup and validation
   - Enforce strict orthogonality.
   - Merge collinear segments, remove tiny segments.
   - Clamp endpoints to resolved anchors and preserve preferred departure axes.
   - Validate obstacle intersections, fallback if invalid.

## A* cost model (human-intuitive routing)
- g(n): cumulative cost = distance + bend penalties + aesthetic penalties.
- h(n): Manhattan distance to target + heading/orientation penalties.
- Bend penalty: large cost for each turn to minimize segments.
- Backtracking prevention: block immediate U-turns and repeated traversal of
  the same axis in opposite directions unless no alternatives exist.
- Segment length preference: reward longer straight segments to avoid
  stair-step patterns.
- Side-aware obstacle routing: prefer routes that go around shorter sides of
  obstacles when both options are viable.
- Overlap handling: if a shape contains the start/end, disable avoidance for
  that shape to ensure a valid path exists.

## Editing flows
- Segment dragging:
  - Translate the dragged segment along its perpendicular axis.
  - Pin the segment’s coordinate (axis + fixed value) and re-route the rest.
- Endpoint dragging:
  - Resolve new anchors and re-route with existing pinned segments.
- Pinned segments are preserved across element moves unless they become
  geometrically impossible; in that case, return a degraded plan and reset the
  pin.

## Topology transitions
- The router will prefer fewer bends as elements align.
- Re-route with pinned constraints first; if not possible, relax pins one at a
  time (oldest pin last) to reach a valid minimal-bend route.
- Transitions should preserve direction and avoid “flip-flopping” between
  equivalent routes.

## Error handling and fallbacks
- Node expansion has a budget; if exceeded or no path is found, fallback to
  deterministic 1- or 2-bend midpoints respecting anchor headings.
- Return a `status` flag for UI logging via `LogService`.

## Testing plan
- Keep existing elbow tests as acceptance baseline.
- Add new tests for:
  - Pinned segment persistence across element movement.
  - Backtracking prevention (no immediate U-turns unless required).
  - Short-arrow direct routing stability.
  - Overlap allowances for bound elements.
  - Segment drag + endpoint drag interactions.

## Integration and migration
- Replace existing elbow routing and editing modules with the new orthogonal
  connector engine.
- Update call sites in arrow edit operations to use new API.
- Keep UI contracts unchanged except for updated data structures.

## Open questions
- Exact node budget defaults and how to expose them (config vs constant).
- Whether to persist route plan metadata in serialized arrow data or derive it
  at load time.
