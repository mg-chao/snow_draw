import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_constants.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_heading.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/combined_element_lookup.dart';
import 'package:test/test.dart';

import 'elbow_test_utils.dart';

List<ElbowHeading> _significantHeadings(List<DrawPoint> points) {
  final headings = <ElbowHeading>[];
  for (var i = 0; i < points.length - 1; i++) {
    final start = points[i];
    final end = points[i + 1];
    if (ElbowGeometry.manhattanDistance(start, end) <=
        ElbowConstants.dedupThreshold) {
      continue;
    }
    headings.add(ElbowGeometry.headingForSegment(start, end));
  }
  return headings;
}

bool _hasDuplicateConsecutiveHeadings(List<ElbowHeading> headings) {
  for (var i = 1; i < headings.length; i++) {
    if (headings[i] == headings[i - 1]) {
      return true;
    }
  }
  return false;
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

DrawPoint _resolveBoundPoint({
  required ArrowBinding binding,
  required ElementState target,
  required ArrowData data,
}) {
  final boundPoint = ArrowBindingUtils.resolveElbowBoundPoint(
    binding: binding,
    target: target,
    hasArrowhead: data.endArrowhead != ArrowheadStyle.none,
  );
  expect(boundPoint, isNotNull);
  return boundPoint!;
}

ElbowEditResult _computeBoundEndEdit({
  required List<DrawPoint> points,
  required List<ElbowFixedSegment> fixedSegments,
  required ArrowBinding binding,
  required ElementState boundElement,
}) {
  final element = _arrowElement(points, fixedSegments: fixedSegments);
  final data = element.data as ArrowData;
  final movedPoints = List<DrawPoint>.from(points)
    ..[points.length - 1] = _resolveBoundPoint(
      binding: binding,
      target: boundElement,
      data: data,
    );

  return computeElbowEdit(
    element: element,
    data: data.copyWith(endBinding: binding),
    lookup: CombinedElementLookup(base: {boundElement.id: boundElement}),
    localPointsOverride: movedPoints,
    fixedSegmentsOverride: fixedSegments,
    endBindingOverride: binding,
  );
}

void _expectNoDuplicateHeadings(ElbowEditResult result, {String? label}) {
  final headings = _significantHeadings(result.localPoints);
  expect(
    elbowPathIsOrthogonal(result.localPoints),
    isTrue,
    reason: '${label ?? ''} Path must be orthogonal.',
  );
  expect(
    _hasDuplicateConsecutiveHeadings(headings),
    isFalse,
    reason:
        '${label ?? ''} Path must not contain two '
        'consecutive segments with the same heading.\n'
        'Headings: $headings\n'
        'Points: ${result.localPoints}',
  );
}

void main() {
  group('mergeConsecutiveSameHeading unit tests', () {
    test('removes intermediate point between same-heading segments', () {
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 0),
      ];

      final merged = ElbowGeometry.mergeConsecutiveSameHeading(points);

      expect(merged.length, 2);
      expect(merged.first, points.first);
      expect(merged.last, points.last);
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
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 50),
      ];

      final merged = ElbowGeometry.mergeConsecutiveSameHeading(points);

      expect(merged.length, 2);
    });

    test('no-op for alternating headings', () {
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 100, y: 100),
        const DrawPoint(x: 200, y: 100),
      ];

      final merged = ElbowGeometry.mergeConsecutiveSameHeading(points);

      expect(merged.length, 4);
    });

    test('chains multiple same-heading merges', () {
      final points = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 50, y: 0),
        const DrawPoint(x: 100, y: 0),
        const DrawPoint(x: 200, y: 0),
      ];

      final merged = ElbowGeometry.mergeConsecutiveSameHeading(points);

      expect(merged.length, 2);
    });
  });

  group('fixed-down binding no duplicate headings', () {
    const bindingRect = DrawRect(minX: 80, minY: 160, maxX: 200, maxY: 240);

    for (final fixedY in [80.0, 120.0, 150.0]) {
      for (final lastX in [140.0, 180.0, 210.0, 250.0, 300.0]) {
        for (final anchorY in [0.1, 0.2, 0.3, 0.5, 0.8]) {
          test('fixedY=$fixedY lastX=$lastX anchorY=$anchorY', () {
            final points = <DrawPoint>[
              DrawPoint.zero,
              const DrawPoint(x: 120, y: 0),
              DrawPoint(x: 120, y: fixedY),
              DrawPoint(x: lastX, y: fixedY),
            ];
            final fixedSegments = <ElbowFixedSegment>[
              ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
            ];
            final boundElement = elbowRectangleElement(
              id: 'rect-1',
              rect: bindingRect,
            );
            final binding = ArrowBinding(
              elementId: 'rect-1',
              anchor: DrawPoint(x: 1, y: anchorY),
            );

            final result = _computeBoundEndEdit(
              points: points,
              fixedSegments: fixedSegments,
              binding: binding,
              boundElement: boundElement,
            );

            _expectNoDuplicateHeadings(
              result,
              label: 'fixedY=$fixedY lastX=$lastX anchorY=$anchorY',
            );
          });
        }
      }
    }
  });

  group('all binding sides no duplicate headings', () {
    const rect = DrawRect(minX: 100, minY: 100, maxX: 250, maxY: 200);
    const anchors = <String, DrawPoint>{
      'right-top': DrawPoint(x: 1, y: 0.2),
      'right-mid': DrawPoint(x: 1, y: 0.5),
      'right-bot': DrawPoint(x: 1, y: 0.8),
      'bottom-left': DrawPoint(x: 0.2, y: 1),
      'bottom-mid': DrawPoint(x: 0.5, y: 1),
      'bottom-right': DrawPoint(x: 0.8, y: 1),
      'left-top': DrawPoint(x: 0, y: 0.2),
      'left-mid': DrawPoint(x: 0, y: 0.5),
      'left-bot': DrawPoint(x: 0, y: 0.8),
      'top-left': DrawPoint(x: 0.2, y: 0),
      'top-mid': DrawPoint(x: 0.5, y: 0),
      'top-right': DrawPoint(x: 0.8, y: 0),
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
          ElbowFixedSegment(index: 2, start: points[1], end: points[2]),
        ];
        final boundElement = elbowRectangleElement(id: 'rect-1', rect: rect);
        final binding = ArrowBinding(elementId: 'rect-1', anchor: entry.value);

        final result = _computeBoundEndEdit(
          points: points,
          fixedSegments: fixedSegments,
          binding: binding,
          boundElement: boundElement,
        );

        _expectNoDuplicateHeadings(result, label: 'anchor=${entry.key}');
      });
    }
  });
}
