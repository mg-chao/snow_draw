import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/utils/stroke_pattern_utils.dart';

void main() {
  group('LineShaderKey', () {
    test('quantizes spacing, lineWidth, and angle', () {
      final key = LineShaderKey(spacing: 5.123, lineWidth: 2.789, angle: 0.5);
      expect(key.spacing, 5.1);
      expect(key.lineWidth, 2.8);
      expect(key.angle, 0.5);
    });

    test('quantizes angle so near-identical values match', () {
      final a = LineShaderKey(
        spacing: 5,
        lineWidth: 2,
        angle: 0.7853981633974483,
      );
      final b = LineShaderKey(spacing: 5, lineWidth: 2, angle: 0.7854);
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('cache hits for near-identical angles', () {
      clearStrokePatternCaches();
      final paint1 = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0.7853981633974483,
        color: const Color(0xFFFF0000),
      );
      final paint2 = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0.7854,
        color: const Color(0xFF00FF00),
      );
      expect(identical(paint1.shader, paint2.shader), isTrue);
    });

    test('equal keys match', () {
      final a = LineShaderKey(
        spacing: 5,
        lineWidth: 2,
        angle: -math.pi / 4,
      );
      final b = LineShaderKey(
        spacing: 5,
        lineWidth: 2,
        angle: -math.pi / 4,
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('different keys do not match', () {
      final a = LineShaderKey(spacing: 5, lineWidth: 2, angle: 0);
      final b = LineShaderKey(spacing: 5, lineWidth: 3, angle: 0);
      expect(a, isNot(equals(b)));
    });
  });

  group('buildDashedPath', () {
    test('returns empty path for empty input', () {
      final result = buildDashedPath(Path(), 5, 3);
      // An empty input path produces an empty dashed path.
      final metrics = result.computeMetrics().toList();
      expect(metrics, isEmpty);
    });

    test('produces segments for a straight line', () {
      final base = Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0);
      final dashed = buildDashedPath(base, 10, 5);
      final metrics = dashed.computeMetrics().toList();
      // 100 / (10 + 5) = 6.67 → expect ~7 segments.
      expect(metrics.length, greaterThanOrEqualTo(6));
      expect(metrics.length, lessThanOrEqualTo(8));
    });
  });

  group('buildDottedPath', () {
    test('returns empty path for empty input', () {
      final result = buildDottedPath(Path(), 5, 1);
      final metrics = result.computeMetrics().toList();
      expect(metrics, isEmpty);
    });

    test('produces ovals for a straight line', () {
      final base = Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0);
      final dotted = buildDottedPath(base, 10, 2);
      // Each dot is an oval added to the path, so the path
      // should have multiple contours.
      final metrics = dotted.computeMetrics().toList();
      // 100 / 10 = 10 dots, each is a closed oval contour.
      expect(metrics.length, greaterThanOrEqualTo(9));
      expect(metrics.length, lessThanOrEqualTo(11));
    });
  });

  group('buildLineFillPaint', () {
    test('returns a paint with shader and color filter', () {
      final paint = buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: -math.pi / 4,
        color: const Color(0xFFFF0000),
      );
      expect(paint.style, PaintingStyle.fill);
      expect(paint.shader, isNotNull);
      expect(paint.colorFilter, isNotNull);
      expect(paint.isAntiAlias, isTrue);
    });

    test('caches shader for same key', () {
      clearStrokePatternCaches();
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
      // Same shader key → same shader instance.
      expect(identical(paint1.shader, paint2.shader), isTrue);
    });
  });

  group('clearStrokePatternCaches', () {
    test('clears the shader cache', () {
      buildLineFillPaint(
        spacing: 8,
        lineWidth: 1.5,
        angle: 0,
        color: const Color(0xFFFF0000),
      );
      expect(lineShaderCache.length, greaterThan(0));
      clearStrokePatternCaches();
      expect(lineShaderCache.length, 0);
    });
  });

  group('buildDotPositions', () {
    test('returns empty list for empty path', () {
      final result = buildDotPositions(Path(), 5);
      expect(result.length, 0);
    });

    test('produces (x, y) pairs for a straight line', () {
      final base = Path()
        ..moveTo(0, 0)
        ..lineTo(100, 0);
      final positions = buildDotPositions(base, 10);
      // 100 / 10 = 10 intervals → 11 dots, each is 2 floats.
      expect(positions.length, greaterThanOrEqualTo(20));
      expect(positions.length.isEven, isTrue);
      // First dot should be at the origin.
      expect(positions[0], closeTo(0, 0.1));
      expect(positions[1], closeTo(0, 0.1));
    });

    test('dot positions lie along the path', () {
      final base = Path()
        ..moveTo(0, 0)
        ..lineTo(50, 0);
      final positions = buildDotPositions(base, 10);
      // All y-values should be ~0 for a horizontal line.
      for (var i = 1; i < positions.length; i += 2) {
        expect(positions[i], closeTo(0, 0.1));
      }
      // x-values should be monotonically increasing.
      for (var i = 2; i < positions.length; i += 2) {
        expect(positions[i], greaterThanOrEqualTo(positions[i - 2] - 0.1));
      }
    });
  });
}
