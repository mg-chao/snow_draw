import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_hit_tester.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_flutter_backend/render/legacy/free_draw_visual_cache.dart';
import 'package:snow_draw_flutter_backend/render/legacy/free_draw_renderer.dart';

const _strokeWidth = 4.0;
const _elementRect = DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110);
const _canvasBounds = Rect.fromLTWH(0, 0, 256, 256);
const _hitPosition = DrawPoint(x: 60, y: 60);
const _multiPointStrokeData = FreeDrawData(
  points: [DrawPoint.zero, DrawPoint(x: 0.4, y: 0.3), DrawPoint(x: 1, y: 1)],
  strokeWidth: _strokeWidth,
);

void main() {
  group('FreeDraw two-point fast path', () {
    setUp(FreeDrawVisualCache.instance.clear);

    for (final strokeStyle in StrokeStyle.values) {
      test('renderer bypasses visual cache for $strokeStyle strokes', () {
        final element = _freeDrawElement(
          FreeDrawData(strokeStyle: strokeStyle, strokeWidth: _strokeWidth),
        );

        _render(element);

        _expectCacheEntryCount(0);
      });
    }

    test('renderer still uses visual cache for multi-point strokes', () {
      final element = _freeDrawElement(_multiPointStrokeData);

      _render(element);

      _expectCacheEntryCount(1);
    });

    test('hit tester bypasses visual cache for two-point strokes', () {
      const hitTester = FreeDrawHitTester();
      final element = _freeDrawElement(
        const FreeDrawData(strokeWidth: _strokeWidth),
      );

      final isHit = hitTester.hitTest(
        element: element,
        position: _hitPosition,
        tolerance: 1,
      );

      expect(isHit, isTrue);
      _expectCacheEntryCount(0);
    });

    test('hit tester bypasses visual cache for multi-point strokes', () {
      const hitTester = FreeDrawHitTester();
      final element = _freeDrawElement(_multiPointStrokeData);

      final isHit = hitTester.hitTest(
        element: element,
        position: _hitPosition,
        tolerance: 2,
      );

      expect(isHit, isTrue);
      _expectCacheEntryCount(0);
    });
  });
}

ElementState _freeDrawElement(FreeDrawData data) => ElementState(
  id: 'free_draw_line',
  rect: _elementRect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: data,
);

void _render(ElementState element) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, _canvasBounds);
  const FreeDrawRenderer().render(
    canvas: canvas,
    element: element,
    scaleFactor: 1,
  );
  recorder.endRecording().dispose();
}

void _expectCacheEntryCount(int expectedCount) {
  expect(FreeDrawVisualCache.instance.entryCount, expectedCount);
}
