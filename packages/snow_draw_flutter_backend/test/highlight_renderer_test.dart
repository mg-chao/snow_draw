import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

import 'package:snow_draw_flutter_backend/render/legacy/highlight_renderer.dart';

void main() {
  test('highlight renderer uses multiply blend', () async {
    final element = ElementState(
      id: 'h1',
      rect: const DrawRect(minX: 0, minY: 0, maxX: 20, maxY: 20),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const HighlightData(
        color: DrawColor(0x80FF0000),
        strokeColor: DrawColor(0x00000000),
        strokeWidth: 0,
        shape: HighlightShape.rectangle,
      ),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 20, 20),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    const HighlightRenderer().render(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
    );
    final image = await recorder.endRecording().toImage(20, 20);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    image.dispose();
    final pixel = bytes!.buffer.asUint8List();

    expect(pixel[0], 255);
    expect(pixel[1], lessThan(255));
    expect(pixel[2], lessThan(255));
  });

  test('highlight stroke does not use multiply blend', () async {
    final element = ElementState(
      id: 'h2',
      rect: const DrawRect(minX: 0, minY: 0, maxX: 20, maxY: 20),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const HighlightData(
        color: DrawColor(0x00000000),
        strokeColor: DrawColor(0xFF00FF00),
        strokeWidth: 2,
        shape: HighlightShape.rectangle,
      ),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 20, 20),
      Paint()..color = const Color(0xFFFFFFFF),
    );
    const HighlightRenderer().render(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
    );
    final image = await recorder.endRecording().toImage(20, 20);
    final bytes = await image.toByteData(format: ImageByteFormat.rawRgba);
    image.dispose();

    final pixel = bytes!.buffer.asUint8List();
    var hasGreenDominantPixel = false;
    for (var i = 0; i <= pixel.length - 4; i += 4) {
      final r = pixel[i];
      final g = pixel[i + 1];
      final b = pixel[i + 2];
      final a = pixel[i + 3];
      if (a > 0 && g > 150 && g > r && g > b) {
        hasGreenDominantPixel = true;
        break;
      }
    }

    expect(hasGreenDominantPixel, isTrue);
  });
}
