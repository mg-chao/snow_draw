import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_renderer.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_visual_cache.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  group('ArrowRenderer', () {
    setUp(arrowVisualCache.clear);

    for (final strokeStyle in StrokeStyle.values) {
      test('skips invalid single-point geometry for $strokeStyle', () {
        final element = _arrowElement(
          ArrowData(
            points: const [DrawPoint.zero],
            strokeStyle: strokeStyle,
            strokeWidth: 4,
          ),
        );

        expect(() => _render(element), returnsNormally);
      });
    }
  });
}

ElementState _arrowElement(ArrowData data) => ElementState(
  id: 'arrow_renderer_test',
  rect: const DrawRect(minX: 10, minY: 10, maxX: 110, maxY: 110),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: data,
);

void _render(ElementState element) {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, 256, 256));
  const ArrowRenderer().render(
    canvas: canvas,
    element: element,
    scaleFactor: 1,
  );
  recorder.endRecording().dispose();
}
