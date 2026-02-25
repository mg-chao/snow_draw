import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/highlight_mask_painter.dart';

const _deg45 = 0.7853981633974483;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('highlight mask clears holes for highlight shapes', () async {
    final bytes = await _paintHighlightMaskBytes(
      elements: const [
        ElementState(
          id: 'h1',
          rect: DrawRect(minX: 5, minY: 5, maxX: 15, maxY: 15),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(),
        ),
      ],
      width: 20,
      height: 20,
    );

    expect(_alphaAt(bytes, width: 20, x: 1, y: 1), 255);
    expect(_alphaAt(bytes, width: 20, x: 10, y: 10), 0);
  });

  test('overlapping highlights keep overlap region transparent', () async {
    final bytes = await _paintHighlightMaskBytes(
      elements: const [
        ElementState(
          id: 'h1',
          rect: DrawRect(minX: 4, minY: 4, maxX: 14, maxY: 14),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(),
        ),
        ElementState(
          id: 'h2',
          rect: DrawRect(minX: 10, minY: 4, maxX: 20, maxY: 14),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: HighlightData(),
        ),
      ],
      width: 24,
      height: 24,
    );

    expect(_alphaAt(bytes, width: 24, x: 12, y: 8), 0);
  });

  test(
    'highlight mask culling keeps rotated highlights near viewport edge',
    () async {
      final bytes = await _paintHighlightMaskBytes(
        elements: const [
          ElementState(
            id: 'h2',
            rect: DrawRect(minX: -8, maxX: -0.5, maxY: 8),
            rotation: _deg45,
            opacity: 1,
            zIndex: 0,
            data: HighlightData(),
          ),
        ],
        width: 20,
        height: 20,
      );

      expect(_alphaAt(bytes, width: 20, x: 0, y: 4), lessThan(255));
    },
  );
}

Future<ByteData> _paintHighlightMaskBytes({
  required List<ElementState> elements,
  required int width,
  required int height,
}) async {
  final initial = DrawState.initial();
  final state = DrawState(
    domain: initial.domain.copyWith(
      document: initial.domain.document.copyWith(elements: elements),
    ),
    application: initial.application.copyWith(interaction: const IdleState()),
  );
  final view = DrawStateView.fromState(state);
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  paintHighlightMask(
    canvas: canvas,
    highlights: view.highlightMaskScene.elements,
    viewportRect: DrawRect(maxX: width.toDouble(), maxY: height.toDouble()),
    maskConfig: const HighlightMaskConfig(maskOpacity: 1),
  );

  final image = await recorder.endRecording().toImage(width, height);
  final bytes = await image.toByteData();
  expect(bytes, isNotNull);
  return bytes!;
}

int _alphaAt(
  ByteData bytes, {
  required int width,
  required int x,
  required int y,
}) => bytes.getUint8(((y * width) + x) * 4 + 3);
