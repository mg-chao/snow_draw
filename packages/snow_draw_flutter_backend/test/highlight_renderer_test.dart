import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/highlight/highlight_renderer.dart';

void main() {
  test('highlight renderer uses multiply blend', () async {
    const element = ElementState(
      id: 'h1',
      rect: DrawRect(maxX: 20, maxY: 20),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(
        color: DrawColor(0x80FF0000),
        strokeColor: DrawColor(0x00000000),
      ),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 20, 20),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    const HighlightRenderer().render(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
    );
    final image = await recorder.endRecording().toImage(20, 20);
    final bytes = await image.toByteData();
    image.dispose();
    final pixel = bytes!.buffer.asUint8List();

    expect(pixel[0], 255);
    expect(pixel[1], lessThan(255));
    expect(pixel[2], lessThan(255));
  });

  test('highlight stroke does not use multiply blend', () async {
    const element = ElementState(
      id: 'h2',
      rect: DrawRect(maxX: 20, maxY: 20),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(
        color: DrawColor(0x00000000),
        strokeColor: DrawColor(0xFF00FF00),
        strokeWidth: 2,
      ),
    );

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(
        const Rect.fromLTWH(0, 0, 20, 20),
        Paint()..color = const Color(0xFFFFFFFF),
      );
    const HighlightRenderer().render(
      canvas: canvas,
      element: element,
      scaleFactor: 1,
    );
    final image = await recorder.endRecording().toImage(20, 20);
    final bytes = await image.toByteData();
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
