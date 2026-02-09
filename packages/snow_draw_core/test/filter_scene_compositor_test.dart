import 'dart:ui';
import 'dart:ui' as ui;
import 'dart:typed_data';

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

  test('rotated filter samples scene without rotating source content', () async {
    const imageSize = ui.Size(200, 200);
    const filterElement = ElementState(
      id: 'filter',
      rect: DrawRect(minX: 60, minY: 80, maxX: 140, maxY: 120),
      rotation: 0.7853981633974483,
      opacity: 1,
      zIndex: 1,
      data: FilterData(type: CanvasFilterType.inversion),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    filterSceneCompositor.paintElements(
      canvas: canvas,
      elements: const [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: 200, maxY: 200),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        filterElement,
      ],
      paintElement: (sceneCanvas, element) {
        if (element.id != 'base') {
          return;
        }
        sceneCanvas.drawRect(
          Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
          Paint()
            ..shader = ui.Gradient.linear(
              const Offset(0, 0),
              Offset(imageSize.width, 0),
              const [Color(0xFFFF0000), Color(0xFF0000FF)],
            ),
        );
      },
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      imageSize.width.toInt(),
      imageSize.height.toInt(),
    );
    final data = await image.toByteData();
    expect(data, isNotNull);

    const samplePoint = Offset(100, 100);
    final sampled = _readPixel(data!, imageSize.width.toInt(), samplePoint);
    final t = samplePoint.dx / imageSize.width;
    final source = _lerpColor(
      const Color(0xFFFF0000),
      const Color(0xFF0000FF),
      t,
    );
    final expected = Color.fromARGB(
      255,
      255 - source.red,
      255 - source.green,
      255 - source.blue,
    );

    expect((sampled.red - expected.red).abs(), lessThanOrEqualTo(3));
    expect((sampled.green - expected.green).abs(), lessThanOrEqualTo(3));
    expect((sampled.blue - expected.blue).abs(), lessThanOrEqualTo(3));
  });

  test('filter opacity blends filtered result with underlying scene', () async {
    const imageSize = ui.Size(80, 80);
    const baseColor = Color(0xFF204080);
    const filterOpacity = 0.25;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    filterSceneCompositor.paintElements(
      canvas: canvas,
      elements: [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: imageSize.width, maxY: imageSize.height),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'filter',
          rect: DrawRect(maxX: imageSize.width, maxY: imageSize.height),
          rotation: 0,
          opacity: filterOpacity,
          zIndex: 1,
          data: FilterData(type: CanvasFilterType.inversion),
        ),
      ],
      paintElement: (sceneCanvas, element) {
        if (element.id != 'base') {
          return;
        }
        sceneCanvas.drawRect(
          Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
          Paint()..color = baseColor,
        );
      },
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      imageSize.width.toInt(),
      imageSize.height.toInt(),
    );
    final data = await image.toByteData();
    expect(data, isNotNull);

    final sampled = _readPixel(data!, imageSize.width.toInt(), const Offset(40, 40));
    final inverted = Color.fromARGB(
      255,
      255 - baseColor.red,
      255 - baseColor.green,
      255 - baseColor.blue,
    );
    final expected = _lerpColor(baseColor, inverted, filterOpacity);

    expect((sampled.red - expected.red).abs(), lessThanOrEqualTo(2));
    expect((sampled.green - expected.green).abs(), lessThanOrEqualTo(2));
    expect((sampled.blue - expected.blue).abs(), lessThanOrEqualTo(2));
  });
}

Color _lerpColor(Color a, Color b, double t) {
  final clampedT = t.clamp(0.0, 1.0);
  final r = (a.red + ((b.red - a.red) * clampedT)).round().clamp(0, 255);
  final g = (a.green + ((b.green - a.green) * clampedT)).round().clamp(0, 255);
  final bl = (a.blue + ((b.blue - a.blue) * clampedT)).round().clamp(0, 255);
  final alpha =
      (a.alpha + ((b.alpha - a.alpha) * clampedT)).round().clamp(0, 255);
  return Color.fromARGB(alpha, r, g, bl);
}

Color _readPixel(ByteData data, int width, Offset offset) {
  final x = offset.dx.round().clamp(0, width - 1);
  final y = offset.dy.round();
  final index = ((y * width) + x) * 4;
  final r = data.getUint8(index);
  final g = data.getUint8(index + 1);
  final b = data.getUint8(index + 2);
  final a = data.getUint8(index + 3);
  return Color.fromARGB(a, r, g, b);
}
