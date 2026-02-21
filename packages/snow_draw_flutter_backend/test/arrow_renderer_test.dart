import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_flutter_backend/render/legacy/arrow_visual_cache.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_flutter_backend/render/legacy/arrow_renderer.dart';

void main() {
  setUp(arrowVisualCache.clear);

  for (final strokeStyle in StrokeStyle.values) {
    test('skips invalid single-point geometry for $strokeStyle', () {
      expect(
        () => _renderInvalidSinglePointArrow(strokeStyle),
        returnsNormally,
      );
    });
  }
}

void _renderInvalidSinglePointArrow(StrokeStyle strokeStyle) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 256, 256));
  final element = ElementState(
    id: 'arrow_renderer_test',
    rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: ArrowData(
      points: const [DrawPoint.zero],
      strokeStyle: strokeStyle,
      strokeWidth: 4,
    ),
  );
  const ArrowRenderer().render(
    canvas: canvas,
    element: element,
    scaleFactor: 1,
  );
  recorder.endRecording().dispose();
}
