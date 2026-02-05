# Elbow Arrow Architectural Rewrite

## Overview

A greenfield rewrite of the orthogonal connector (elbow arrow) feature, implementing Manhattan routing with element binding, segment manipulation, and path stability from domain-first principles.

## Design Decisions

| Aspect | Decision |
|--------|----------|
| Segment model | Two states: free (auto-routed) or fixed (user-modified) |
| Binding protocol | Shape-agnostic `Bindable` interface |
| Anchor model | Edge + proportional position (0-1), snaps to midpoint |
| Obstacle avoidance | Bound elements only |
| Routing | Pure function, topology classification (0-3 bends) |
| Segment sliding | Perpendicular translation, inserts segments near endpoints |
| Topology transitions | Immediate snap to optimal |
| State representation | Segments with metadata, immutable value types |
| Edit pipeline | Sealed operation types, unified `applyOperation` |

## Core Domain Model

### ElbowSegment

The atomic unit of the path:

```dart
class ElbowSegment {
  final Point start;
  final Point end;
  final Axis axis;      // horizontal | vertical
  final bool isFixed;   // false = free, true = fixed (user-modified)
}
```

- **Free segments**: Can be recalculated during routing
- **Fixed segments**: Preserved during element movement; router works around them

### ElbowPath

An immutable sequence of connected segments:

```dart
class ElbowPath {
  final List<ElbowSegment> segments;

  Point get startPoint => segments.first.start;
  Point get endPoint => segments.last.end;
  List<Point> get vertices;  // All corner points
}
```

### ElbowAnchor

Normalized attachment point on an element edge:

```dart
class ElbowAnchor {
  final Edge edge;        // top | bottom | left | right
  final double position;  // 0.0 to 1.0 along edge (0.5 = midpoint)
}
```

### ElbowBinding

Connection to a bindable element:

```dart
class ElbowBinding {
  final String elementId;
  final ElbowAnchor anchor;
  final double gap;  // Spacing from element boundary
}
```

### ElbowArrow

The complete arrow state:

```dart
class ElbowArrow {
  final ElbowPath path;
  final ElbowBinding? startBinding;
  final ElbowBinding? endBinding;
  final ArrowStyle style;
}
```

## Bindable Protocol

Elements opt-in to being arrow-bindable by implementing:

```dart
abstract interface class Bindable {
  String get id;
  Rect get bounds;  // For obstacle avoidance

  /// Calculate world-space attachment point for an anchor
  Point resolveAnchor(ElbowAnchor anchor, double gap);

  /// Find nearest valid anchor from a world-space point
  ElbowAnchor? nearestAnchor(Point worldPoint, {double snapThreshold});

  /// Determine outbound heading when arrow exits from this anchor
  ElbowHeading exitHeading(ElbowAnchor anchor);
}
```

Each element type implements its own geometry:
- Rectangle: Projects onto 4 edges
- Circle: Maps edges to arc quadrants
- Polygon: Projects onto polygon edges

## Routing Algorithm

### Pure Function Signature

```dart
ElbowPath routeElbow({
  required Point start,
  required Point end,
  required ElbowHeading? startHeading,
  required ElbowHeading? endHeading,
  required List<Rect> obstacles,
  required List<ElbowSegment> fixedSegments,
});
```

### Topology Classification

| Scenario | Bends | Shape |
|----------|-------|-------|
| Aligned on same axis, clear path | 0 | Straight line |
| Adjacent quadrant, no obstruction | 1 | L-shape |
| Opposite sides, offset | 2 | S-shape or Z-shape |
| Complex obstruction or heading constraints | 3 | U-shape with detour |

### Routing Steps

1. **Classify topology** based on start/end positions and headings
2. **Generate candidate path** with calculated vertex positions
3. **Integrate fixed segments** by routing around them
4. **Validate & simplify**: Ensure axis-alignment, merge collinear, remove zero-length

## Segment Manipulation

### Perpendicular Sliding

```dart
ElbowPath slideSegment({
  required ElbowPath currentPath,
  required int segmentIndex,
  required double delta,  // Perpendicular offset
});
```

**Algorithm:**
1. Identify segment and determine perpendicular axis
2. Translate segment endpoints by delta
3. Adjust neighbor segments to maintain connectivity
4. If segment connects to arrow endpoint, insert new segment to keep endpoint fixed
5. Mark translated segment as fixed
6. Simplify path (merge collinear, remove zero-length)

## Edit Pipeline

### Operation Types

```dart
sealed class ElbowOperation {
  ElbowArrow apply(ElbowArrow arrow, BindableRegistry registry);
}

class MoveEndpoint extends ElbowOperation { ... }
class SlideSegment extends ElbowOperation { ... }
class ToggleSegmentFixed extends ElbowOperation { ... }
class BoundElementMoved extends ElbowOperation { ... }
```

### Invariants

Every operation guarantees:
- All segments remain axis-aligned
- Fixed segments preserve their axis and approximate position
- Path is continuous
- No zero-length or collinear adjacent segments

## File Structure

```
elbow/
├── model/
│   ├── elbow_segment.dart
│   ├── elbow_path.dart
│   ├── elbow_anchor.dart
│   ├── elbow_binding.dart
│   └── elbow_heading.dart
├── protocol/
│   ├── bindable.dart
│   └── bindable_registry.dart
├── routing/
│   ├── elbow_router.dart
│   ├── topology_classifier.dart
│   └── path_simplifier.dart
├── operations/
│   ├── elbow_operation.dart
│   ├── move_endpoint.dart
│   ├── slide_segment.dart
│   ├── toggle_fixed.dart
│   └── bound_element_moved.dart
└── elbow_arrow.dart
```

## Integration Points

**Reuse from existing codebase:**
- Element bounds/ID infrastructure
- Arrow style/rendering
- Hit testing framework
- Canvas coordinate transforms

**Replace:**
- Current elbow/ subdirectory (19 files)
- ArrowBinding → ElbowBinding with anchor model
- ElbowFixedSegment → ElbowSegment.isFixed

## Architectural Principles

1. **Pure geometric core**: All path calculations are pure functions
2. **Immutable state**: Operations return new instances
3. **Protocol-based binding**: Arrow system decoupled from element types
4. **Explicit over implicit**: Fixed segments explicitly marked
