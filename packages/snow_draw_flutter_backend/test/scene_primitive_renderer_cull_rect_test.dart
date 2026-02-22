import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/scene/scene_primitive_renderer.dart';

void main() {
  test('cull rect skips rendering when scene is fully rejected', () async {
    const scene = RenderScene(
      cullRect: DrawRect(minX: 100, minY: 100, maxX: 120, maxY: 120),
      primitives: <RenderPrimitive>[
        RenderPathFillPrimitive(
          path: RenderPath(<RenderPathCommand>[
            RenderMoveTo(DrawPoint.zero),
            RenderLineTo(DrawPoint(x: 8, y: 0)),
            RenderLineTo(DrawPoint(x: 8, y: 8)),
            RenderLineTo(DrawPoint(x: 0, y: 8)),
            RenderClosePath(),
          ]),
          colorArgb: 0xFF00FF00,
        ),
      ],
    );

    final pixel = await _renderAndReadPixel(scene: scene, x: 4, y: 4);

    expect(pixel.a, 0);
  });

  test('cull rect keeps thick stroke visible near viewport edge', () async {
    const scene = RenderScene(
      cullRect: DrawRect(minX: -1, minY: 0, maxX: -1, maxY: 8),
      primitives: <RenderPrimitive>[
        RenderPathStrokePrimitive(
          path: RenderPath(<RenderPathCommand>[
            RenderMoveTo(DrawPoint(x: -1, y: 0)),
            RenderLineTo(DrawPoint(x: -1, y: 8)),
          ]),
          colorArgb: 0xFFFFFFFF,
          strokeWidth: 4,
        ),
      ],
    );

    final pixel = await _renderAndReadPixel(scene: scene, x: 0, y: 4);

    expect(pixel.a, greaterThan(0));
  });
}

Future<_Rgba> _renderAndReadPixel({
  required RenderScene scene,
  required int x,
  required int y,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..clipRect(const ui.Rect.fromLTWH(0, 0, 8, 8));

  const ScenePrimitiveRenderer().renderScene(canvas: canvas, scene: scene);

  final image = recorder.endRecording().toImageSync(8, 8);
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    expect(byteData, isNotNull);
    return _readRgbaPixel(byteData!, x: x, y: y, width: 8);
  } finally {
    image.dispose();
  }
}

_Rgba _readRgbaPixel(
  ByteData data, {
  required int x,
  required int y,
  required int width,
}) {
  final index = (y * width + x) * 4;
  return _Rgba(
    r: data.getUint8(index),
    g: data.getUint8(index + 1),
    b: data.getUint8(index + 2),
    a: data.getUint8(index + 3),
  );
}

final class _Rgba {
  const _Rgba({
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  final int r;
  final int g;
  final int b;
  final int a;
}
