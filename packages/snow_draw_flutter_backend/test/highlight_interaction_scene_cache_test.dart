import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/highlight_interaction_scene_cache.dart';

const _englishLocale = ui.Locale('en');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses static segments across highlight edit frames', () {
    final cache = InteractionSceneCache();
    final firstFrame = _buildScene(
      volatileRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: firstFrame,
        volatileElementIds: const {'volatile'},
        documentVersion: 10,
        textRenderingCacheRevision: 0,
      ),
      3,
    );

    final secondFrame = _buildScene(
      volatileRect: const DrawRect(minX: 120, minY: 40, maxX: 150, maxY: 80),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: secondFrame,
        volatileElementIds: const {'volatile'},
        documentVersion: 10,
        textRenderingCacheRevision: 0,
      ),
      1,
    );
  });

  test('reuses full scene picture when no volatile element is present', () {
    final cache = InteractionSceneCache();
    final elements = _buildScene(
      volatileRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        volatileElementIds: const <String>{},
        documentVersion: 20,
        textRenderingCacheRevision: 0,
      ),
      3,
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        volatileElementIds: const <String>{},
        documentVersion: 20,
        textRenderingCacheRevision: 0,
      ),
      0,
    );
  });

  test('invalidates cached segments when text cache revision changes', () {
    final cache = InteractionSceneCache();
    final elements = _buildScene(
      volatileRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        volatileElementIds: const <String>{},
        documentVersion: 30,
        textRenderingCacheRevision: 1,
      ),
      3,
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        volatileElementIds: const <String>{},
        documentVersion: 30,
        textRenderingCacheRevision: 2,
      ),
      3,
    );
  });

  test(
    'invalidates full-scene cache when segment element instances change',
    () {
      final cache = InteractionSceneCache();
      final firstFrame = _buildScene(
        volatileRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
      );
      expect(
        _paintFrame(
          cache: cache,
          elements: firstFrame,
          volatileElementIds: const <String>{},
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
          volatileElementIds: const <String>{},
          documentVersion: 40,
          textRenderingCacheRevision: 0,
        ),
        3,
      );
    },
  );

  test('rebuilds segment layout when volatile ids change', () {
    final cache = InteractionSceneCache();
    final elements = _buildScene(
      volatileRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        volatileElementIds: const {'volatile'},
        documentVersion: 50,
        textRenderingCacheRevision: 0,
      ),
      3,
    );

    expect(
      _paintFrame(
        cache: cache,
        elements: elements,
        volatileElementIds: const {'static_2'},
        documentVersion: 50,
        textRenderingCacheRevision: 0,
      ),
      3,
    );
  });
}

List<ElementState> _buildScene({required DrawRect volatileRect}) => [
  const ElementState(
    id: 'static_1',
    rect: DrawRect(maxX: 10, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  ),
  ElementState(
    id: 'volatile',
    rect: volatileRect,
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
  required InteractionSceneCache cache,
  required List<ElementState> elements,
  required Set<String> volatileElementIds,
  required int documentVersion,
  required int textRenderingCacheRevision,
}) {
  var paintCount = 0;
  _paintOnFreshCanvas((canvas) {
    cache.paint(
      canvas: canvas,
      elements: elements,
      volatileElementIds: volatileElementIds,
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
