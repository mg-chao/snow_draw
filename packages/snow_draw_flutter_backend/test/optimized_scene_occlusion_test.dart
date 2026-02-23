import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';

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

    test('treats two-point free-draw strokes as line occluders', () {
      const seedAabb = DrawRect(minX: 10, minY: 20, maxX: 70, maxY: 60);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'free_line',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FreeDrawData(strokeWidth: 8),
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

    test('splits long diagonal lines into segmented query rects', () {
      const seedAabb = DrawRect(maxX: 1000, maxY: 1000);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'line',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: LineData(strokeWidth: 4),
        ),
        seedAabb: seedAabb,
        maxLineQueryRects: 6,
        lineTargetSegmentLength: 200,
      );

      expect(rects, hasLength(6));
      for (final rect in rects) {
        expect(rect.width, lessThan(seedAabb.width));
        expect(rect.height, lessThan(seedAabb.height));
      }
    });

    test('falls back to seed aabb when query-rect budget is exhausted', () {
      const seedAabb = DrawRect(maxX: 1000, maxY: 1000);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'line',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: LineData(strokeWidth: 4),
        ),
        seedAabb: seedAabb,
        maxLineQueryRects: 0,
      );

      expect(rects, [seedAabb]);
    });

    test('normalizes non-finite line planner tuning values', () {
      const seedAabb = DrawRect(maxX: 1000, maxY: 1000);
      final rects = resolveOptimizedOccluderQueryRects(
        seedElement: const ElementState(
          id: 'line',
          rect: seedAabb,
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: LineData(strokeWidth: 4),
        ),
        seedAabb: seedAabb,
        maxLineQueryRects: 6,
        linePaddingFloor: double.nan,
        linePaddingStrokeFactor: double.nan,
        lineTargetSegmentLength: double.nan,
      );

      expect(rects, hasLength(6));
      for (final rect in rects) {
        expect(rect.minX.isFinite, isTrue);
        expect(rect.minY.isFinite, isTrue);
        expect(rect.maxX.isFinite, isTrue);
        expect(rect.maxY.isFinite, isTrue);
      }
    });
  });
}
