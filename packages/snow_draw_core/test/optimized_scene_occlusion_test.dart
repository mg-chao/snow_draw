import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/optimized_scene_occlusion.dart';

void main() {
  group('resolveOptimizedOccluderQueryRects', () {
    test('falls back to seed aabb for non-line elements', () {
      const seedAabb = DrawRect(minX: 10, minY: 20, maxX: 30, maxY: 40);
      final rect = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'rect',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        seedAabb: seedAabb,
      );

      expect(rect, [seedAabb]);
    });

    test('returns padded query rect for two-point line segments', () {
      const seedAabb = DrawRect(minX: 10, minY: 20, maxX: 70, maxY: 60);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'line',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: LineData(strokeWidth: 8),
        ),
        seedAabb: seedAabb,
      );

      expect(rects, hasLength(1));
      final query = rects.single;
      expect(query.minX, equals(4));
      expect(query.minY, equals(14));
      expect(query.maxX, equals(76));
      expect(query.maxY, equals(66));
    });

    test('applies element rotation before creating query rects', () {
      const seedAabb = DrawRect(maxX: 10, maxY: 10);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'line',
          rect: seedAabb,
          rotation: math.pi / 2,
          opacity: 1,
          zIndex: 1,
          data: LineData(),
        ),
        seedAabb: seedAabb,
      );

      expect(rects, hasLength(1));
      final query = rects.single;
      expect(query.minX, closeTo(-3, 1e-9));
      expect(query.minY, closeTo(-3, 1e-9));
      expect(query.maxX, closeTo(13, 1e-9));
      expect(query.maxY, closeTo(13, 1e-9));
    });

    test('falls back to seed aabb for multi-point lines', () {
      const seedAabb = DrawRect(maxX: 100, maxY: 100);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'line',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: LineData(
            points: [
              DrawPoint.zero,
              DrawPoint(x: 0.5, y: 1),
              DrawPoint(x: 1, y: 0),
            ],
          ),
        ),
        seedAabb: seedAabb,
      );

      expect(rects, [seedAabb]);
    });
  });
}
