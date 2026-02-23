import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/highlight_mask_static_scene_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses cached static mask picture for stable interaction frames', () {
    var renderCount = 0;
    final cache = _buildCache(() => renderCount += 1);
    final document = DocumentState(elements: const [_highlightOne]);

    _paintMaskFrame(
      cache: cache,
      document: document,
      staticHighlights: const [_highlightOne],
      excludedDocumentHighlightIds: const {'h1'},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.45),
    );
    _paintMaskFrame(
      cache: cache,
      document: document,
      staticHighlights: const [_highlightOne],
      excludedDocumentHighlightIds: const {'h1'},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.45),
    );

    expect(renderCount, 1);
  });

  test('rebuilds cached picture when excluded highlight ids change', () {
    var renderCount = 0;
    final cache = _buildCache(() => renderCount += 1);
    final document = DocumentState(
      elements: const [_highlightOne, _highlightTwo],
    );

    _paintMaskFrame(
      cache: cache,
      document: document,
      staticHighlights: const [_highlightOne],
      excludedDocumentHighlightIds: const {'h1'},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.45),
    );
    _paintMaskFrame(
      cache: cache,
      document: document,
      staticHighlights: const [_highlightOne],
      excludedDocumentHighlightIds: const {'h2'},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.45),
    );

    expect(renderCount, 2);
  });

  test('rebuilds cached picture when mask config changes', () {
    var renderCount = 0;
    final cache = _buildCache(() => renderCount += 1);
    final document = DocumentState(elements: const [_highlightOne]);

    _paintMaskFrame(
      cache: cache,
      document: document,
      staticHighlights: const [_highlightOne],
      excludedDocumentHighlightIds: const {'h1'},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.35),
    );
    _paintMaskFrame(
      cache: cache,
      document: document,
      staticHighlights: const [_highlightOne],
      excludedDocumentHighlightIds: const {'h1'},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.75),
    );

    expect(renderCount, 2);
  });

  test('returns false without static highlights', () {
    final cache = HighlightMaskStaticSceneCache();
    final painted = _paintMaskFrame(
      cache: cache,
      document: DocumentState(),
      staticHighlights: const <ElementState>[],
      excludedDocumentHighlightIds: const <String>{},
      maskConfig: const HighlightMaskConfig(maskOpacity: 0.6),
    );

    expect(painted, isFalse);
  });
}

HighlightMaskStaticSceneCache _buildCache(void Function() onRender) =>
    HighlightMaskStaticSceneCache(
      renderMask:
          ({
            required canvas,
            required highlights,
            required viewportRect,
            required maskConfig,
            required scaleFactor,
            required cameraPosition,
          }) {
            onRender();
            canvas.drawRect(
              const ui.Rect.fromLTWH(0, 0, 1, 1),
              ui.Paint()..color = const ui.Color(0xFF000000),
            );
          },
    );

bool _paintMaskFrame({
  required HighlightMaskStaticSceneCache cache,
  required DocumentState document,
  required List<ElementState> staticHighlights,
  required Set<String> excludedDocumentHighlightIds,
  required HighlightMaskConfig maskConfig,
}) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final painted = cache.paint(
    canvas: canvas,
    document: document,
    staticHighlights: staticHighlights,
    excludedDocumentHighlightIds: excludedDocumentHighlightIds,
    viewportRect: const DrawRect(maxX: 200, maxY: 120),
    maskConfig: maskConfig,
    scaleFactor: 1,
    cameraPosition: ui.Offset.zero,
  );
  recorder.endRecording().dispose();
  return painted;
}

const _highlightOne = ElementState(
  id: 'h1',
  rect: DrawRect(minX: 10, minY: 10, maxX: 40, maxY: 30),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: HighlightData(),
);

const _highlightTwo = ElementState(
  id: 'h2',
  rect: DrawRect(minX: 60, minY: 12, maxX: 90, maxY: 32),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: HighlightData(),
);
