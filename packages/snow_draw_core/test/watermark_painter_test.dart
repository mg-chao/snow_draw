import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/ui/canvas/watermark_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('watermark painter skips rendering when text is empty', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(80, 80);

    paintWatermark(
      canvas: canvas,
      viewportSize: size,
      config: const WatermarkConfig(),
    );

    final image = await recorder.endRecording().toImage(80, 80);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    final data = bytes!;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      expect(data.getUint8(i + 3), 0);
    }
  });

  test('watermark painter renders visible pixels when enabled', () async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    const size = ui.Size(180, 120);

    paintWatermark(
      canvas: canvas,
      viewportSize: size,
      config: const WatermarkConfig(text: 'WM', gap: 40, opacity: 0.6),
    );

    final image = await recorder.endRecording().toImage(180, 120);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    final data = bytes!;
    var hasVisiblePixel = false;
    for (var i = 0; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i + 3) > 0) {
        hasVisiblePixel = true;
        break;
      }
    }
    expect(hasVisiblePixel, isTrue);
  });
}
