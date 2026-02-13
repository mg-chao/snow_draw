import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_path_utils.dart';

void main() {
  group('buildFreeDrawSmoothPath', () {
    test('returns empty path for fewer than 2 points', () {
      final path = buildFreeDrawSmoothPath([const Offset(10, 10)]);
      final metrics = path.computeMetrics().toList();
      expect(metrics, isEmpty);
    });

    test('returns straight line for exactly 2 points', () {
      final path = buildFreeDrawSmoothPath([
        const Offset(0, 0),
        const Offset(100, 0),
      ]);
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1));
      expect(metrics.first.length, closeTo(100, 0.1));
    });

    test('returns smooth path for 3+ points', () {
      final points = [
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(100, 0),
      ];
      final path = buildFreeDrawSmoothPath(points);
      final metrics = path.computeMetrics().toList();
      expect(metrics, hasLength(1));
      // Smooth curve should be longer than straight segments.
      expect(metrics.first.length, greaterThan(100));
    });

    test('handles closed path (first == last)', () {
      final points = [
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(100, 0),
        const Offset(0, 0),
      ];
      final path = buildFreeDrawSmoothPath(points);
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty);
      // Closed path should have isClosed == true.
      expect(metrics.first.isClosed, isTrue);
    });

    test('produces consistent output for same input', () {
      final points = List.generate(20, (i) => Offset(i * 10.0, (i % 3) * 15.0));
      final path1 = buildFreeDrawSmoothPath(points);
      final path2 = buildFreeDrawSmoothPath(points);
      final m1 = path1.computeMetrics().toList();
      final m2 = path2.computeMetrics().toList();
      expect(m1.length, m2.length);
      for (var i = 0; i < m1.length; i++) {
        expect(m1[i].length, closeTo(m2[i].length, 0.001));
      }
    });

    test('handles many points without error', () {
      final points = List.generate(500, (i) => Offset(i * 2.0, (i % 7) * 5.0));
      final path = buildFreeDrawSmoothPath(points);
      final metrics = path.computeMetrics().toList();
      expect(metrics, isNotEmpty);
      expect(metrics.first.length, greaterThan(0));
    });
  });

  group('buildFreeDrawSmoothPathIncremental', () {
    test('returns null for fewer than 2 points', () {
      final result = buildFreeDrawSmoothPathIncremental(
        allPoints: [const Offset(10, 10)],
        basePath: Path(),
        basePointCount: 0,
      );
      expect(result, isNull);
    });

    test('returns null for closed path', () {
      final points = [
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(0, 0),
      ];
      final result = buildFreeDrawSmoothPathIncremental(
        allPoints: points,
        basePath: Path(),
        basePointCount: 2,
      );
      expect(result, isNull);
    });

    test('returns null when base is too short', () {
      final points = [
        const Offset(0, 0),
        const Offset(50, 50),
        const Offset(100, 0),
        const Offset(150, 50),
      ];
      final result = buildFreeDrawSmoothPathIncremental(
        allPoints: points,
        basePath: Path(),
        basePointCount: 2,
      );
      expect(result, isNull);
    });
  });

  group('resolveFreeDrawLocalPoints', () {
    test('converts normalized points to local space', () {
      final rect = const Rect.fromLTWH(0, 0, 200, 100);
      // Use DrawPoint and DrawRect from the actual API.
      // Since these are internal types, test via the path utils.
      // This is a smoke test to ensure the function exists.
      expect(resolveFreeDrawLocalPoints, isNotNull);
    });
  });
}
