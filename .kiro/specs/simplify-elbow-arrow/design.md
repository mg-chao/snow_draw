# Design Document: Simplify Elbow Arrow

## Overview

This refactoring simplifies the elbow arrow implementation (19 files across two `part of` libraries) by:

1. Extracting the inlined `_BinaryHeap` into a standalone generic utility.
2. Unifying the duplicated spacing harmonization logic (obstacle-exit vs segment-spacing) into a single module.
3. Consolidating the overlapping `ElbowGeometry` and `ElbowPathUtils` classes into one cohesive geometry module.
4. Reducing the routing part-file count from 5 to 3 by merging tightly coupled files.
5. Reducing the editing part-file count from 6 to 4 by merging tightly coupled files.
6. Simplifying the obstacle layout builder to use the unified spacing module and clearer step sequencing.

All changes are pure refactoring — no behavioral changes. Every existing test must pass with at most import-path updates.

## Architecture

### Current Structure (19 files)

```
elbow/
├── elbow_router.dart              (library, 5 parts)
│   ├── elbow_router_pipeline.dart
│   ├── elbow_router_endpoints.dart
│   ├── elbow_router_obstacles.dart
│   ├── elbow_router_grid.dart
│   └── elbow_router_path.dart
├── elbow_editing.dart             (library, 6 parts)
│   ├── elbow_edit_pipeline.dart
│   ├── elbow_edit_endpoint_drag.dart
│   ├── elbow_edit_fixed_segments.dart
│   ├── elbow_edit_geometry.dart
│   ├── elbow_edit_perpendicular.dart
│   └── elbow_edit_routing.dart
├── elbow_constants.dart
├── elbow_geometry.dart
├── elbow_heading.dart
├── elbow_path_utils.dart
├── elbow_spacing.dart
├── elbow_fixed_segment.dart
└── orthogonal/                    (empty)
```

### Target Structure (13 files)

```
elbow/
├── elbow_router.dart              (library, 3 parts)
│   ├── elbow_router_pipeline.dart (pipeline + endpoints merged)
│   ├── elbow_router_obstacles.dart(obstacles + spacing harmonization via shared module)
│   └── elbow_router_path.dart     (path + grid merged, grid uses extracted BinaryHeap)
├── elbow_editing.dart             (library, 4 parts)
│   ├── elbow_edit_pipeline.dart   (pipeline + geometry merged)
│   ├── elbow_edit_endpoint_drag.dart
│   ├── elbow_edit_fixed_segments.dart (fixed segments + routing merged)
│   └── elbow_edit_perpendicular.dart
├── elbow_constants.dart           (unchanged)
├── elbow_geometry.dart            (consolidated: absorbs ElbowPathUtils)
├── elbow_heading.dart             (unchanged)
├── elbow_spacing.dart             (expanded: absorbs harmonization logic)
├── elbow_fixed_segment.dart       (unchanged)
└── (delete) elbow_path_utils.dart (merged into elbow_geometry.dart)
└── (delete) orthogonal/           (empty directory removed)
```

### Extracted Utility

```
draw/utils/
└── binary_heap.dart               (new generic utility)
```

### Merge Rationale

**Routing merges:**
- `elbow_router_endpoints.dart` → into `elbow_router_pipeline.dart`: Endpoints are only used by the pipeline; they share the `_ResolvedEndpoint` types and are always read together. Combined ~220 lines.
- `elbow_router_grid.dart` → into `elbow_router_path.dart`: The grid is only called from path construction; the A* router and path post-processing are a single logical flow. The `_BinaryHeap` moves out to a shared utility. Combined ~750 lines (down from ~850 after BinaryHeap extraction).

**Editing merges:**
- `elbow_edit_geometry.dart` → into `elbow_edit_pipeline.dart`: Only 3 small helper functions (~50 lines) used exclusively by the pipeline.
- `elbow_edit_routing.dart` → into `elbow_edit_fixed_segments.dart`: The routing helpers are only called during fixed-segment release and re-routing flows. Combined ~400 lines.

## Components and Interfaces

### 1. BinaryHeap (new: `draw/utils/binary_heap.dart`)

