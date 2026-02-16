import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/highlight_interaction_scene_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reuses static segments across highlight edit frames', () {
    final cache = HighlightInteractionSceneCache();
    var paintCount = 0;

    final firstFrame = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    _paintOnFreshCanvas((canvas) {
      cache.paint(
        canvas: canvas,
        elements: firstFrame,
        dynamicElementIds: const {'dynamic'},
        documentVersion: 10,
        textRenderingCacheRevision: 0,
        scaleFactor: 1,
        locale: const ui.Locale('en'),
        paintElement: (_, _) => paintCount++,
      );
    });
    expect(paintCount, 3);

    paintCount = 0;
    final secondFrame = _buildScene(
      dynamicRect: const DrawRect(minX: 120, minY: 40, maxX: 150, maxY: 80),
    );
    _paintOnFreshCanvas((canvas) {
      cache.paint(
        canvas: canvas,
        elements: secondFrame,
        dynamicElementIds: const {'dynamic'},
        documentVersion: 10,
        textRenderingCacheRevision: 0,
        scaleFactor: 1,
        locale: const ui.Locale('en'),
        paintElement: (_, _) => paintCount++,
      );
    });

    // Only the dynamic preview element should be repainted on the second frame.
    expect(paintCount, 1);
  });

  test('reuses full scene picture when no dynamic element is present', () {
    final cache = HighlightInteractionSceneCache();
    var paintCount = 0;
    final elements = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );

    _paintOnFreshCanvas((canvas) {
      cache.paint(
        canvas: canvas,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 20,
        textRenderingCacheRevision: 0,
        scaleFactor: 1,
        locale: const ui.Locale('en'),
        paintElement: (_, _) => paintCount++,
      );
    });
    expect(paintCount, 3);

    paintCount = 0;
    _paintOnFreshCanvas((canvas) {
      cache.paint(
        canvas: canvas,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 20,
        textRenderingCacheRevision: 0,
        scaleFactor: 1,
        locale: const ui.Locale('en'),
        paintElement: (_, _) => paintCount++,
      );
    });
    expect(paintCount, 0);
  });

  test('invalidates cached segments when text cache revision changes', () {
    final cache = HighlightInteractionSceneCache();
    final elements = _buildScene(
      dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
    );
    var paintCount = 0;

    _paintOnFreshCanvas((canvas) {
      cache.paint(
        canvas: canvas,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 30,
        textRenderingCacheRevision: 1,
        scaleFactor: 1,
        locale: const ui.Locale('en'),
        paintElement: (_, _) => paintCount++,
      );
    });
    expect(paintCount, 3);

    paintCount = 0;
    _paintOnFreshCanvas((canvas) {
      cache.paint(
        canvas: canvas,
        elements: elements,
        dynamicElementIds: const <String>{},
        documentVersion: 30,
        textRenderingCacheRevision: 2,
        scaleFactor: 1,
        locale: const ui.Locale('en'),
        paintElement: (_, _) => paintCount++,
      );
    });
    expect(paintCount, 3);
  });

  test(
    'invalidates full-scene cache when segment element instances change',
    () {
      final cache = HighlightInteractionSceneCache();
      final firstFrame = _buildScene(
        dynamicRect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
      );
      var paintCount = 0;

      _paintOnFreshCanvas((canvas) {
        cache.paint(
          canvas: canvas,
          elements: firstFrame,
          dynamicElementIds: const <String>{},
          documentVersion: 40,
          textRenderingCacheRevision: 0,
          scaleFactor: 1,
          locale: const ui.Locale('en'),
          paintElement: (_, _) => paintCount++,
        );
      });
      expect(paintCount, 3);

      paintCount = 0;
      final secondFrame = <ElementState>[
        firstFrame[0],
        firstFrame[1].copyWith(
          rect: const DrawRect(minX: 60, maxX: 90, maxY: 10),
        ),
        firstFrame[2],
      ];
      _paintOnFreshCanvas((canvas) {
        cache.paint(
          canvas: canvas,
          elements: secondFrame,
          dynamicElementIds: const <String>{},
          documentVersion: 40,
          textRenderingCacheRevision: 0,
          scaleFactor: 1,
          locale: const ui.Locale('en'),
          paintElement: (_, _) => paintCount++,
        );
      });

      expect(paintCount, 3);
    },
  );
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

void _paintOnFreshCanvas(void Function(ui.Canvas canvas) paint) {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas);
  recorder.endRecording().dispose();
}
