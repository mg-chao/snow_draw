import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/filter_pipeline/filter_segment_renderer.dart';

void _paintElementRect(Canvas canvas, ElementState element, Color color) {
  canvas.drawRect(
    Rect.fromLTWH(
      element.rect.minX,
      element.rect.minY,
      element.rect.width,
      element.rect.height,
    ),
    Paint()..color = color,
  );
}

void main() {
  test(
    'segment renderer paints non-filter elements on the original canvas',
    () {
      var paintCount = 0;
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      filterSegmentRenderer.paint(
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
          expect(identical(sceneCanvas, canvas), isTrue);
          paintCount += 1;
          _paintElementRect(sceneCanvas, element, const Color(0xFF000000));
        },
      );

      expect(paintCount, 2);
      recorder.endRecording();
    },
  );

  test('segment renderer handles filter overlays without throwing', () {
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
    filterSegmentRenderer.paint(
      canvas: canvas,
      elements: const [base, filter],
      paintElement: (sceneCanvas, element) {
        _paintElementRect(sceneCanvas, element, const Color(0xFF00AAFF));
      },
    );
    recorder.endRecording();
  });

  test(
    'segment renderer handles non-shader fallback filters without throwing',
    () {
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
      filterSegmentRenderer.paint(
        canvas: canvas,
        elements: const [base, grayscale, inversion],
        paintElement: (sceneCanvas, element) {
          _paintElementRect(sceneCanvas, element, const Color(0xFFAA5500));
        },
      );
      recorder.endRecording();
    },
  );

  test('segment renderer exposes diagnostics for segmented passes', () {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    filterSegmentRenderer.paint(
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
        _paintElementRect(sceneCanvas, element, const Color(0xFF336699));
      },
    );

    final diagnostics = filterSegmentRenderer.lastDiagnostics;
    expect(diagnostics.filterPasses, 0);
    expect(diagnostics.batchCount, 0);
    recorder.endRecording();
  });
}
