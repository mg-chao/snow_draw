import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test(
    'transformFixedSegments keeps world positions across center changes',
    () {
      const oldRect = DrawRect(minX: -50, minY: -50, maxX: 50, maxY: 50);
      const newRect = DrawRect(minX: -40, minY: -50, maxX: 60, maxY: 50);
      const rotation = math.pi / 2;

      final segments = <ElbowFixedSegment>[
        const ElbowFixedSegment(
          index: 2,
          start: DrawPoint(x: 0, y: 10),
          end: DrawPoint(x: 0, y: 20),
        ),
      ];

      final transformed = transformFixedSegments(
        segments: segments,
        oldRect: oldRect,
        newRect: newRect,
        rotation: rotation,
      );

      expect(transformed, isNotNull);
      expect(transformed!.length, 1);

      final start = transformed.first.start;
      final end = transformed.first.end;
      expect(start.x, closeTo(10, 1e-6));
      expect(start.y, closeTo(20, 1e-6));
      expect(end.x, closeTo(10, 1e-6));
      expect(end.y, closeTo(30, 1e-6));
    },
  );

  test('transformFixedSegments returns null for empty segments', () {
    const oldRect = DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100);
    const newRect = DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110);

    final transformed = transformFixedSegments(
      segments: const [],
      oldRect: oldRect,
      newRect: newRect,
      rotation: 0,
    );

    expect(transformed, isNull);
  });
}
