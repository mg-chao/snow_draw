# Implementation Plan: Simplify Elbow Arrow

## Overview

Incremental refactoring of the elbow arrow implementation from 19 files to 13 files, extracting reusable utilities and eliminating duplication. Each step preserves all existing tests. The implementation language is Dart, targeting `packages/snow_draw_core`.

## Tasks

- [x] 1. Extract BinaryHeap into a standalone generic utility
  - [x] 1.1 Create `packages/snow_draw_core/lib/draw/utils/binary_heap.dart` with a public generic `BinaryHeap<T>` class
    - Extract the `_BinaryHeap` from `elbow_router_grid.dart` verbatim
    - Make it public, replace `Object?` cast with typed `T` scoring function
    - Add dartdoc for the public API (`push`, `pop`, `rescore`, `isEmpty`, `isNotEmpty`)
    - _Requirements: 1.1, 1.2, 1.3_
  - [ ]* 1.2 Write property test for BinaryHeap
    - Add `glados` as a dev dependency in `packages/snow_draw_core/pubspec.yaml`
    - Create `packages/snow_draw_core/test/binary_heap_property_test.dart`
    - **Property 1: BinaryHeap always pops the minimum-scored element**
    - **Validates: Requirements 1.3**
  - [x] 1.3 Update `elbow_router_grid.dart` to import and use the extracted `BinaryHeap`
    - Remove the inlined `_BinaryHeap` class
    - Import `binary_heap.dart` and use `BinaryHeap<_ElbowGridNode>`
    - _Requirements: 1.1, 1.4_

- [x] 2. Checkpoint — Ensure all tests pass
  - Run `flutter test` in `packages/snow_draw_core`
  - Ensure all existing elbow tests pass with no assertion changes
  - Ensure the new BinaryHeap property test passes
  - Ask the user if questions arise.

- [x] 3. Consolidate ElbowPathUtils into ElbowGeometry
  - [x] 3.1 Merge `ElbowPathUtils` methods and `ElbowAxis` enum into `elbow_geometry.dart`
    - Move the `ElbowAxis` enum into `elbow_geometry.dart`
    - Add all `ElbowPathUtils` static methods to `ElbowGeometry` as static methods
    - Keep the same method signatures and behavior
    - _Requirements: 3.1, 3.2_
  - [x] 3.2 Update all call sites from `ElbowPathUtils.xxx` to `ElbowGeometry.xxx`
    - Update imports in all elbow routing and editing part files
    - Update imports in test files that reference `ElbowPathUtils`
    - _Requirements: 3.1, 3.3_
  - [x] 3.3 Delete `elbow_path_utils.dart`
    - _Requirements: 3.2_

- [x] 4. Checkpoint — Ensure all tests pass
  - Run `flutter test` in `packages/snow_draw_core`
  - Ensure all existing elbow tests pass with at most import-path changes
  - Ask the user if questions arise.

- [x] 5. Unify spacing harmonization logic
  - [x] 5.1 Add unified spacing resolution and application helpers to `elbow_spacing.dart`
    - Add `resolveObstacleSpacing(elementBounds, obstacle, heading)` — extracted from `_resolveObstacleSpacing` in `elbow_router_obstacles.dart`
    - Add `applyObstacleSpacing(obstacle, elementBounds, heading, spacing)` — extracted from `_applyObstacleSpacing`
    - Add `minBindingSpacing(hasArrowhead)` — extracted from the duplicated `_minBindingSpacing`
    - Keep these as top-level library-private functions or static methods on `ElbowSpacing`
    - _Requirements: 2.1, 2.2, 2.4_
  - [x] 5.2 Update `elbow_router_obstacles.dart` to use the unified spacing functions
    - Replace `_resolveObstacleSpacing`, `_applyObstacleSpacing`, `_minBindingSpacing` calls with the new unified versions
    - Remove the local duplicates
    - _Requirements: 2.1, 2.5, 6.1_
  - [x] 5.3 Update `elbow_router_path.dart` to use the unified spacing functions for segment harmonization
    - Replace `_segmentSpacing` and `_applySegmentSpacing` with versions that delegate to shared axis-resolution logic
    - Remove the local `_minBindingSpacing` duplicate
    - _Requirements: 2.1, 2.3, 2.5_
  - [ ]* 5.4 Write property tests for spacing harmonization
    - Create `packages/snow_draw_core/test/elbow_spacing_property_test.dart`
    - **Property 2: Obstacle spacing apply-then-resolve round trip**
    - **Validates: Requirements 2.2, 2.4**
    - **Property 3: Segment spacing apply-then-resolve round trip**
    - **Validates: Requirements 2.3, 2.4**

