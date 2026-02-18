import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_hit_tester.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_renderer.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_visual_cache.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('FreeDraw two-point fast path', () {
    setUp(FreeDrawVisualCache.instance.clear);

    for (final strokeStyle in StrokeStyle.values) {
      test('renderer bypasses visual cache for $strokeStyle strokes', () {
        final element = _freeDrawElement(
          FreeDrawData(strokeStyle: strokeStyle, strokeWidth: 4),
        );

        _render(element);

        expect(FreeDrawVisualCache.instance.entryCount, 0);
      });
    }

    test('renderer still uses visual cache for multi-point strokes', () {
      final element = _freeDrawElement(
        const FreeDrawData(
          points: [
            DrawPoint.zero,
            DrawPoint(x: 0.45, y: 0.35),
            DrawPoint(x: 1, y: 1),
          ],
          strokeWidth: 4,
        ),
      );

      _render(element);

      expect(FreeDrawVisualCache.instance.entryCount, 1);
    });

    test('hit tester bypasses visual cache for two-point strokes', () {
      const hitTester = FreeDrawHitTester();
      final element = _freeDrawElement(const FreeDrawData(strokeWidth: 4));

      final isHit = hitTester.hitTest(
        element: element,
        position: const DrawPoint(x: 60, y: 60),
        tolerance: 1,
      );

      expect(isHit, isTrue);
      expect(FreeDrawVisualCache.instance.entryCount, 0);
    });

    test('hit tester keeps cached path flow for multi-point strokes', () {
      const hitTester = FreeDrawHitTester();
      final element = _freeDrawElement(
        const FreeDrawData(
          points: [
            DrawPoint.zero,
            DrawPoint(x: 0.4, y: 0.25),
            DrawPoint(x: 1, y: 1),
          ],
          strokeWidth: 4,
        ),
      );

      hitTester.hitTest(
        element: element,
        position: const DrawPoint(x: 60, y: 60),
        tolerance: 2,
      );

      expect(FreeDrawVisualCache.instance.entryCount, 1);
    });
  });
}

ElementState _freeDrawElement(FreeDrawData data) => ElementState(
  id: 'free_draw_line',
  rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: data,
);

void _render(ElementState element) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 256, 256));
  const FreeDrawRenderer().render(
    canvas: canvas,
    element: element,
    scaleFactor: 1,
  );
  recorder.endRecording().dispose();
}