```dart
/// A generic min-heap that orders elements by a caller-supplied score.
///
/// Used by the elbow A* grid router and available for reuse by other
/// subsystems that need priority-queue behavior.
class BinaryHeap<T> {
  BinaryHeap(this._score);

  final double Function(T) _score;

  bool get isEmpty;
  bool get isNotEmpty;

  void push(T element);
  T? pop();
  void rescore(T element);
}
```

Public API. Extracted verbatim from the current `_BinaryHeap` in `elbow_router_grid.dart`, made public and generic with a typed scoring function (currently uses `Object?` cast internally).

### 2. Unified Spacing Module (expanded: `elbow_spacing.dart`)

Current `ElbowSpacing` has 3 methods. We add a private `ElbowSpacingHarmonizer` mixin or set of top-level functions that unify the duplicated logic:

```dart
// Existing public API (unchanged):
class ElbowSpacing {
  static double bindingGap({required bool hasArrowhead});
  static double headPadding({required bool hasArrowhead});
  static double fixedNeighborPadding({required bool hasArrowhead});
}

// New: unified harmonization helpers (library-private, used by router)
double resolveSpacingForObstacle({
  required DrawRect elementBounds,
  required DrawRect obstacle,
  required ElbowHeading heading,
});

double resolveSpacingForSegment({
  required _RouteSegment segment,
  required DrawRect bounds,
  required ElbowHeading heading,
});

DrawRect applySpacingToObstacle({
  required DrawRect obstacle,
  required DrawRect elementBounds,
  required ElbowHeading heading,
  required double spacing,
});

void applySpacingToSegment({
  required List<DrawPoint> points,
  required _RouteSegment segment,
  required DrawRect bounds,
  required ElbowHeading heading,
  required double spacing,
});

double minBindingSpacing({required bool hasArrowhead});
```

The obstacle and segment variants differ only in how they read the current spacing value (obstacle edge vs segment midpoint). The apply variants differ in what they write to (obstacle rect vs point list). Both share the heading-axis switch logic and min-spacing clamping.

Since the `_RouteSegment` type is private to the router library, the segment-specific functions will remain inside the router's part files but delegate to shared axis-resolution logic in `elbow_spacing.dart`.

### 3. Consolidated Geometry (expanded: `elbow_geometry.dart`)

`ElbowPathUtils` is absorbed into `ElbowGeometry`. All existing call sites update their import and class prefix.

```dart
class ElbowGeometry {
  // Existing (unchanged):
  static ElbowHeading headingForVector(double dx, double dy);
  static ElbowHeading headingForSegment(DrawPoint from, DrawPoint to);
  static double manhattanDistance(DrawPoint a, DrawPoint b);
  static bool isHorizontal(DrawPoint a, DrawPoint b);
  static ElbowHeading headingForPointOnBounds(DrawRect bounds, DrawPoint point);

  // Absorbed from ElbowPathUtils:
  static ElbowAxis? axisAlignedForSegment(DrawPoint a, DrawPoint b, {double epsilon});
  static ElbowAxis axisForSegment(DrawPoint a, DrawPoint b, {double epsilon});
  static bool segmentIsHorizontal(DrawPoint a, DrawPoint b, {double epsilon});
  static bool segmentIsVertical(DrawPoint a, DrawPoint b, {double epsilon});
  static double axisValue(DrawPoint start, DrawPoint end, {required ElbowAxis axis});
  static bool pointsClose(DrawPoint a, DrawPoint b, {double epsilon});
  static bool pointsAligned(DrawPoint a, DrawPoint b, {double epsilon});
  static bool segmentsCollinear(DrawPoint a, DrawPoint b, DrawPoint c, {double epsilon});
  static List<DrawPoint> directElbowPath(DrawPoint start, DrawPoint end, {required bool preferHorizontal, double epsilon});
  static List<DrawPoint> removeShortSegments(List<DrawPoint> points, {double minLength});
  static List<DrawPoint> cornerPoints(List<DrawPoint> points);
  static List<DrawPoint> simplifyPath(List<DrawPoint> points, {Set<DrawPoint> pinned});
  static bool hasDiagonalSegments(List<DrawPoint> points);
}
```

