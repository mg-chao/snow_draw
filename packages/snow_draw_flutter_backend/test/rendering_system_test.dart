import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/free_draw/free_draw_path_utils.dart';
import 'package:snow_draw_flutter_backend/render/free_draw/free_draw_visual_cache.dart';
import 'package:snow_draw_flutter_backend/render/patterns/stroke_pattern_utils.dart';

void main() {
  group('LruCache', () {
    test('getOrCreate returns existing value on cache hit', () {
      final cache = LruCache<String, int>(maxEntries: 4)..put('a', 1);
      var builderCalled = false;
      final result = cache.getOrCreate('a', () {
        builderCalled = true;
        return 99;
      });
      expect(result, 1);
      expect(builderCalled, isFalse);
    });

    test('getOrCreate calls builder on cache miss', () {
      final cache = LruCache<String, int>(maxEntries: 4);
      var builderCalled = false;
      final result = cache.getOrCreate('a', () {
        builderCalled = true;
        return 42;
      });
      expect(result, 42);
      expect(builderCalled, isTrue);
    });

    test('evicts least recently used entry', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 2, onEvict: evicted.add)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      expect(evicted, [1]);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });

    test('get promotes entry to front', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 2, onEvict: evicted.add)
        ..put('a', 1)
        ..put('b', 2)
        ..get('a')
        ..put('c', 3);
      // Access 'a' to promote it.
      // Insert 'c' - should evict 'b' (now LRU).
      expect(evicted, [2]);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull);
    });

    test('put replaces value and calls onEvict for old value', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', 1)
        ..put('a', 2);
      expect(evicted, [1]);
      expect(cache.get('a'), 2);
    });

    test('clear calls onEvict for all entries', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3)
        ..clear();
      expect(evicted, containsAll([1, 2, 3]));
      expect(cache.length, 0);
    });

    test('remove calls onEvict', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', 1)
        ..remove('a');
      expect(evicted, [1]);
      expect(cache.length, 0);
    });

    test('remove returns false for missing key', () {
      final cache = LruCache<String, int>(maxEntries: 4);
      expect(cache.remove('missing'), isFalse);
    });
  });

  group('buildLineFillPaint', () {
    setUp(clearStrokePatternCaches);

    test('returns paint with correct style', () {
      final paint = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0,
        color: const Color(0xFFFF0000),
      );
      expect(paint.style, PaintingStyle.fill);
      expect(paint.shader, isNotNull);
      expect(paint.colorFilter, isNotNull);
      expect(paint.isAntiAlias, isTrue);
    });

    test('caches shader for identical parameters', () {
      final paint1 = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0,
        color: const Color(0xFFFF0000),
      );
      final paint2 = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0,
        color: const Color(0xFF00FF00),
      );
      expect(identical(paint1.shader, paint2.shader), isTrue);
    });

    test('different spacing produces different shader', () {
      final paint1 = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0,
        color: const Color(0xFFFF0000),
      );
      final paint2 = buildLineFillPaint(
        spacing: 12,
        lineWidth: 1.5,
        angle: 0,
        color: const Color(0xFFFF0000),
      );
      expect(identical(paint1.shader, paint2.shader), isFalse);
    });
  });

  group('buildDotPositions', () {
    test('returns empty for empty path', () {
      final result = buildDotPositions(Path(), 5);
      expect(result.length, 0);
    });

    test('produces correct count for straight line', () {
      final base = Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0);
      final positions = buildDotPositions(base, 10);
      // 100 / 10 = 10 intervals -> 11 dots, each 2 floats.
      expect(positions.length, greaterThanOrEqualTo(20));
      expect(positions.length.isEven, isTrue);
    });

    test('positions are along the path', () {
      final base = Path()
        ..moveTo(0, 0)
        ..lineTo(50, 0);
      final positions = buildDotPositions(base, 10);
      for (var i = 1; i < positions.length; i += 2) {
        expect(positions[i], closeTo(0, 0.1));
      }
    });
  });

  group('FreeDrawVisualCache', () {
    ElementState makeElement({
      required String id,
      required List<DrawPoint> points,
      double width = 100,
      double height = 100,
    }) => ElementState(
      id: id,
      rect: DrawRect(maxX: width, maxY: height),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: FreeDrawData(points: points),
    );

    test('resolve returns same entry for identical element', () {
      final element = makeElement(
        id: 'e1',
        points: const [
          DrawPoint.zero,
          DrawPoint(x: 0.5, y: 0.5),
          DrawPoint(x: 1, y: 1),
        ],
      );
      final cache = FreeDrawVisualCache.instance;
      final entry1 = cache.resolve(
        element: element,
        data: element.data as FreeDrawData,
      );
      final entry2 = cache.resolve(
        element: element,
        data: element.data as FreeDrawData,
      );
      expect(identical(entry1, entry2), isTrue);
    });

    test('resolve rebuilds entry when size changes', () {
      final element1 = makeElement(
        id: 'e2',
        points: const [
          DrawPoint.zero,
          DrawPoint(x: 0.5, y: 0.5),
          DrawPoint(x: 1, y: 1),
        ],
      );
      final element2 = element1.copyWith(
        rect: const DrawRect(maxX: 200, maxY: 200),
      );
      final cache = FreeDrawVisualCache.instance;
      final entry1 = cache.resolve(
        element: element1,
        data: element1.data as FreeDrawData,
      );
      final entry2 = cache.resolve(
        element: element2,
        data: element2.data as FreeDrawData,
      );
      expect(identical(entry1, entry2), isFalse);
    });
  });

  group('FreeDrawVisualEntry', () {
    test('matches returns true for identical data and dimensions', () {
      const data = FreeDrawData();
      final entry = FreeDrawVisualEntry(
        data: data,
        width: 100,
        height: 100,
        pointCount: 2,
        path: Path(),
      );
      expect(entry.matches(data, 100, 100), isTrue);
    });

    test('matches returns false for different dimensions', () {
      const data = FreeDrawData();
      final entry = FreeDrawVisualEntry(
        data: data,
        width: 100,
        height: 100,
        pointCount: 2,
        path: Path(),
      );
      expect(entry.matches(data, 200, 100), isFalse);
    });
  });

  group('buildFreeDrawSmoothPath', () {
    test('returns empty path for fewer than 2 points', () {
      final path = buildFreeDrawSmoothPath([]);
      expect(path.computeMetrics().isEmpty, isTrue);

      final path1 = buildFreeDrawSmoothPath([Offset.zero]);
      expect(path1.computeMetrics().isEmpty, isTrue);
    });

    test('returns straight line for exactly 2 points', () {
      final path = buildFreeDrawSmoothPath([Offset.zero, const Offset(100, 0)]);
      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.length, closeTo(100, 0.1));
    });

    test('returns smooth path for 3+ points', () {
      final path = buildFreeDrawSmoothPath([
        Offset.zero,
        const Offset(50, 50),
        const Offset(100, 0),
      ]);
      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.length, greaterThan(100));
    });

    test('handles closed path (first == last)', () {
      final path = buildFreeDrawSmoothPath([
        Offset.zero,
        const Offset(50, 50),
        const Offset(100, 0),
        Offset.zero,
      ]);
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty);
    });
  });

  group('resolveFreeDrawLocalPoints', () {
    test('returns empty for empty points', () {
      final result = resolveFreeDrawLocalPoints(
        rect: const DrawRect(maxX: 100, maxY: 100),
        points: const [],
      );
      expect(result, isEmpty);
    });

    test('scales normalized points to rect dimensions', () {
      final result = resolveFreeDrawLocalPoints(
        rect: const DrawRect(maxX: 200, maxY: 100),
        points: const [DrawPoint(x: 0.5, y: 0.5), DrawPoint(x: 1, y: 1)],
      );
      expect(result.length, 2);
      expect(result[0].dx, closeTo(100, 0.01));
      expect(result[0].dy, closeTo(50, 0.01));
      expect(result[1].dx, closeTo(200, 0.01));
      expect(result[1].dy, closeTo(100, 0.01));
    });
  });

  group('LineShaderKey', () {
    test('quantizes values', () {
      final key = LineShaderKey(spacing: 5.123, lineWidth: 2.789, angle: 0.5);
      expect(key.spacing, 5.1);
      expect(key.lineWidth, 2.8);
      expect(key.angle, 0.5);
    });

    test('equal keys match', () {
      final a = LineShaderKey(spacing: 5, lineWidth: 2, angle: 0);
      final b = LineShaderKey(spacing: 5, lineWidth: 2, angle: 0);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different keys do not match', () {
      final a = LineShaderKey(spacing: 5, lineWidth: 2, angle: 0);
      final b = LineShaderKey(spacing: 5, lineWidth: 3, angle: 0);
      expect(a, isNot(equals(b)));
    });
  });
}
