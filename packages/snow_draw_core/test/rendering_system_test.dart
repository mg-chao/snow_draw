import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_path_utils.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_visual_cache.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';
import 'package:snow_draw_core/draw/utils/stroke_pattern_utils.dart';

void main() {
  group('LruCache', () {
    test('getOrCreate returns existing value on cache hit', () {
      final cache = LruCache<String, int>(maxEntries: 4);
      cache.put('a', 1);
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
      final cache = LruCache<String, int>(
        maxEntries: 2,
        onEvict: evicted.add,
      );
      cache.put('a', 1);
      cache.put('b', 2);
      cache.put('c', 3);
      expect(evicted, [1]);
      expect(cache.get('a'), isNull);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
    });

    test('get promotes entry to front', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(
        maxEntries: 2,
        onEvict: evicted.add,
      );
      cache.put('a', 1);
      cache.put('b', 2);
      // Access 'a' to promote it.
      cache.get('a');
      // Insert 'c' — should evict 'b' (now LRU).
      cache.put('c', 3);
      expect(evicted, [2]);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), isNull);
    });

    test('put replaces value and calls onEvict for old value', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(
        maxEntries: 4,
        onEvict: evicted.add,
      );
      cache.put('a', 1);
      cache.put('a', 2);
      expect(evicted, [1]);
      expect(cache.get('a'), 2);
    });

    test('clear calls onEvict for all entries', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(
        maxEntries: 4,
        onEvict: evicted.add,
      );
      cache
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3)
        ..clear();
      expect(evicted, containsAll([1, 2, 3]));
      expect(cache.length, 0);
    });

    test('remove calls onEvict', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(
        maxEntries: 4,
        onEvict: evicted.add,
      );
      cache.put('a', 1);
      cache.remove('a');
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
      // 100 / 10 = 10 intervals → 11 dots, each 2 floats.
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
    ElementState _makeElement({
      required String id,
      required List<DrawPoint> points,
      double width = 100,
      double height = 100,
    }) {
      return ElementState(
        id: id,
        rect: DrawRect(minX: 0, minY: 0, maxX: width, maxY: height),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FreeDrawData(
          points: points,
          strokeWidth: 2,
        ),
      );
    }

    test('resolve returns same entry for identical element', () {
      final element = _makeElement(
        id: 'e1',
        points: const [
          DrawPoint(x: 0, y: 0),
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
      final element1 = _makeElement(
        id: 'e2',
        points: const [
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 0.5, y: 0.5),
          DrawPoint(x: 1, y: 1),
        ],
        width: 100,
        height: 100,
      );
      final element2 = element1.copyWith(
        rect: const DrawRect(
          minX: 0,
          minY: 0,
          maxX: 200,
          maxY: 200,
        ),
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
    test('getCachedPicture returns null when no picture cached', () {
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(),
        width: 100,
        height: 100,
        pointCount: 3,
        path: Path(),
        strokePath: null,
      );
      expect(entry.getCachedPicture(1.0), isNull);
    });

    test('getCachedPicture returns picture for matching opacity', () {
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(),
        width: 100,
        height: 100,
        pointCount: 3,
        path: Path(),
        strokePath: null,
      );
      final recorder = PictureRecorder();
      Canvas(recorder);
      final picture = recorder.endRecording();
      entry.setCachedPicture(picture, 1.0);
      expect(entry.getCachedPicture(1.0), isNotNull);
      expect(entry.getCachedPicture(0.5), isNull);
      entry.dispose();
    });

    test('setCachedPicture disposes previous picture', () {
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(),
        width: 100,
        height: 100,
        pointCount: 3,
        path: Path(),
        strokePath: null,
      );
      final recorder1 = PictureRecorder();
      Canvas(recorder1);
      final picture1 = recorder1.endRecording();
      entry.setCachedPicture(picture1, 1.0);

      final recorder2 = PictureRecorder();
      Canvas(recorder2);
      final picture2 = recorder2.endRecording();
      entry.setCachedPicture(picture2, 1.0);

      // The entry should hold picture2 now.
      expect(entry.getCachedPicture(1.0), same(picture2));
      entry.dispose();
    });

    test('getOrBuildFlattened caches result', () {
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(50, 50);
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(),
        width: 100,
        height: 100,
        pointCount: 3,
        path: path,
        strokePath: null,
      );
      final flat1 = entry.getOrBuildFlattened(2);
      final flat2 = entry.getOrBuildFlattened(2);
      expect(identical(flat1, flat2), isTrue);
    });

    test('getOrBuildClosedFillPath caches result', () {
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(50, 50)
        ..lineTo(50, 0);
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(),
        width: 100,
        height: 100,
        pointCount: 3,
        path: path,
        strokePath: null,
      );
      final closed1 = entry.getOrBuildClosedFillPath();
      final closed2 = entry.getOrBuildClosedFillPath();
      expect(identical(closed1, closed2), isTrue);
    });

    test('matches returns true for identical data and dimensions', () {
      const data = FreeDrawData();
      final entry = FreeDrawVisualEntry(
        data: data,
        width: 100,
        height: 100,
        pointCount: 2,
        path: Path(),
        strokePath: null,
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
        strokePath: null,
      );
      expect(entry.matches(data, 200, 100), isFalse);
    });
  });

  group('buildFreeDrawSmoothPath', () {
    test('returns empty path for fewer than 2 points', () {
      final path = buildFreeDrawSmoothPath([]);
      expect(path.computeMetrics().isEmpty, isTrue);

      final path1 = buildFreeDrawSmoothPath([const Offset(0, 0)]);
      expect(path1.computeMetrics().isEmpty, isTrue);
    });

    test('returns straight line for exactly 2 points', () {
      final path = buildFreeDrawSmoothPath([
        const Offset(0, 0),
        const Offset(100, 0),
      ]);
      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.length, closeTo(100, 0.1));
    });

    test('returns smooth path for 3+ points', () {
      final path = buildFreeDrawSmoothPath([
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(100, 0),
      ]);
      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.length, greaterThan(100));
    });

    test('handles closed path (first == last)', () {
      final path = buildFreeDrawSmoothPath([
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(100, 0),
        const Offset(0, 0),
      ]);
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty);
    });
  });

  group('buildFreeDrawSmoothPathIncremental', () {
    test('returns null for too few points', () {
      final result = buildFreeDrawSmoothPathIncremental(
        allPoints: [const Offset(0, 0)],
        basePath: Path(),
        basePointCount: 0,
      );
      expect(result, isNull);
    });

    test('returns path when extending existing path', () {
      final points = [
        const Offset(0, 0),
        const Offset(25, 25),
        const Offset(50, 50),
        const Offset(75, 25),
      ];
      final basePath = buildFreeDrawSmoothPath(points.sublist(0, 3));
      final result = buildFreeDrawSmoothPathIncremental(
        allPoints: points,
        basePath: basePath,
        basePointCount: 3,
      );
      // May return null if incremental build isn't possible,
      // but should not throw.
      if (result != null) {
        final metrics = result.computeMetrics().toList();
        expect(metrics, isNotEmpty);
      }
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
        points: const [
          DrawPoint(x: 0.5, y: 0.5),
          DrawPoint(x: 1, y: 1),
        ],
      );
      expect(result.length, 2);
      expect(result[0].dx, closeTo(100, 0.01));
      expect(result[0].dy, closeTo(50, 0.01));
      expect(result[1].dx, closeTo(200, 0.01));
      expect(result[1].dy, closeTo(100, 0.01));
    });
  });

  group('resolveFreeDrawPressures', () {
    test('returns empty for empty points', () {
      final result = resolveFreeDrawPressures(points: const []);
      expect(result, isEmpty);
    });

    test('returns 0.5 for all when no pressure data', () {
      final result = resolveFreeDrawPressures(
        points: const [
          DrawPoint(x: 0, y: 0),
          DrawPoint(x: 1, y: 1),
        ],
      );
      expect(result, [0.5, 0.5]);
    });

    test('returns actual pressure when available', () {
      final result = resolveFreeDrawPressures(
        points: const [
          DrawPoint(x: 0, y: 0, pressure: 0.8),
          DrawPoint(x: 1, y: 1),
        ],
      );
      expect(result[0], closeTo(0.8, 0.01));
      expect(result[1], 0.5);
    });
  });

  group('LineShaderKey', () {
    test('quantizes values', () {
      final key = LineShaderKey(
        spacing: 5.123,
        lineWidth: 2.789,
        angle: 0.5,
      );
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

  group('flattenPath precision', () {
    test('short path does not over-allocate', () {
      // A short straight line should produce a small number of
      // points, not be clamped to an arbitrary minimum.
      final path = Path()
        ..moveTo(0, 0)
        ..lineTo(10, 0);
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(strokeWidth: 2),
        width: 100,
        height: 100,
        pointCount: 2,
        path: path,
        strokePath: null,
      );
      final flattened = entry.getOrBuildFlattened(2);
      // With step = max(2, 2*2) = 4, a 10px line should produce
      // ~3-4 points, not 512.
      expect(flattened.length, lessThan(10));
      expect(flattened.length, greaterThanOrEqualTo(2));
    });

    test('long complex path produces enough points', () {
      // A longer path should produce proportionally more points.
      final path = Path()..moveTo(0, 0);
      for (var i = 1; i <= 100; i++) {
        path.lineTo(i * 10.0, (i % 2 == 0) ? 0 : 50);
      }
      final entry = FreeDrawVisualEntry(
        data: const FreeDrawData(strokeWidth: 2),
        width: 1000,
        height: 50,
        pointCount: 101,
        path: path,
        strokePath: null,
      );
      final flattened = entry.getOrBuildFlattened(2);
      // Should have a reasonable number of points for hit testing.
      expect(flattened.length, greaterThan(50));
    });
  });
}
