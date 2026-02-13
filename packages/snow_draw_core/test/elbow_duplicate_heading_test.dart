import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_router.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/combined_element_lookup.dart';

import 'elbow_test_utils.dart';

/// Returns true when no two consecutive significant segments
/// share the same heading.
bool _hasNoDuplicateConsecutiveHeadings(List<DrawPoint> points) {
  ElbowHeading? previous;
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (ElbowGeometry.manhattanDistance(s, e) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    final heading = ElbowGeometry.headingForSegment(s, e);
    if (heading == previous) {
      return false;
    }
    previous = heading;
  }
  return true;
}

List<ElbowHeading> _headings(List<DrawPoint> points) {
  final result = <ElbowHeading>[];
  for (var i = 0; i < points.length - 1; i++) {
    final s = points[i];
    final e = points[i + 1];
    if (ElbowGeometry.manhattanDistance(s, e) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    result.add(ElbowGeometry.headingForSegment(s, e));
  }
  return result;
}

ElementState _arrowElement(
  List<DrawPoint> points, {
  List<ElbowFixedSegment>? fixedSegments,
}) {
  final rect = elbowRectForPoints(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  final data = ArrowData(
    points: normalized,
    arrowType: ArrowType.elbow,
    fixedSegments: fixedSegments,
  );
  return ElementState(
    id: 'arrow',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: data,
  );
}

void _expectNoDuplicateHeadings(
  ElbowEditResult result, {
  String? label,
}) {
  final headings = _headings(result.localPoints);
  expect(
    elbowPathIsOrthogonal(result.localPoints),
    isTrue,
    reason: '${label ?? ''} Path must be orthogonal.',
  );
  expect(
    _hasNoDuplicateConsecutiveHeadings(result.localPoints),
    isTrue,
    reason:
        '${label ?? ''} Path must not contain two '
        'consecutive segments with the same heading.\n'
        'Headings: $headings\n'
        'Points: ${result.localPoints}',
  );
}

void main() {
  group('mergeConsecutiveSameHeading unit tests', () {
    test('removes intermediate point between same-heading '
        'segments', () {
      // Two Right segments: should merge to just start+end.
      final dupPoints = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 0),
      ];
      final merged =
          ElbowGeometry.mergeConsecutiveSameHeading(dupPoints);
      expect(merged.length, 2);
      expect(merged.first, dupPoints.first);
      expect(merged.last, dupPoints.last);
    });

    test('preserves pinned points', () {
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 0),
      ];
      final pinned = {points[1]};
      final merged = ElbowGeometry.mergeConsecutiveSameHeading(
        points,
        pinned: pinned,
      );
      expect(merged.length, 3);
    });

    test('handles non-collinear same-heading segments', () {
      // Right at y=0, then Right at y=50 — same heading,
      // different axis values.
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 50),
      ];
      // (0,0)->(100,0) = Right
      // (100,0)->(200,50) = diagonal, heading = Right
      // mergeConsecutiveSameHeading should remove (100,0).
      final merged =
          ElbowGeometry.mergeConsecutiveSameHeading(points);
      expect(merged.length, 2);
    });

    test('no-op for alternating headings', () {
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 100, y: 100),
        const DrawPoint(x: 200, y: 100),
      ];
      final merged =
          ElbowGeometry.mergeConsecutiveSameHeading(points);
      expect(merged.length, 4);
    });

    test('chains multiple same-heading merges', () {
      // Right, Right, Right — three consecutive.
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 50, y: 0),
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 0),
      ];
      final merged =
          ElbowGeometry.mergeConsecutiveSameHeading(points);
      expect(merged.length, 2);
    });
  });

  group('fixed-down binding no duplicate headings', () {
    // The original bug scenario: path [Right, Down(fixed), Right]
    // with end bound to the right side of a rectangle.
    const bindingRect = DrawRect(
      minX: 80,
      minY: 160,
      maxX: 200,
      maxY: 240,
    );

    for (final fixedY in [80.0, 120.0, 150.0]) {
      for (final lastX in [140.0, 180.0, 210.0, 250.0, 300.0]) {
        for (final anchorY in [0.1, 0.2, 0.3, 0.5, 0.8]) {
          test(
            'fixedY=$fixedY lastX=$lastX anchorY=$anchorY',
            () {
              final points = <DrawPoint>[
                DrawPoint.zero,
                const DrawPoint(x: 120, y: 0),
                DrawPoint(x: 120, y: fixedY),
                DrawPoint(x: lastX, y: fixedY),
              ];
              final fixedSegments = <ElbowFixedSegment>[
                ElbowFixedSegment(
                  index: 2,
                  start: points[1],
                  end: points[2],
                ),
              ];
              final element = _arrowElement(
                points,
                fixedSegments: fixedSegments,
              );
              final data = element.data as ArrowData;

              final boundElement = elbowRectangleElement(
                id: 'rect-1',
                rect: bindingRect,
              );
              final binding = ArrowBinding(
                elementId: 'rect-1',
                anchor: DrawPoint(x: 1, y: anchorY),
              );
              final boundPoint =
                  ArrowBindingUtils.resolveElbowBoundPoint(
                    binding: binding,
                    target: boundElement,
                    hasArrowhead:
                        data.endArrowhead !=
                        ArrowheadStyle.none,
                  ) ??
                  points.last;

              final movedPoints =
                  List<DrawPoint>.from(points);
              movedPoints[movedPoints.length - 1] =
                  boundPoint;

              final result = computeElbowEdit(
                element: element,
                data: data.copyWith(endBinding: binding),
                lookup: CombinedElementLookup(
                  base: {'rect-1': boundElement},
                ),
                localPointsOverride: movedPoints,
                fixedSegmentsOverride: fixedSegments,
                endBindingOverride: binding,
              );

              _expectNoDuplicateHeadings(
                result,
                label:
                    'fixedY=$fixedY lastX=$lastX '
                    'anchorY=$anchorY',
              );
            },
          );
        }
      }
    }
  });

  group('all binding sides no duplicate headings', () {
    // Test binding to all four sides of a rectangle.
    const rect = DrawRect(
      minX: 100,
      minY: 100,
      maxX: 250,
      maxY: 200,
    );

    final anchors = <String, DrawPoint>{
      'right-top': const DrawPoint(x: 1, y: 0.2),
      'right-mid': const DrawPoint(x: 1, y: 0.5),
      'right-bot': const DrawPoint(x: 1, y: 0.8),
      'bottom-left': const DrawPoint(x: 0.2, y: 1),
      'bottom-mid': const DrawPoint(x: 0.5, y: 1),
      'bottom-right': const DrawPoint(x: 0.8, y: 1),
      'left-top': const DrawPoint(x: 0, y: 0.2),
      'left-mid': const DrawPoint(x: 0, y: 0.5),
      'left-bot': const DrawPoint(x: 0, y: 0.8),
      'top-left': const DrawPoint(x: 0.2, y: 0),
      'top-mid': const DrawPoint(x: 0.5, y: 0),
      'top-right': const DrawPoint(x: 0.8, y: 0),
    };

    for (final entry in anchors.entries) {
      test('anchor=${entry.key}', () {
        final points = <DrawPoint>[
          DrawPoint.zero,
          const DrawPoint(x: 120, y: 0),
          const DrawPoint(x: 120, y: 80),
          const DrawPoint(x: 240, y: 80),
        ];
        final fixedSegments = <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 2,
            start: points[1],
            end: points[2],
          ),
        ];
        final element = _arrowElement(
          points,
          fixedSegments: fixedSegments,
        );
        final data = element.data as ArrowData;

        final boundElement = elbowRectangleElement(
          id: 'rect-1',
          rect: rect,
        );
        final binding = ArrowBinding(
          elementId: 'rect-1',
          anchor: entry.value,
        );
        final boundPoint =
            ArrowBindingUtils.resolveElbowBoundPoint(
              binding: binding,
              target: boundElement,
              hasArrowhead:
                  data.endArrowhead !=
                  ArrowheadStyle.none,
            ) ??
            points.last;

        final movedPoints = List<DrawPoint>.from(points);
        movedPoints[movedPoints.length - 1] = boundPoint;

        final result = computeElbowEdit(
          element: element,
          data: data.copyWith(endBinding: binding),
          lookup: CombinedElementLookup(
            base: {'rect-1': boundElement},
          ),
          localPointsOverride: movedPoints,
          fixedSegmentsOverride: fixedSegments,
          endBindingOverride: binding,
        );

        _expectNoDuplicateHeadings(
          result,
          label: 'anchor=${entry.key}',
        );
      });
    }
  });
}
