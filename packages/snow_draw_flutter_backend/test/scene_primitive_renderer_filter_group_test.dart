import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/scene/scene_primitive_renderer.dart';

void main() {
  test('blend_multiply filter group applies multiply compositing', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawRect(
        const ui.Rect.fromLTWH(0, 0, 4, 4),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );

    const scene = RenderScene(
      primitives: <RenderPrimitive>[
        RenderBlendMultiplyGroupPrimitive(
          child: RenderScene(
            primitives: <RenderPrimitive>[
              RenderPathFillPrimitive(
                path: RenderPath(<RenderPathCommand>[
                  RenderMoveTo(DrawPoint.zero),
                  RenderLineTo(DrawPoint(x: 4, y: 0)),
                  RenderLineTo(DrawPoint(x: 4, y: 4)),
                  RenderLineTo(DrawPoint(x: 0, y: 4)),
                  RenderClosePath(),
                ]),
                colorArgb: 0xFF00FF00,
              ),
            ],
          ),
        ),
      ],
    );

    const ScenePrimitiveRenderer().renderScene(canvas: canvas, scene: scene);

    final image = recorder.endRecording().toImageSync(4, 4);
    addTearDown(image.dispose);
    final byteData = await image.toByteData();
    expect(byteData, isNotNull);
    final pixel = _readRgbaPixel(byteData!, x: 2, y: 2, width: 4);
    expect(pixel.a, 255);
    expect(pixel.r, lessThanOrEqualTo(2));
    expect(pixel.g, lessThanOrEqualTo(2));
    expect(pixel.b, lessThanOrEqualTo(2));
  });
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
