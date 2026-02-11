# Requirements Document

## Introduction

The elbow arrow implementation in `packages/snow_draw_core` has grown to 19 files across two `part of` libraries (routing and editing). Multiple iterations have introduced duplicated spacing/harmonization logic, an inlined custom BinaryHeap, overlapping geometry helpers, and overly fragmented part files. This refactoring simplifies the implementation by extracting reusable generic utilities, consolidating duplicated logic, and reducing file count — all while preserving identical runtime behavior and keeping every existing test green.

## Glossary

- **Elbow_Router**: The routing subsystem that computes orthogonal paths between two endpoints, avoiding obstacles. Entry point: `routeElbowArrow()`.
- **Elbow_Editor**: The editing subsystem that adjusts elbow paths when users drag endpoints or pin segments. Entry point: `computeElbowEdit()`.
- **BinaryHeap**: A min-heap data structure used by the A* grid router to efficiently select the next node with the lowest cost.
- **Spacing_Harmonizer**: Logic that equalizes the gap between routed segments and bound element edges so both ends of an arrow look visually balanced.
- **Fixed_Segment**: A user-pinned segment of an elbow path whose axis position is preserved during edits.
- **Obstacle_Layout**: The padded bounding boxes around bound elements that the router must avoid.
- **Path_Utils**: Shared helpers for deduplication, collinearity detection, corner extraction, and simplification of orthogonal point lists.
- **Geometry_Helpers**: Functions for cardinal heading detection, Manhattan distance, axis alignment, and triangle-based quadrant tests.

## Requirements

### Requirement 1: Extract Generic BinaryHeap Utility

**User Story:** As a developer, I want the BinaryHeap to be a standalone, reusable generic class, so that it can be tested independently and reused by other subsystems.

#### Acceptance Criteria

1. THE Elbow_Router SHALL use a BinaryHeap class that resides outside the `elbow_router.dart` part-of library in a shared utility location within `snow_draw_core`.
2. THE BinaryHeap SHALL be a generic class parameterized by element type with a caller-supplied scoring function.
3. THE BinaryHeap SHALL support push, pop, rescore, isEmpty, and isNotEmpty operations with the same semantics as the current inlined implementation.
4. WHEN the BinaryHeap is extracted, THE Elbow_Router SHALL produce identical routing results for all inputs.

### Requirement 2: Unify Spacing Harmonization Logic

**User Story:** As a developer, I want a single spacing harmonization module, so that the duplicated obstacle-exit and segment-spacing code is maintained in one place.

#### Acceptance Criteria

1. THE Spacing_Harmonizer SHALL provide a single set of functions that both the Elbow_Router obstacle phase and the Elbow_Router post-process phase call for resolving, comparing, and applying spacing values.
2. WHEN spacing is resolved for an obstacle boundary, THE Spacing_Harmonizer SHALL compute the distance between the element bounds edge and the obstacle edge along the heading axis.
3. WHEN spacing is resolved for a routed segment, THE Spacing_Harmonizer SHALL compute the distance between the element bounds edge and the segment midpoint along the heading axis.
4. WHEN spacing is applied, THE Spacing_Harmonizer SHALL adjust the target edge (obstacle boundary or segment point pair) to match the resolved spacing value along the heading axis.
5. WHEN the unified Spacing_Harmonizer replaces the duplicated functions, THE Elbow_Router SHALL produce identical routing results for all inputs.

### Requirement 3: Consolidate Geometry Helpers

**User Story:** As a developer, I want a single geometry module for elbow-related computations, so that overlapping concerns between `ElbowGeometry` and `ElbowPathUtils` are resolved.

#### Acceptance Criteria

1. THE Geometry_Helpers SHALL provide all axis-alignment, collinearity, heading detection, Manhattan distance, segment analysis, and corner extraction functions in a consolidated module.
2. WHEN functions from `ElbowGeometry` and `ElbowPathUtils` overlap in purpose (axis detection, segment direction analysis), THE Geometry_Helpers SHALL retain only one canonical implementation for each concern.
3. WHEN the consolidated Geometry_Helpers replace the original two classes, THE Elbow_Router and Elbow_Editor SHALL produce identical results for all inputs.

### Requirement 4: Reduce Routing Part-File Count

**User Story:** As a developer, I want fewer, more cohesive routing files, so that the routing subsystem is easier to navigate and maintain.

#### Acceptance Criteria

1. THE Elbow_Router SHALL organize its implementation into no more than three part files (down from five), grouping tightly coupled logic together.
2. WHEN part files are consolidated, THE Elbow_Router SHALL preserve all existing public API signatures (`routeElbowArrow`, `routeElbowArrowForElement`, `routeElbowArrowForElementPoints`, `ElbowRouteResult`, `ElbowRoutedPoints`).
3. WHEN part files are consolidated, THE Elbow_Router SHALL produce identical routing results for all inputs.

### Requirement 5: Reduce Editing Part-File Count

**User Story:** As a developer, I want fewer, more cohesive editing files, so that the editing subsystem is easier to navigate and maintain.

#### Acceptance Criteria

1. THE Elbow_Editor SHALL organize its implementation into no more than four part files (down from six), grouping tightly coupled logic together.
2. WHEN part files are consolidated, THE Elbow_Editor SHALL preserve all existing public API signatures (`computeElbowEdit`, `transformFixedSegments`, `ElbowEditResult`).
3. WHEN part files are consolidated, THE Elbow_Editor SHALL produce identical editing results for all inputs.

### Requirement 6: Simplify Obstacle Layout Planning

**User Story:** As a developer, I want the obstacle layout planning to use clearer, less deeply nested helper functions, so that the padding and overlap-splitting logic is easier to understand.

#### Acceptance Criteria

1. THE Obstacle_Layout builder SHALL use the unified Spacing_Harmonizer for all spacing computations instead of local duplicates.
2. THE Obstacle_Layout builder SHALL express the dynamic AABB computation as a sequence of named, focused steps rather than deeply nested helper calls.
3. WHEN the simplified Obstacle_Layout builder replaces the original, THE Elbow_Router SHALL produce identical routing results for all inputs.

### Requirement 7: Preserve All Existing Tests

**User Story:** As a developer, I want every existing elbow test to pass without modification after the refactoring, so that I have confidence no behavior has changed.

#### Acceptance Criteria

1. WHEN the refactoring is complete, THE Elbow_Router SHALL pass all existing routing tests without modification to test assertions.
2. WHEN the refactoring is complete, THE Elbow_Editor SHALL pass all existing editing tests without modification to test assertions.
3. IF a test file requires import path changes due to file moves, THEN the test file SHALL update only its import statements while keeping all assertions identical.

### Requirement 8: ElbowFixedSegment Serialization Round-Trip

**User Story:** As a developer, I want confidence that the ElbowFixedSegment JSON serialization remains correct after refactoring, so that persisted arrow data continues to load correctly.

#### Acceptance Criteria

1. FOR ALL valid ElbowFixedSegment objects, serializing to JSON via `toJson()` then deserializing via `fromJson()` SHALL produce an equivalent ElbowFixedSegment object (round-trip property).
2. WHEN an invalid JSON payload is provided to `fromJson()`, THE ElbowFixedSegment SHALL throw a `FormatException`.
