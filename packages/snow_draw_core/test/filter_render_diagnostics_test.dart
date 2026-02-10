import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/filter_scene_compositor.dart';

void main() {
  test('diagnostics are bounded by batches and filters', () {
    final elements = <ElementState>[];
    for (var i = 0; i < 1000; i++) {
      elements.add(
        ElementState(
          id: 'e$i',
          rect: DrawRect(minX: i.toDouble(), maxX: i + 1, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: i,
          data: const RectangleData(),
        ),
      );
    }
    elements.addAll(const [
      ElementState(
        id: 'f1',
        rect: DrawRect(maxX: 100, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 1000,
        data: FilterData(type: CanvasFilterType.inversion),
      ),
      ElementState(
        id: 'f2',
        rect: DrawRect(minX: 20, maxX: 120, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 1001,
        data: FilterData(type: CanvasFilterType.grayscale),
      ),
      ElementState(
        id: 'f3',
        rect: DrawRect(minX: 40, maxX: 140, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 1002,
        data: FilterData(type: CanvasFilterType.gaussianBlur, strength: 0.8),
      ),
    ]);

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    filterSceneCompositor.paintElements(
      canvas: canvas,
      elements: elements,
      paintElement: (sceneCanvas, element) {
        if (element.data is RectangleData) {
          sceneCanvas.drawRect(
            Rect.fromLTWH(
              element.rect.minX,
              element.rect.minY,
              element.rect.width,
              element.rect.height,
            ),
            Paint()..color = const Color(0xFF2266AA),
          );
        }
      },
    );

    final diagnostics = filterSceneCompositor.lastDiagnostics;
    expect(diagnostics.filterPasses, 3);
    expect(diagnostics.batchCount, 1);
    expect(diagnostics.saveLayers, 3);
    expect(diagnostics.pictureRecorders, lessThanOrEqualTo(10));
    recorder.endRecording();
  });
}