The `ElbowAxis` enum moves into `elbow_geometry.dart` as well (currently in `elbow_path_utils.dart`).

### 4. Router Part-File Consolidation

After merging:

| New file | Contains | Origin |
|---|---|---|
| `elbow_router_pipeline.dart` | `_ElbowRouteRequest`, `_ElbowRouteContext`, `_ElbowRoutePipeline`, `_ElbowRoutePlan`, endpoint resolution types and functions | `elbow_router_pipeline.dart` + `elbow_router_endpoints.dart` |
| `elbow_router_obstacles.dart` | Obstacle layout builder, bounds inflation/clamping/splitting, dynamic AABB, exit positions (uses unified spacing from `elbow_spacing.dart`) | `elbow_router_obstacles.dart` (simplified) |
| `elbow_router_path.dart` | Direct path checks, fallback paths, grid building, A* routing (uses extracted `BinaryHeap`), post-processing, segment spacing harmonization | `elbow_router_path.dart` + `elbow_router_grid.dart` |

### 5. Editor Part-File Consolidation

After merging:

| New file | Contains | Origin |
|---|---|---|
| `elbow_edit_pipeline.dart` | Pipeline orchestration, mode selection, context building, `_resolveLocalPoints`, `_pointsEqual`, `_pointsEqualExceptEndpoints` | `elbow_edit_pipeline.dart` + `elbow_edit_geometry.dart` |
| `elbow_edit_endpoint_drag.dart` | Endpoint drag flow (unchanged) | `elbow_edit_endpoint_drag.dart` |
| `elbow_edit_fixed_segments.dart` | Fixed segment sanitization, reindexing, mapping, simplification, release handling, routing helpers | `elbow_edit_fixed_segments.dart` + `elbow_edit_routing.dart` |
| `elbow_edit_perpendicular.dart` | Perpendicular binding enforcement (unchanged) | `elbow_edit_perpendicular.dart` |

## Data Models

No data model changes. All existing types are preserved:

- `ElbowRouteResult` — immutable, holds routed points + resolved start/end.
- `ElbowRoutedPoints` — immutable, holds local + world point lists.
- `ElbowEditResult` — immutable, holds local points + optional fixed segments.
- `ElbowFixedSegment` — immutable, JSON-serializable pinned segment with index, start, end.
- `ElbowHeading` — enum with `right`, `down`, `left`, `up` and extensions.
- `ElbowAxis` — enum with `horizontal`, `vertical` (moves from `elbow_path_utils.dart` to `elbow_geometry.dart`).
- `ElbowConstants` — static constants class (unchanged).
- `DrawPoint`, `DrawRect` — core geometry types (unchanged, external to elbow).


## Correctness Properties

*A property is a characteristic or behavior that should hold true across all valid executions of a system — essentially, a formal statement about what the system should do. Properties serve as the bridge between human-readable specifications and machine-verifiable correctness guarantees.*

Since this is a pure refactoring, most requirements are structural (code organization) or behavioral-equivalence (existing tests must pass). The testable properties focus on the extracted/unified components that have well-defined functional contracts.

### Property 1: BinaryHeap always pops the minimum-scored element

*For any* sequence of push operations with arbitrary scores, calling `pop()` SHALL always return the element with the lowest score among all elements currently in the heap. After popping, the next `pop()` SHALL return the next-lowest, and so on until the heap is empty.

**Validates: Requirements 1.3**

### Property 2: Obstacle spacing apply-then-resolve round trip

*For any* valid `DrawRect` obstacle, `DrawRect` element bounds (where the obstacle edge extends beyond the element edge along the heading axis), and `ElbowHeading`, applying a spacing value via `applySpacingToObstacle` and then resolving it via `resolveSpacingForObstacle` SHALL return the same spacing value (within floating-point epsilon).

**Validates: Requirements 2.2, 2.4**

### Property 3: Segment spacing apply-then-resolve round trip

