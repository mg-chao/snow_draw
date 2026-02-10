import 'dart:typed_data';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/filter_pipeline/filter_segment_renderer.dart';

void main() {
  test('renderer paints non-filter elements using original canvas', () {
    final renderer = FilterSegmentRenderer();
    var paintCount = 0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    var usedOriginalCanvas = true;

    renderer.paint(
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

  test('renderer handles stacked filter order without throwing', () {
    final renderer = FilterSegmentRenderer();
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
      () => renderer.paint(
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

  test('renderer filter opacity blends filtered result', () async {
    final renderer = FilterSegmentRenderer();
    const imageSize = ui.Size(80, 80);
    const baseColor = Color(0xFF204080);
    const filterOpacity = 0.25;

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    renderer.paint(
      canvas: canvas,
      elements: [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: imageSize.width, maxY: imageSize.height),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: const RectangleData(),
        ),
        const ElementState(
          id: 'filter',
          rect: DrawRect(maxX: 80, maxY: 80),
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

    final sampled = _readPixel(
      data!,
      imageSize.width.toInt(),
      const Offset(40, 40),
    );
    final inverted = Color.fromARGB(
      255,
      255 - _channelFromUnit(baseColor.r),
      255 - _channelFromUnit(baseColor.g),
      255 - _channelFromUnit(baseColor.b),
    );
    final expected = _lerpColor(baseColor, inverted, filterOpacity);
    final sampledR = _channelFromUnit(sampled.r);
    final sampledG = _channelFromUnit(sampled.g);
    final sampledB = _channelFromUnit(sampled.b);
    final expectedR = _channelFromUnit(expected.r);
    final expectedG = _channelFromUnit(expected.g);
    final expectedB = _channelFromUnit(expected.b);

    expect((sampledR - expectedR).abs(), lessThanOrEqualTo(2));
    expect((sampledG - expectedG).abs(), lessThanOrEqualTo(2));
    expect((sampledB - expectedB).abs(), lessThanOrEqualTo(2));
  });

  test('rotated filter clip path remains valid and bounded', () {
    final renderer = FilterSegmentRenderer();
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

    expect(
      () => renderer.paint(
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
          sceneCanvas.drawRect(
            Rect.fromLTWH(
              element.rect.minX,
              element.rect.minY,
              element.rect.width,
              element.rect.height,
            ),
            Paint()..color = const Color(0xFF2244AA),
          );
        },
      ),
      returnsNormally,
    );
    recorder.endRecording();
  });

  test('semi-transparent content is replaced, not double composited', () async {
    final renderer = FilterSegmentRenderer();
    const imageSize = ui.Size(80, 80);

    Future<Color> renderWithFilterCount(int filterCount) async {
      final elements = <ElementState>[
        const ElementState(
          id: 'base',
          rect: DrawRect(maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ];
      for (var i = 0; i < filterCount; i++) {
        elements.add(
          ElementState(
            id: 'filter-$i',
            rect: const DrawRect(maxX: 80, maxY: 80),
            rotation: 0,
            opacity: 1,
            zIndex: i + 1,
            data: const FilterData(type: CanvasFilterType.inversion),
          ),
        );
      }

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      renderer.paint(
        canvas: canvas,
        elements: elements,
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            Rect.fromLTWH(0, 0, imageSize.width, imageSize.height),
            Paint()..color = const Color(0x80FF0000),
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
      return _readPixel(data!, imageSize.width.toInt(), const Offset(40, 40));
    }

    final unfiltered = await renderWithFilterCount(0);
    final singleFiltered = await renderWithFilterCount(1);
    final doubleFiltered = await renderWithFilterCount(2);

    final unfilteredR = _channelFromUnit(unfiltered.r);
    final unfilteredG = _channelFromUnit(unfiltered.g);
    final unfilteredB = _channelFromUnit(unfiltered.b);
    final unfilteredA = _channelFromUnit(unfiltered.a);
    final singleFilteredR = _channelFromUnit(singleFiltered.r);
    final singleFilteredG = _channelFromUnit(singleFiltered.g);
    final singleFilteredB = _channelFromUnit(singleFiltered.b);
    final doubleFilteredR = _channelFromUnit(doubleFiltered.r);
    final doubleFilteredG = _channelFromUnit(doubleFiltered.g);
    final doubleFilteredB = _channelFromUnit(doubleFiltered.b);
    final doubleFilteredA = _channelFromUnit(doubleFiltered.a);

    final singleDiff =
        (singleFilteredR - unfilteredR).abs() +
        (singleFilteredG - unfilteredG).abs() +
        (singleFilteredB - unfilteredB).abs();
    expect(singleDiff, greaterThan(10));

    expect((doubleFilteredR - unfilteredR).abs(), lessThanOrEqualTo(2));
    expect((doubleFilteredG - unfilteredG).abs(), lessThanOrEqualTo(2));
    expect((doubleFilteredB - unfilteredB).abs(), lessThanOrEqualTo(2));
    expect((doubleFilteredA - unfilteredA).abs(), lessThanOrEqualTo(2));
  });

  test('filter cache is bounded while filter bounds vary', () {
    final renderer = FilterSegmentRenderer();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    for (var i = 0; i < 400; i++) {
      final extent = 40 + i.toDouble();
      renderer.paint(
        canvas: canvas,
        elements: [
          const ElementState(
            id: 'base',
            rect: DrawRect(maxX: 1024, maxY: 1024),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: RectangleData(),
          ),
          ElementState(
            id: 'filter',
            rect: DrawRect(maxX: extent, maxY: extent),
            rotation: 0,
            opacity: 1,
            zIndex: 1,
            data: const FilterData(type: CanvasFilterType.gaussianBlur),
          ),
        ],
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            const Rect.fromLTWH(0, 0, 1024, 1024),
            Paint()..color = const Color(0xFF334455),
          );
        },
      );
    }

    expect(
      renderer.debugFilterCacheSize,
      lessThanOrEqualTo(renderer.debugFilterCacheLimit),
    );
    recorder.endRecording();
  });
}

Color _lerpColor(Color a, Color b, double t) {
  final clampedT = t.clamp(0.0, 1.0);
  final baseR = _channelFromUnit(a.r);
  final baseG = _channelFromUnit(a.g);
  final baseB = _channelFromUnit(a.b);
  final baseA = _channelFromUnit(a.a);
  final targetR = _channelFromUnit(b.r);
  final targetG = _channelFromUnit(b.g);
  final targetB = _channelFromUnit(b.b);
  final targetA = _channelFromUnit(b.a);

  final r = (baseR + ((targetR - baseR) * clampedT)).round().clamp(0, 255);
  final g = (baseG + ((targetG - baseG) * clampedT)).round().clamp(0, 255);
  final bl = (baseB + ((targetB - baseB) * clampedT)).round().clamp(0, 255);
  final alpha = (baseA + ((targetA - baseA) * clampedT)).round().clamp(0, 255);
  return Color.fromARGB(alpha, r, g, bl);
}

int _channelFromUnit(double value) => (value * 255).round().clamp(0, 255);

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
