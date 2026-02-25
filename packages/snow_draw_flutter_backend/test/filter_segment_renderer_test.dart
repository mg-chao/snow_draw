import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/filter_pipeline/filter_segment_renderer.dart';

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

  test('renderer paints all split non-filter batches on original canvas', () {
    final renderer = FilterSegmentRenderer(
      segmentBuilder: const _SplitNonFilterSegmentBuilder(),
    );
    var paintCount = 0;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    var usedOriginalCanvas = true;

    renderer.paint(
      canvas: canvas,
      elements: const [
        ElementState(
          id: 'first',
          rect: DrawRect(maxX: 100, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'second',
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
          Paint()..color = const Color(0xFF336699),
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
    const imageSize = Size(80, 80);
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

  test(
    'overlapping inversions keep sequential compositing semantics',
    () async {
      final renderer = FilterSegmentRenderer();
      const imageSize = Size(80, 80);

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
      final singleFilteredR = _channelFromUnit(singleFiltered.r);
      final singleFilteredG = _channelFromUnit(singleFiltered.g);
      final singleFilteredB = _channelFromUnit(singleFiltered.b);
      final doubleFilteredR = _channelFromUnit(doubleFiltered.r);
      final doubleFilteredG = _channelFromUnit(doubleFiltered.g);
      final doubleFilteredB = _channelFromUnit(doubleFiltered.b);

      final singleDiff =
          (singleFilteredR - unfilteredR).abs() +
          (singleFilteredG - unfilteredG).abs() +
          (singleFilteredB - unfilteredB).abs();
      expect(singleDiff, greaterThan(10));

      final doubleDiff =
          (doubleFilteredR - unfilteredR).abs() +
          (doubleFilteredG - unfilteredG).abs() +
          (doubleFilteredB - unfilteredB).abs();
      expect(doubleDiff, greaterThan(5));

      final diagnostics = renderer.lastDiagnostics;
      expect(diagnostics.filterPasses, 2);
      expect(diagnostics.pictureRecorders, greaterThanOrEqualTo(1));
    },
  );

  test(
    'renderer reuses stable non-filter batches across filter preview frames',
    () {
      final renderer = FilterSegmentRenderer();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const baseElement = ElementState(
        id: 'base',
        rect: DrawRect(maxX: 160, maxY: 90),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      const cacheContext = FilterRenderCacheContext(
        textRenderingCacheRevision: 7,
        scaleKey: 1000,
        localeTag: 'en-US',
      );

      void paintFrame(DrawRect filterRect) {
        renderer.paint(
          canvas: canvas,
          elements: [
            baseElement,
            ElementState(
              id: 'filter',
              rect: filterRect,
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: const FilterData(type: CanvasFilterType.inversion),
            ),
          ],
          paintElement: (sceneCanvas, element) {
            if (element.id != 'base') {
              return;
            }
            sceneCanvas.drawRect(
              const Rect.fromLTWH(0, 0, 160, 90),
              Paint()..color = const Color(0xFF114477),
            );
          },
          cacheContext: cacheContext,
        );
      }

      paintFrame(const DrawRect(maxX: 80, maxY: 80));
      final firstFrame = renderer.lastDiagnostics;
      paintFrame(const DrawRect(minX: 10, minY: 10, maxX: 90, maxY: 90));
      final secondFrame = renderer.lastDiagnostics;

      expect(firstFrame.batchCacheHits, 0);
      expect(firstFrame.batchCacheMisses, greaterThanOrEqualTo(1));
      expect(secondFrame.batchCacheHits, greaterThanOrEqualTo(1));
      expect(secondFrame.batchCacheMisses, 0);
      expect(
        secondFrame.pictureRecorders,
        lessThan(firstFrame.pictureRecorders),
      );
      recorder.endRecording();
    },
  );

  test(
    'batch picture cache invalidates when non-filter element identity changes',
    () {
      final renderer = FilterSegmentRenderer();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const cacheContext = FilterRenderCacheContext(
        textRenderingCacheRevision: 5,
        scaleKey: 1000,
        localeTag: 'en-US',
      );

      const baseA = ElementState(
        id: 'base',
        rect: DrawRect(maxX: 160, maxY: 90),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final baseB = baseA.copyWith(opacity: 0.8);

      void paintFrame(ElementState base) {
        renderer.paint(
          canvas: canvas,
          elements: [
            base,
            const ElementState(
              id: 'filter',
              rect: DrawRect(minX: 16, minY: 10, maxX: 128, maxY: 84),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: FilterData(type: CanvasFilterType.inversion),
            ),
          ],
          paintElement: (sceneCanvas, element) {
            if (element.id != 'base') {
              return;
            }
            sceneCanvas.drawRect(
              const Rect.fromLTWH(0, 0, 160, 90),
              Paint()..color = const Color(0xFF114477),
            );
          },
          cacheContext: cacheContext,
        );
      }

      paintFrame(baseA);
      final firstFrame = renderer.lastDiagnostics;
      paintFrame(baseB);
      final secondFrame = renderer.lastDiagnostics;

      expect(firstFrame.batchCacheMisses, greaterThanOrEqualTo(1));
      expect(firstFrame.batchCacheHits, 0);
      expect(secondFrame.batchCacheHits, 0);
      expect(secondFrame.batchCacheMisses, greaterThanOrEqualTo(1));
      recorder.endRecording();
    },
  );

  test('batch cache survives context recreation '
      'when batch elements are stable', () {
    final renderer = FilterSegmentRenderer();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const cacheContextV1 = FilterRenderCacheContext(
      textRenderingCacheRevision: 5,
      scaleKey: 1000,
      localeTag: 'en-US',
    );
    final cacheRevision = cacheContextV1.textRenderingCacheRevision;
    final scaleKey = cacheContextV1.scaleKey;
    final localeTag = cacheContextV1.localeTag;
    final cacheContextV2 = FilterRenderCacheContext(
      textRenderingCacheRevision: cacheRevision,
      scaleKey: scaleKey,
      localeTag: localeTag,
    );
    const baseElement = ElementState(
      id: 'base',
      rect: DrawRect(maxX: 160, maxY: 90),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );
    const filterElement = ElementState(
      id: 'filter',
      rect: DrawRect(maxX: 80, maxY: 80),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: FilterData(type: CanvasFilterType.inversion),
    );
    const sceneElements = [baseElement, filterElement];

    void paintFrame(FilterRenderCacheContext cacheContext) {
      renderer.paint(
        canvas: canvas,
        elements: sceneElements,
        cacheContext: cacheContext,
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            const Rect.fromLTWH(0, 0, 160, 90),
            Paint()..color = const Color(0xFF225588),
          );
        },
      );
    }

    paintFrame(cacheContextV1);
    final firstFrame = renderer.lastDiagnostics;
    paintFrame(cacheContextV2);
    final secondFrame = renderer.lastDiagnostics;

    expect(firstFrame.batchCacheMisses, greaterThanOrEqualTo(1));
    expect(secondFrame.batchCacheHits, greaterThanOrEqualTo(1));
    expect(secondFrame.batchCacheMisses, 0);
    recorder.endRecording();
  });

  test('batch cache invalidates when serial connector revision changes', () {
    final renderer = FilterSegmentRenderer();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const cacheContextV1 = FilterRenderCacheContext(
      textRenderingCacheRevision: 5,
      scaleKey: 1000,
      localeTag: 'en-US',
      serialConnectorRevision: 11,
    );
    const cacheContextV2 = FilterRenderCacheContext(
      textRenderingCacheRevision: 5,
      scaleKey: 1000,
      localeTag: 'en-US',
      serialConnectorRevision: 12,
    );
    const baseElement = ElementState(
      id: 'base',
      rect: DrawRect(maxX: 160, maxY: 90),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );
    const filterElement = ElementState(
      id: 'filter',
      rect: DrawRect(maxX: 80, maxY: 80),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: FilterData(type: CanvasFilterType.inversion),
    );
    const sceneElements = [baseElement, filterElement];

    void paintFrame(FilterRenderCacheContext cacheContext) {
      renderer.paint(
        canvas: canvas,
        elements: sceneElements,
        cacheContext: cacheContext,
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            const Rect.fromLTWH(0, 0, 160, 90),
            Paint()..color = const Color(0xFF225588),
          );
        },
      );
    }

    paintFrame(cacheContextV1);
    final firstFrame = renderer.lastDiagnostics;
    paintFrame(cacheContextV2);
    final secondFrame = renderer.lastDiagnostics;

    expect(firstFrame.batchCacheMisses, greaterThanOrEqualTo(1));
    expect(secondFrame.batchCacheHits, 0);
    expect(secondFrame.batchCacheMisses, greaterThanOrEqualTo(1));
    recorder.endRecording();
  });

  test('batch cache eviction keeps in-flight batch pictures valid', () async {
    final renderer = FilterSegmentRenderer(
      segmentBuilder: const _SplitNonFilterSegmentBuilder(),
    );
    const batchCount = 128;
    const baseColor = Color(0xFF223344);
    const cacheContext = FilterRenderCacheContext(
      textRenderingCacheRevision: 3,
      scaleKey: 1000,
      localeTag: 'en-US',
    );
    final elements = <ElementState>[
      for (var i = 0; i < batchCount; i++)
        ElementState(
          id: 'base-$i',
          rect: DrawRect(minX: i * 2, maxX: (i + 1) * 2, maxY: 24),
          rotation: 0,
          opacity: 1,
          zIndex: i,
          data: const RectangleData(),
        ),
      const ElementState(
        id: 'filter',
        rect: DrawRect(maxX: batchCount * 2, maxY: 24),
        rotation: 0,
        opacity: 1,
        zIndex: batchCount,
        data: FilterData(type: CanvasFilterType.inversion),
      ),
    ];

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    renderer.paint(
      canvas: canvas,
      elements: elements,
      cacheContext: cacheContext,
      paintElement: (sceneCanvas, element) {
        if (element.id == 'filter') {
          return;
        }
        sceneCanvas.drawRect(
          Rect.fromLTWH(
            element.rect.minX,
            element.rect.minY,
            element.rect.width,
            element.rect.height,
          ),
          Paint()..color = baseColor,
        );
      },
    );

    final picture = recorder.endRecording();
    final image = await picture.toImage(batchCount * 2, 24);
    final data = await image.toByteData();
    expect(data, isNotNull);

    final expected = Color.fromARGB(
      255,
      255 - _channelFromUnit(baseColor.r),
      255 - _channelFromUnit(baseColor.g),
      255 - _channelFromUnit(baseColor.b),
    );
    final firstPixel = _readPixel(data!, batchCount * 2, const Offset(1, 12));
    final lastPixel = _readPixel(
      data,
      batchCount * 2,
      const Offset((batchCount * 2) - 2, 12),
    );
    expect(_channelFromUnit(firstPixel.a), greaterThan(0));
    expect(_channelFromUnit(lastPixel.a), greaterThan(0));

    final expectedR = _channelFromUnit(expected.r);
    final expectedG = _channelFromUnit(expected.g);
    final expectedB = _channelFromUnit(expected.b);
    expect(
      (_channelFromUnit(firstPixel.r) - expectedR).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (_channelFromUnit(firstPixel.g) - expectedG).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (_channelFromUnit(firstPixel.b) - expectedB).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (_channelFromUnit(lastPixel.r) - expectedR).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (_channelFromUnit(lastPixel.g) - expectedG).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      (_channelFromUnit(lastPixel.b) - expectedB).abs(),
      lessThanOrEqualTo(2),
    );
    expect(
      renderer.debugBatchPictureCacheSize,
      lessThanOrEqualTo(renderer.debugBatchPictureCacheLimit),
    );
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

  test('tail filter pass avoids additional picture recording on cache hit', () {
    final renderer = FilterSegmentRenderer();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const cacheContext = FilterRenderCacheContext(
      textRenderingCacheRevision: 1,
      scaleKey: 1000,
      localeTag: 'en-US',
    );
    const base = ElementState(
      id: 'base',
      rect: DrawRect(maxX: 128, maxY: 96),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );
    const filter = ElementState(
      id: 'filter',
      rect: DrawRect(minX: 16, minY: 16, maxX: 112, maxY: 80),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: FilterData(type: CanvasFilterType.inversion),
    );

    void paintFrame() {
      renderer.paint(
        canvas: canvas,
        elements: const [base, filter],
        cacheContext: cacheContext,
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            const Rect.fromLTWH(0, 0, 128, 96),
            Paint()..color = const Color(0xFF667788),
          );
        },
      );
    }

    paintFrame();
    final first = renderer.lastDiagnostics;
    paintFrame();
    final second = renderer.lastDiagnostics;

    expect(first.pictureRecorders, greaterThanOrEqualTo(1));
    expect(second.pictureRecorders, 0);
    expect(second.batchCacheHits, 1);
    recorder.endRecording();
  });

  test(
    'tail merged-filter pass avoids additional picture recording on cache hit',
    () {
      final renderer = FilterSegmentRenderer();
      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      const cacheContext = FilterRenderCacheContext(
        textRenderingCacheRevision: 2,
        scaleKey: 1000,
        localeTag: 'en-US',
      );
      const base = ElementState(
        id: 'base',
        rect: DrawRect(maxX: 128, maxY: 96),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      const firstFilter = ElementState(
        id: 'filter-1',
        rect: DrawRect(minX: 12, minY: 12, maxX: 60, maxY: 84),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(type: CanvasFilterType.inversion),
      );
      const secondFilter = ElementState(
        id: 'filter-2',
        rect: DrawRect(minX: 68, minY: 12, maxX: 116, maxY: 84),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: FilterData(type: CanvasFilterType.inversion),
      );

      void paintFrame() {
        renderer.paint(
          canvas: canvas,
          elements: const [base, firstFilter, secondFilter],
          cacheContext: cacheContext,
          paintElement: (sceneCanvas, element) {
            if (element.id != 'base') {
              return;
            }
            sceneCanvas.drawRect(
              const Rect.fromLTWH(0, 0, 128, 96),
              Paint()..color = const Color(0xFF425A70),
            );
          },
        );
      }

      paintFrame();
      final first = renderer.lastDiagnostics;
      paintFrame();
      final second = renderer.lastDiagnostics;

      expect(first.pictureRecorders, greaterThanOrEqualTo(1));
      expect(second.pictureRecorders, 0);
      expect(second.batchCacheHits, 1);
      expect(second.filterPasses, 2);
      recorder.endRecording();
    },
  );

  test(
    'tail merged-filter pass preserves overlapping filter semantics',
    () async {
      const imageWidth = 96.0;
      const imageHeight = 96.0;
      const base = ElementState(
        id: 'base',
        rect: DrawRect(maxX: imageWidth, maxY: imageHeight),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      const firstFilter = ElementState(
        id: 'filter-1',
        rect: DrawRect(minX: 8, minY: 8, maxX: 88, maxY: 88),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(type: CanvasFilterType.inversion),
      );
      const secondFilter = ElementState(
        id: 'filter-2',
        rect: DrawRect(minX: 20, minY: 16, maxX: 92, maxY: 92),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: FilterData(type: CanvasFilterType.inversion),
      );

      Future<Color> renderSample(FilterSegmentBuilder segmentBuilder) async {
        final renderer = FilterSegmentRenderer(segmentBuilder: segmentBuilder);
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        renderer.paint(
          canvas: canvas,
          elements: const [base, firstFilter, secondFilter],
          paintElement: (sceneCanvas, element) {
            if (element.id != 'base') {
              return;
            }
            sceneCanvas.drawRect(
              const Rect.fromLTWH(0, 0, imageWidth, imageHeight),
              Paint()..color = const Color(0x806699CC),
            );
          },
        );

        final picture = recorder.endRecording();
        final image = await picture.toImage(
          imageWidth.toInt(),
          imageHeight.toInt(),
        );
        final bytes = await image.toByteData();
        expect(bytes, isNotNull);
        return _readPixel(bytes!, imageWidth.toInt(), const Offset(48, 48));
      }

      final mergedOutput = await renderSample(const FilterSegmentBuilder());
      final splitOutput = await renderSample(
        const _NoMergeFilterSegmentBuilder(),
      );

      expect(
        (_channelFromUnit(mergedOutput.r) - _channelFromUnit(splitOutput.r))
            .abs(),
        lessThanOrEqualTo(2),
      );
      expect(
        (_channelFromUnit(mergedOutput.g) - _channelFromUnit(splitOutput.g))
            .abs(),
        lessThanOrEqualTo(2),
      );
      expect(
        (_channelFromUnit(mergedOutput.b) - _channelFromUnit(splitOutput.b))
            .abs(),
        lessThanOrEqualTo(2),
      );
    },
  );

  test('mosaic cache normalizes quantized offsets at block boundaries', () {
    final kernelFactory = _TestKernelFactory(
      canUseMosaicShader: true,
      resolvedBlockSize: 2,
    );
    final renderer = FilterSegmentRenderer(kernelFactory: kernelFactory);
    const base = ElementState(
      id: 'base',
      rect: DrawRect(maxX: 256, maxY: 128),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );

    List<ElementState> elementsForOffset(double filterMinX) => [
      base,
      ElementState(
        id: 'filter',
        rect: DrawRect(minX: filterMinX, maxX: filterMinX + 128, maxY: 96),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: const FilterData(strength: 0.8),
      ),
    ];

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    renderer
      ..paint(
        canvas: canvas,
        elements: elementsForOffset(1.9),
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            const Rect.fromLTWH(0, 0, 256, 128),
            Paint()..color = const Color(0xFF556677),
          );
        },
      )
      ..paint(
        canvas: canvas,
        elements: elementsForOffset(0.1),
        paintElement: (sceneCanvas, element) {
          if (element.id != 'base') {
            return;
          }
          sceneCanvas.drawRect(
            const Rect.fromLTWH(0, 0, 256, 128),
            Paint()..color = const Color(0xFF556677),
          );
        },
      );

    expect(kernelFactory.resolveMosaicCalls, 2);
    expect(kernelFactory.createMosaicCalls, 1);
    recorder.endRecording();
  });

  test('offscreen filter work is skipped when visible bounds are provided', () {
    final renderer = FilterSegmentRenderer();
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);

    renderer.paint(
      canvas: canvas,
      visibleBounds: const Rect.fromLTWH(0, 0, 100, 100),
      elements: const [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: 100, maxY: 100),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'offscreen-filter',
          rect: DrawRect(minX: 500, minY: 500, maxX: 620, maxY: 620),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(type: CanvasFilterType.gaussianBlur),
        ),
      ],
      paintElement: (sceneCanvas, element) {
        if (element.id != 'base') {
          return;
        }
        sceneCanvas.drawRect(
          const Rect.fromLTWH(0, 0, 100, 100),
          Paint()..color = const Color(0xFF112233),
        );
      },
    );

    final diagnostics = renderer.lastDiagnostics;
    expect(diagnostics.filterPasses, 0);
    expect(diagnostics.saveLayers, 0);
    recorder.endRecording();
  });

  test(
    'mosaic filter stays visually stable when visible bounds cull the layer',
    () async {
      final renderer = FilterSegmentRenderer();
      const imageWidth = 320.0;
      const imageHeight = 320.0;
      const base = ElementState(
        id: 'base',
        rect: DrawRect(maxX: imageWidth, maxY: imageHeight),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      const filter = ElementState(
        id: 'mosaic',
        rect: DrawRect(maxX: imageWidth, maxY: imageHeight),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: FilterData(),
      );

      Future<Color> renderSampleColor({Rect? visibleBounds}) async {
        final recorder = PictureRecorder();
        final canvas = Canvas(recorder);
        renderer.paint(
          canvas: canvas,
          visibleBounds: visibleBounds,
          elements: const [base, filter],
          paintElement: (sceneCanvas, element) {
            if (element.id != 'base') {
              return;
            }
            const tileSize = 8;
            for (var y = 0; y < imageHeight; y += tileSize) {
              for (var x = 0; x < imageWidth; x += tileSize) {
                final isDarkTile =
                    (((x ~/ tileSize) + (y ~/ tileSize)) & 1) == 0;
                sceneCanvas.drawRect(
                  Rect.fromLTWH(
                    x.toDouble(),
                    y.toDouble(),
                    tileSize.toDouble(),
                    tileSize.toDouble(),
                  ),
                  Paint()
                    ..color = isDarkTile
                        ? const Color(0xFF14213D)
                        : const Color(0xFFFCA311),
                );
              }
            }
          },
        );

        final picture = recorder.endRecording();
        final image = await picture.toImage(
          imageWidth.toInt(),
          imageHeight.toInt(),
        );
        final bytes = await image.toByteData();
        expect(bytes, isNotNull);
        return _readPixel(bytes!, imageWidth.toInt(), const Offset(188, 172));
      }

      final fullFrame = await renderSampleColor();
      final culledFrame = await renderSampleColor(
        visibleBounds: const Rect.fromLTWH(120, 120, 120, 120),
      );

      expect(
        (_channelFromUnit(fullFrame.r) - _channelFromUnit(culledFrame.r)).abs(),
        lessThanOrEqualTo(2),
      );
      expect(
        (_channelFromUnit(fullFrame.g) - _channelFromUnit(culledFrame.g)).abs(),
        lessThanOrEqualTo(2),
      );
      expect(
        (_channelFromUnit(fullFrame.b) - _channelFromUnit(culledFrame.b)).abs(),
        lessThanOrEqualTo(2),
      );
    },
  );
}

Color _lerpColor(Color a, Color b, double t) =>
    Color.lerp(a, b, t.clamp(0.0, 1.0))!;

class _SplitNonFilterSegmentBuilder extends FilterSegmentBuilder {
  const _SplitNonFilterSegmentBuilder();

  @override
  List<RenderSegment> build(List<ElementState> elements) {
    final splitSegments = <RenderSegment>[];
    for (final segment in super.build(elements)) {
      if (segment is! ElementBatchSegment || segment.elements.length <= 1) {
        splitSegments.add(segment);
        continue;
      }
      splitSegments.addAll(
        segment.elements.map(
          (element) =>
              ElementBatchSegment(List<ElementState>.unmodifiable([element])),
        ),
      );
    }
    return splitSegments;
  }
}

class _NoMergeFilterSegmentBuilder extends FilterSegmentBuilder {
  const _NoMergeFilterSegmentBuilder();

  @override
  List<RenderSegment> build(List<ElementState> elements) {
    final segments = <RenderSegment>[];
    for (final segment in super.build(elements)) {
      if (segment is! MergedFilterSegment) {
        segments.add(segment);
        continue;
      }
      segments.addAll(segment.filters);
    }
    return segments;
  }
}

int _channelFromUnit(double value) => (value * 255).round().clamp(0, 255);

Color _readPixel(ByteData data, int width, Offset offset) {
  final x = offset.dx.round().clamp(0, width - 1);
  final height = data.lengthInBytes ~/ (width * 4);
  final y = offset.dy.round().clamp(0, height - 1);
  final index = ((y * width) + x) * 4;
  final r = data.getUint8(index);
  final g = data.getUint8(index + 1);
  final b = data.getUint8(index + 2);
  final a = data.getUint8(index + 3);
  return Color.fromARGB(a, r, g, b);
}

class _TestKernelFactory implements FilterKernelFactory {
  _TestKernelFactory({
    required this.canUseMosaicShader,
    this.resolvedBlockSize = 12,
  });

  @override
  final bool canUseMosaicShader;
  final double resolvedBlockSize;

  var createMosaicCalls = 0;
  var resolveMosaicCalls = 0;

  @override
  double resolveMosaicBlockSize({
    required double strength,
    required Size regionSize,
  }) {
    resolveMosaicCalls += 1;
    return resolvedBlockSize;
  }

  @override
  ImageFilter? createMosaicFilter({
    required double strength,
    required Size regionSize,
    required Offset regionOffset,
    double? blockSize,
  }) {
    createMosaicCalls += 1;
    return ImageFilter.blur(sigmaX: 6, sigmaY: 6);
  }
}