*For any* valid route segment (a pair of axis-aligned points forming a segment with a midpoint), `DrawRect` element bounds, `ElbowHeading`, and positive spacing value, applying the spacing via `applySpacingToSegment` and then resolving it via `resolveSpacingForSegment` SHALL return the same spacing value (within floating-point epsilon).

**Validates: Requirements 2.3, 2.4**

### Property 4: ElbowFixedSegment serialization round trip

*For any* valid `ElbowFixedSegment` (non-negative index, finite start/end coordinates), calling `toJson()` then `ElbowFixedSegment.fromJson()` on the result SHALL produce an `ElbowFixedSegment` that is equal to the original.

**Validates: Requirements 8.1**

### Property 5: ElbowFixedSegment rejects invalid JSON

*For any* JSON map that is missing required fields (`index`, `start`, `end`) or contains non-numeric values for coordinates, `ElbowFixedSegment.fromJson()` SHALL throw a `FormatException`.

**Validates: Requirements 8.2**

## Error Handling

This refactoring does not introduce new error paths. Existing error handling is preserved:

- **BinaryHeap.pop()** on an empty heap returns `null` (unchanged behavior).
- **ElbowFixedSegment.fromJson()** throws `FormatException` on invalid payloads (unchanged behavior).
- **Spacing resolution** returns `null` when the computed spacing is non-finite or below epsilon (unchanged behavior).
- **Grid routing** returns `null` when A* finds no path, triggering the fallback path (unchanged behavior).
- **Fixed segment sanitization** silently drops invalid segments (out-of-range indices, diagonal segments, zero-length segments) — unchanged behavior.

## Testing Strategy

### Existing Tests (must all pass, import-only changes allowed)

The following test files validate current behavior and serve as the primary regression safety net:

- `elbow_spacing_consistency_test.dart`
- `elbow_segment_balance_test.dart`
- `elbow_transform_fixed_segments_test.dart`
- `rotate_elbow_exclusion_test.dart`
- `elbow_binding_gap_test.dart`
- `elbow_edge_cases_test.dart`
- `elbow_edit_pipeline_test.dart`
- `elbow_fixed_segments_test.dart`
- `elbow_geometry_test.dart`
- `elbow_route_stability_test.dart`
- `elbow_router_anchor_test.dart`
- `elbow_router_behavior_test.dart`
- `elbow_router_element_route_test.dart`
- `elbow_router_fallback_constraints_test.dart`
- `elbow_router_grid_test.dart`
- `elbow_router_spacing_test.dart`

### New Unit Tests

- **BinaryHeap unit tests**: Push/pop sequences, rescore behavior, empty-heap edge cases.
- **Consolidated geometry smoke tests**: Verify that `ElbowGeometry` methods formerly on `ElbowPathUtils` produce identical results (specific examples from existing test data).

### Property-Based Tests

The project does not currently use a property-based testing library. We will use the `glados` package (a Dart PBT library) added as a dev dependency to `packages/snow_draw_core`.

Each correctness property maps to a single property-based test with a minimum of 100 iterations. Tests are tagged with their design property reference.

- **Property 1** → `binary_heap_property_test.dart` — Generate random sequences of push/pop/rescore operations; verify pop always returns the minimum.
- **Property 2** → `elbow_spacing_property_test.dart` — Generate random obstacle rects, element bounds, headings, and spacing values; verify apply-then-resolve round trip.
- **Property 3** → `elbow_spacing_property_test.dart` — Generate random segments, element bounds, headings, and spacing values; verify apply-then-resolve round trip.
- **Property 4** → `elbow_fixed_segment_property_test.dart` — Generate random ElbowFixedSegment instances; verify toJson/fromJson round trip.
- **Property 5** → `elbow_fixed_segment_property_test.dart` — Generate random invalid JSON maps; verify FormatException is thrown.

Tag format: `// Feature: simplify-elbow-arrow, Property N: <title>`

### Dual Testing Approach

- **Unit tests** cover specific examples, edge cases, and integration points (existing tests + new BinaryHeap/geometry smoke tests).
- **Property tests** cover universal invariants across randomized inputs (5 properties above).
- Together they provide comprehensive coverage: unit tests catch concrete regressions, property tests verify general correctness of extracted components.
