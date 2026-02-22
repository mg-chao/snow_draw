import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';

void main() {
  group('backend entrypoint contract', () {
    test('exports color and coordinate extensions used by app boundary', () {
      final color = const DrawColor(0xFF123456).toFlutterColor();
      expect(color, equals(const Color(0xFF123456)));

      const service = CoordinateService(camera: CameraState.initial);
      final world = service.screenOffsetToWorld(const Offset(10, 20));
      expect(world.x, 10);
      expect(world.y, 20);
      expect(service.worldPointToScreenOffset(world), const Offset(10, 20));
    });

    test(
      'exports Flutter text metrics service used by app context injection',
      () {
        expect(flutterTextMetricsService, isA<FlutterTextMetricsService>());

        final metrics = flutterTextMetricsService.measure(
          const TextLayoutRequest(
            data: TextData(text: 'Backend', fontSize: 14),
            maxWidth: 180,
          ),
        );

        expect(metrics.width, greaterThan(0));
        expect(metrics.height, greaterThan(0));
        expect(metrics.lineHeight, greaterThan(0));
        expect(metrics.lines, isNotEmpty);
      },
    );
  });
}
