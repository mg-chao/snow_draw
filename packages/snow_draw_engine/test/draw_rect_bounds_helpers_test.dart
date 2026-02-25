import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('DrawRect.fromPointCloud', () {
    test('returns zero rect for empty points', () {
      expect(DrawRect.fromPointCloud(const <DrawPoint>[]), const DrawRect());
    });

    test('resolves min and max bounds across points', () {
      final rect = DrawRect.fromPointCloud(const <DrawPoint>[
        DrawPoint(x: 10, y: 5),
        DrawPoint(x: -2, y: 20),
        DrawPoint(x: 7, y: -4),
      ]);

      expect(rect, const DrawRect(minX: -2, minY: -4, maxX: 10, maxY: 20));
    });
  });

  group('DrawRect expansion', () {
    test('expandToInclude grows bounds to include a single point', () {
      const rect = DrawRect(minX: 1, minY: 2, maxX: 3, maxY: 4);
      final expanded = rect.expandToInclude(const DrawPoint(x: -5, y: 6));

      expect(expanded, const DrawRect(minX: -5, minY: 2, maxX: 3, maxY: 6));
    });

    test('expandToIncludeAll preserves rect when no points are provided', () {
      const rect = DrawRect(minX: 1, minY: 2, maxX: 3, maxY: 4);

      expect(rect.expandToIncludeAll(const <DrawPoint>[]), rect);
    });
  });
}
