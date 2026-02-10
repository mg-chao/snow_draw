import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/filter_scene_compositor.dart';

void main() {
  test('compositor paints non-filter elements using original canvas', () {
    var paintCount = 0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    var usedOriginalCanvas = true;
    filterSceneCompositor.paintElements(
      canvas: canvas,
      elements: const [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: 100, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'base2',
          rect: DrawRect(minX: 30, maxX: 80, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
      ],
      paintElement: (sceneCanvas, element) {
        if (!identical(sceneCanvas, canvas)) {
          usedOriginalCanvas = false;
        }
        paintCount += 1;
        sceneCanvas.drawRect(
          Rect.fromLTWH(
            element.rect.minX,
            element.rect.minY,
            element.rect.width,
            element.rect.height,
          ),
          Paint()..color = const Color(0xFF000000),
        );
      },
    );

    expect(paintCount, 2);
    expect(usedOriginalCanvas, isTrue);
    recorder.endRecording();
  });

  test('compositor handles filter overlay without throwing', () {
    const base = ElementState(
      id: 'base',
      rect: DrawRect(maxX: 100, maxY: 60),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );
    const filter = ElementState(
      id: 'filter',
      rect: DrawRect(minX: 10, minY: 10, maxX: 70, maxY: 50),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: FilterData(),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(
      () => filterSceneCompositor.paintElements(
        canvas: canvas,
        elements: const [base, filter],
        paintElement: (sceneCanvas, element) {
          sceneCanvas.drawRect(
            Rect.fromLTWH(
              element.rect.minX,
              element.rect.minY,
              element.rect.width,
              element.rect.height,
            ),
            Paint()..color = const Color(0xFF00AAFF),
          );
        },
      ),
      returnsNormally,
    );
    recorder.endRecording();
  });

  test('compositor handles non-shader fallback filters without throwing', () {
    const base = ElementState(
      id: 'base',
      rect: DrawRect(maxX: 100, maxY: 60),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );
    const grayscale = ElementState(
      id: 'grayscale',
      rect: DrawRect(minX: 10, minY: 10, maxX: 70, maxY: 50),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: FilterData(type: CanvasFilterType.grayscale),
    );
    const inversion = ElementState(
      id: 'inversion',
      rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 55),
      rotation: 0,
      opacity: 1,
      zIndex: 2,
      data: FilterData(type: CanvasFilterType.inversion),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    expect(
      () => filterSceneCompositor.paintElements(
        canvas: canvas,
        elements: const [base, grayscale, inversion],
        paintElement: (sceneCanvas, element) {
          sceneCanvas.drawRect(
            Rect.fromLTWH(
              element.rect.minX,
              element.rect.minY,
              element.rect.width,
              element.rect.height,
            ),
            Paint()..color = const Color(0xFFAA5500),
          );
        },
      ),
      returnsNormally,
    );
    recorder.endRecording();
  });

  test('compositor exposes diagnostics from segmented renderer', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    filterSceneCompositor.paintElements(
      canvas: canvas,
      elements: const [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: 100, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ],
      paintElement: (sceneCanvas, element) {
        sceneCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 20, 20),
          Paint()..color = const Color(0xFF336699),
        );
      },
    );

    final diagnostics = filterSceneCompositor.lastDiagnostics;
    expect(diagnostics.filterPasses, 0);
    expect(diagnostics.batchCount, 0);
    recorder.endRecording();
  });
}
