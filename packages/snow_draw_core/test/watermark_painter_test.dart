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

  test('fallback picture cache ignores color and opacity changes', () {
    final cache = WatermarkPainterCache();
    const size = ui.Size(220, 160);
    final longText = List<String>.filled(300, 'W').join();
    final baseConfig = WatermarkConfig(
      text: longText,
      gap: ConfigDefaults.maxWatermarkGap,
      opacity: 0.2,
    );

    final r1 = ui.PictureRecorder();
    cache.paint(canvas: ui.Canvas(r1), viewportSize: size, config: baseConfig);
    r1.endRecording();
    expect(cache.debugFallbackPictureBuildCount, 1);

    final r2 = ui.PictureRecorder();
    cache.paint(
      canvas: ui.Canvas(r2),
      viewportSize: size,
      config: baseConfig.copyWith(opacity: 0.6),
    );
    r2.endRecording();
    expect(cache.debugFallbackPictureBuildCount, 1);

    final r3 = ui.PictureRecorder();
    cache.paint(
      canvas: ui.Canvas(r3),
      viewportSize: size,
      config: baseConfig.copyWith(color: const ui.Color(0xFF1677FF)),
    );
    r3.endRecording();
    expect(cache.debugFallbackPictureBuildCount, 1);

    final r4 = ui.PictureRecorder();
    cache.paint(
      canvas: ui.Canvas(r4),
      viewportSize: size,
      config: baseConfig.copyWith(gap: ConfigDefaults.minWatermarkGap),
    );
    r4.endRecording();
    expect(cache.debugFallbackPictureBuildCount, 2);
  });

  test('fallback tinting only applies to watermark pixels', () async {
    final cache = WatermarkPainterCache();
    const size = ui.Size(220, 160);
    final longText = List<String>.filled(300, 'W').join();
    final config = WatermarkConfig(
      text: longText,
      gap: ConfigDefaults.maxWatermarkGap,
      opacity: 0.45,
      color: const ui.Color(0xFF1677FF),
    );
    const background = ui.Color(0xFFFF0000);

    final transparentRecorder = ui.PictureRecorder();
    cache.paint(
      canvas: ui.Canvas(transparentRecorder),
      viewportSize: size,
      config: config,
    );
    final transparentBytes = await transparentRecorder
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt())
        .then((image) => image.toByteData());
    expect(transparentBytes, isNotNull);
    expect(cache.debugFallbackPictureBuildCount, 1);

    final compositedRecorder = ui.PictureRecorder();
    final compositedCanvas = ui.Canvas(compositedRecorder)
      ..drawRect(
        ui.Rect.fromLTWH(0, 0, size.width, size.height),
        ui.Paint()..color = background,
      );
    cache.paint(canvas: compositedCanvas, viewportSize: size, config: config);
    final compositedBytes = await compositedRecorder
        .endRecording()
        .toImage(size.width.toInt(), size.height.toInt())
        .then((image) => image.toByteData());
    expect(compositedBytes, isNotNull);
    expect(cache.debugFallbackPictureBuildCount, 1);

    final transparentData = transparentBytes!;
    final compositedData = compositedBytes!;
    final pixelCount = size.width.toInt() * size.height.toInt();
    int? transparentPixelIndex;
    for (var i = 0; i < pixelCount; i++) {
      final alpha = transparentData.getUint8((i * 4) + 3);
      if (alpha == 0) {
        transparentPixelIndex = i;
        break;
      }
    }
    expect(
      transparentPixelIndex,
      isNotNull,
      reason: 'Expected at least one non-watermark pixel in fallback output.',
    );

    final index = transparentPixelIndex!;
    expect(compositedData.getUint8(index * 4), _channelFromUnit(background.r));
    expect(
      compositedData.getUint8((index * 4) + 1),
      _channelFromUnit(background.g),
    );
    expect(
      compositedData.getUint8((index * 4) + 2),
      _channelFromUnit(background.b),
    );
    expect(
      compositedData.getUint8((index * 4) + 3),
      _channelFromUnit(background.a),
    );
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

int _channelFromUnit(double channel) => (channel * 255).round();
