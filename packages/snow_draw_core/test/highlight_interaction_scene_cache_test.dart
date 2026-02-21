import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/highlight_interaction_scene_cache.dart';

const _englishLocale = ui.Locale('en');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses static segments across highlight edit frames', () {
    final cache = HighlightInteractionSceneCache();
    final firstFrame = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: firstFrame,
        dynamicElementIds: const {'dynamic'},
        documentVersion: 10,
        textRenderingCacheRevision: 0,
      ),
      3,
    );

    final secondFrame = _buildScene(
      dynamicRect: const DrawRect(minX: 120, minY: 40, maxX: 150, maxY: 80),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: secondFrame,
        dynamicElementIds: const {'dynamic'},
        documentVersion: 10,
        textRenderingCacheRevision: 0,
      ),
      1,
    );
  });

  test('reuses full scene picture when no dynamic element is present', () {
    final cache = HighlightInteractionSceneCache();
    final elements = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 20,
        textRenderingCacheRevision: 0,
      ),
      3,
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 20,
        textRenderingCacheRevision: 0,
      ),
      0,
    );
  });

  test('invalidates cached segments when text cache revision changes', () {
    final cache = HighlightInteractionSceneCache();
    final elements = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 30,
        textRenderingCacheRevision: 1,
      ),
      3,
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 30,
        textRenderingCacheRevision: 2,
      ),
      3,
    );
  });

  test(
    'invalidates full-scene cache when segment element instances change',
    () {
      final cache = HighlightInteractionSceneCache();
      final firstFrame = _buildScene(
        dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
      );
      expect(
        _paintFrame(
          cache: cache,
          elements: firstFrame,
          dynamicElementIds: const <String>{},
          documentVersion: 40,
          textRenderingCacheRevision: 0,
        ),
        3,
      );

      final secondFrame = <ElementState>[
        firstFrame[0],
        firstFrame[1].copyWith(
          rect: const DrawRect(minX: 60, maxX: 90, maxY: 10),
        ),
        firstFrame[2],
      ];
      expect(
        _paintFrame(
          cache: cache,
          elements: secondFrame,
          dynamicElementIds: const <String>{},
          documentVersion: 40,
          textRenderingCacheRevision: 0,
        ),
        3,
      );
    },
  );

  test('rebuilds segment layout when dynamic ids change', () {
    final cache = HighlightInteractionSceneCache();
    final elements = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        dynamicElementIds: const {'dynamic'},
        documentVersion: 50,
        textRenderingCacheRevision: 0,
      ),
      3,
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        dynamicElementIds: const {'static_2'},
        documentVersion: 50,
        textRenderingCacheRevision: 0,
      ),
      3,
    );
  });
}

List<ElementState> _buildScene({required DrawRect dynamicRect}) => [
  const ElementState(
    id: 'static_1',
    rect: DrawRect(maxX: 10, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  ),
  ElementState(
    id: 'dynamic',
    rect: dynamicRect,
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: const HighlightData(),
  ),
  const ElementState(
    id: 'static_2',
    rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: RectangleData(),
  ),
];

int _paintFrame({
  required HighlightInteractionSceneCache cache,
  required List<ElementState> elements,
  required Set<String> dynamicElementIds,
  required int documentVersion,
  required int textRenderingCacheRevision,
}) {
  var paintCount = 0;
  _paintOnFreshCanvas((canvas) {
    cache.paint(
      canvas: canvas,
      elements: elements,
      dynamicElementIds: dynamicElementIds,
      documentVersion: documentVersion,
      textRenderingCacheRevision: textRenderingCacheRevision,
      scaleFactor: 1,
      locale: _englishLocale,
      paintElement: (_, _) => paintCount++,
    );
  });
  return paintCount;
}

void _paintOnFreshCanvas(void Function(ui.Canvas canvas) paint) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
  recorder.endRecording().dispose();
}