- [x] 6. Checkpoint — Ensure all tests pass
  - Run `flutter test` in `packages/snow_draw_core`
  - Ensure all existing elbow tests pass
  - Ensure the new spacing property tests pass
  - Ask the user if questions arise.

- [x] 7. Consolidate routing part files (5 → 3)
  - [x] 7.1 Merge `elbow_router_endpoints.dart` into `elbow_router_pipeline.dart`
    - Move all endpoint resolution types (`_EndpointInfo`, `_ResolvedEndpoint`, `_ResolvedEndpoints`) and functions (`_resolveEndpointInfo`, `_resolveEndpointHeading`, `_resolveRouteEndpoints`) into `elbow_router_pipeline.dart`
    - Remove the `part 'elbow_router_endpoints.dart';` directive from `elbow_router.dart`
    - Delete `elbow_router_endpoints.dart`
    - _Requirements: 4.1, 4.2, 4.3_
  - [x] 7.2 Merge `elbow_router_grid.dart` into `elbow_router_path.dart`
    - Move all grid types (`_ElbowGrid`, `_ElbowGridNode`, `_ElbowGridAddress`, `_ElbowGridRouter`, `_ElbowNeighborOffset`, `_BendPenalty`) and functions (`_buildGrid`, `_tryRouteGridPath`, `_reconstructPath`, etc.) into `elbow_router_path.dart`
    - The `_BinaryHeap` is already extracted; only the grid-specific code moves
    - Remove the `part 'elbow_router_grid.dart';` directive from `elbow_router.dart`
    - Delete `elbow_router_grid.dart`
    - _Requirements: 4.1, 4.2, 4.3_

- [x] 8. Consolidate editing part files (6 → 4)
  - [x] 8.1 Merge `elbow_edit_geometry.dart` into `elbow_edit_pipeline.dart`
    - Move `_resolveLocalPoints`, `_pointsEqual`, `_pointsEqualExceptEndpoints` into `elbow_edit_pipeline.dart`
    - Remove the `part 'elbow_edit_geometry.dart';` directive from `elbow_editing.dart`
    - Delete `elbow_edit_geometry.dart`
    - _Requirements: 5.1, 5.2, 5.3_
  - [x] 8.2 Merge `elbow_edit_routing.dart` into `elbow_edit_fixed_segments.dart`
    - Move `_routeLocalPath`, `_routeReleasedRegion`, `_handleFixedSegmentRelease`, `_resolveRemovedFixedIndices`, `_preferredHorizontalForRelease` into `elbow_edit_fixed_segments.dart`
    - Remove the `part 'elbow_edit_routing.dart';` directive from `elbow_editing.dart`
    - Delete `elbow_edit_routing.dart`
    - _Requirements: 5.1, 5.2, 5.3_

- [x] 9. Checkpoint — Ensure all tests pass
  - Run `flutter test` in `packages/snow_draw_core`
  - Ensure all existing elbow tests pass with at most import-path changes
  - Ask the user if questions arise.

- [x] 10. Simplify obstacle layout builder
  - [x] 10.1 Refactor `_ElbowObstacleLayoutBuilder.resolve()` to use clearer step sequencing
    - Replace deeply nested helper calls with a flat sequence of named steps
    - Use the unified spacing functions from `ElbowSpacing`
    - Inline or simplify the `_generateDynamicAabbs` / `_dynamicAabbFor` / `_computeMinEdge` / `_computeMaxEdge` chain into more readable helpers
    - _Requirements: 6.1, 6.2, 6.3_

- [ ] 11. Write ElbowFixedSegment property tests
  - [ ]* 11.1 Write property test for ElbowFixedSegment serialization round trip
    - Create `packages/snow_draw_core/test/elbow_fixed_segment_property_test.dart`
    - **Property 4: ElbowFixedSegment serialization round trip**
    - **Validates: Requirements 8.1**
  - [ ]* 11.2 Write property test for ElbowFixedSegment invalid JSON rejection
    - **Property 5: ElbowFixedSegment rejects invalid JSON**
    - **Validates: Requirements 8.2**

- [x] 12. Clean up and delete empty orthogonal directory
  - Delete the empty `elbow/orthogonal/` directory
  - Verify final file count is 13 (down from 19 + 1 empty dir)
  - _Requirements: 4.1, 5.1_

- [x] 13. Final checkpoint — Ensure all tests pass
  - Run `flutter test` in `packages/snow_draw_core`
  - Ensure all existing elbow tests pass
  - Ensure all new property tests pass
  - Run `melos run lint` to verify no new lint warnings
  - Ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Checkpoints ensure incremental validation after each major change
- Property tests validate universal correctness properties of extracted components
- Unit tests (existing suite) validate specific examples and edge cases
- The `glados` package is needed as a dev dependency for property-based testing
- After adding `glados`, run `melos bootstrap` to refresh the workspace
