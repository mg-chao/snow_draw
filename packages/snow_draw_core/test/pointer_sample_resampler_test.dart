import 'package:snow_draw_core/draw/input/pointer_sample_resampler.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('resamplePointerSamples', () {
    test('returns empty list when maxSamples is non-positive', () {
      final samples = <DrawPoint>[DrawPoint.zero, const DrawPoint(x: 1, y: 0)];

      final result = resamplePointerSamples(
        sampledPoints: samples,
        maxSamples: 0,
      );

      expect(result, isEmpty);
    });

    test('returns the latest sample when maxSamples is one', () {
      final samples = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 1, y: 0),
        const DrawPoint(x: 2, y: 0),
      ];

      final result = resamplePointerSamples(
        sampledPoints: samples,
        maxSamples: 1,
      );

      expect(result, hasLength(1));
      expect(result.single, samples.last);
    });

    test('returns original samples when already within cap', () {
      final samples = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 1, y: 0),
        const DrawPoint(x: 2, y: 0),
      ];

      final result = resamplePointerSamples(
        sampledPoints: samples,
        maxSamples: 8,
      );

      expect(identical(result, samples), isTrue);
    });

    test('keeps endpoints and caps interior samples', () {
      final samples = List<DrawPoint>.generate(
        100,
        (index) => DrawPoint(x: index.toDouble(), y: 0),
      );

      final result = resamplePointerSamples(
        sampledPoints: samples,
        maxSamples: 12,
      );

      expect(result.length, lessThanOrEqualTo(12));
      expect(result.first, samples.first);
      expect(result.last, samples.last);
    });

    test('drops adjacent duplicates introduced by rounded indices', () {
      final samples = <DrawPoint>[
        DrawPoint.zero,
        DrawPoint.zero,
        const DrawPoint(x: 1, y: 0),
        const DrawPoint(x: 2, y: 0),
        const DrawPoint(x: 2, y: 0),
      ];

      final result = resamplePointerSamples(
        sampledPoints: samples,
        maxSamples: 4,
      );

      for (var i = 1; i < result.length; i++) {
        expect(result[i], isNot(result[i - 1]));
      }
      expect(result.first, samples.first);
      expect(result.last, samples.last);
    });
  });
}
