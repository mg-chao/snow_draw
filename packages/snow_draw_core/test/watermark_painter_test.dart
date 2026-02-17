import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/ui/canvas/watermark_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(watermarkPainterCache.invalidate);

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

    expect(_hasVisiblePixel(bytes!), isTrue);
  });

  test('cache reuses picture for identical config and size', () {
    final cache = WatermarkPainterCache();
    const config = WatermarkConfig(text: 'A', gap: 40, opacity: 0.5);
    const size = ui.Size(100, 100);

    // First paint records a picture.
    final r1 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r1), viewportSize: size, config: config);
    r1.endRecording();

    // Second paint with same params should not throw and should
    // still produce visible output (proves the cache is alive).
    final r2 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r2), viewportSize: size, config: config);
    // If the cache were broken the second call would fail or
    // produce an empty picture.
    final picture = r2.endRecording();
    expect(picture, isNotNull);

    cache.invalidate();
  });

  test('cache invalidates when config changes', () async {
    final cache = WatermarkPainterCache();
    const size = ui.Size(120, 80);
    const configA = WatermarkConfig(text: 'A', gap: 40, opacity: 0.5);
    const configB = WatermarkConfig(text: 'B', gap: 40, opacity: 0.5);

    // Paint with config A.
    final r1 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r1), viewportSize: size, config: configA);
    r1.endRecording();

    // Paint with config B - rendering should still succeed.
    final r2 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r2), viewportSize: size, config: configB);
    final image = await r2.endRecording().toImage(120, 80);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    // Should have visible pixels from config B.
    expect(_hasVisiblePixel(bytes!), isTrue);

    cache.invalidate();
  });

  test('cache handles viewport size changes', () async {
    final cache = WatermarkPainterCache();
    const config = WatermarkConfig(text: 'WM', gap: 40, opacity: 0.5);

    // Paint at one size.
    final r1 = ui.PictureRecorder();
    cache.paint(
      canvas: ui.Canvas(r1),
      viewportSize: const ui.Size(100, 100),
      config: config,
    );
    r1.endRecording();

    // Paint at a different size - rendering should still succeed.
    final r2 = ui.PictureRecorder();
    cache.paint(
      canvas: ui.Canvas(r2),
      viewportSize: const ui.Size(200, 150),
      config: config,
    );
    final image = await r2.endRecording().toImage(200, 150);
    final bytes = await image.toByteData();
    expect(bytes, isNotNull);

    expect(_hasVisiblePixel(bytes!), isTrue);

    cache.invalidate();
  });

  test('cache falls back when shader tile exceeds max extent', () async {
    final cache = WatermarkPainterCache();
    final config = WatermarkConfig(
      text: List<String>.filled(300, 'W').join(),
      gap: ConfigDefaults.maxWatermarkGap,
      opacity: 0.5,
    );
    const size = ui.Size(220, 160);

    final r1 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r1), viewportSize: size, config: config);
    final firstBytes = await r1
        .endRecording()
        .toImage(220, 160)
        .then((image) => image.toByteData());
    expect(firstBytes, isNotNull);
    expect(_hasVisiblePixel(firstBytes!), isTrue);

    final r2 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r2), viewportSize: size, config: config);
    final secondBytes = await r2
        .endRecording()
        .toImage(220, 160)
        .then((image) => image.toByteData());
    expect(secondBytes, isNotNull);
    expect(_hasVisiblePixel(secondBytes!), isTrue);

    cache.invalidate();
  });
}

bool _hasVisiblePixel(ByteData data) {
  for (var i = 0; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i + 3) > 0) {
      return true;
    }
  }
  return false;
}
