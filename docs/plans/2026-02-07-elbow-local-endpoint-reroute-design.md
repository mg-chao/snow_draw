# Elbow local endpoint reroute design (fixed segments)

## Summary
When an elbow arrow endpoint is dragged or bound/unbound and fixed segments
exist, only the span between the active endpoint and the nearest fixed segment
should be recomputed. The rest of the path remains unchanged. The nearest
fixed segment is the first fixed segment on that endpoint side (by index
order). The fixed segment keeps its direction but may slide along its axis and
change length. This applies to both start and end endpoints.

## Goals
- Update only the endpoint-side span during endpoint drag and binding changes.
- Preserve untouched prefix/suffix points beyond the nearest fixed segment.
- Keep fixed segment direction and axis stable while allowing length changes.
- Preserve existing behavior when no fixed segments exist.

## Non-goals
- Do not change routing when both endpoints are active at the same time.
- Do not alter routing behavior for non-elbow arrows.

## Pipeline change
Add a local reroute step in `elbow_edit_endpoint_drag.dart` after Step A
(endpoint overrides) and before Step B (baseline reroute).

### Trigger
- `fixedSegments.isNotEmpty`
- Exactly one active side (`startActive != endActive`).
- Activity includes endpoint move or binding change (including unbind).

### Local reroute algorithm (one side)
1. Select nearest fixed segment:
   - Start side: `fixedSegments.first`.
   - End side: `fixedSegments.last`.
2. Determine anchor index:
   - Start side: `anchorIndex = segment.index`.
   - End side: `anchorIndex = segment.index - 1`.
3. Route a local path between the active endpoint and the anchor using
   `_routeReleasedRegion`, with only the active side binding/arrowhead.
4. Splice the new local path with the unchanged remainder of the original
   points (prefix or suffix).
5. Sync fixed segments to points:
   - Use `_reindexFixedSegments` if the point count or order changes.
   - Otherwise `_syncFixedSegmentsToPoints`.
6. If reindexing drops segments or indices are invalid, fall back to the
   original state and continue the normal pipeline.

### Interaction with existing steps
- If local reroute succeeds, skip Step B (baseline route).
- Step C (binding removal reroute) must avoid re-routing the same side again
  to prevent double changes.
- Continue Steps D-J unchanged to enforce axes, perpendicular bindings, and
  collinear merges.

## Error handling
- Treat local reroute as best-effort; any invalid indices, empty routes, or
  reindex failures revert to baseline behavior.
- Never silently drop fixed segments.

## Tests
Add tests in `packages/snow_draw_core/test/elbow_edit_pipeline_test.dart`:
- End binding change on a path with two fixed segments only updates the final
  span; prefix points remain identical.
- Start binding change mirrors the behavior on the prefix side.
- Unbind without endpoint movement still triggers local reroute, and the
  non-active side remains unchanged.
- Ensure orthogonality and fixed segment count are preserved.
