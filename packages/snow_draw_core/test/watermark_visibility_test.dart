import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/ui/canvas/watermark_visibility.dart';

void main() {
  test('isWatermarkVisible returns false for whitespace-only text', () {
    expect(isWatermarkVisible(const WatermarkConfig(text: '   ')), isFalse);
  });

  test('isWatermarkVisible returns false for imperceptible alpha', () {
    expect(
      isWatermarkVisible(
        const WatermarkConfig(text: 'CONFIDENTIAL', opacity: 0.001),
      ),
      isFalse,
    );
  });

  test('isWatermarkVisible returns true for visible watermark config', () {
    expect(
      isWatermarkVisible(const WatermarkConfig(text: 'CONFIDENTIAL')),
      isTrue,
    );
  });

  test('watermark layer resolves to none when text is empty', () {
    final layer = resolveWatermarkLayer(
      hasDynamicContent: false,
      config: const WatermarkConfig(),
    );
    expect(layer, WatermarkLayer.none);
  });

  test('watermark layer resolves to none when opacity is zero', () {
    final layer = resolveWatermarkLayer(
      hasDynamicContent: false,
      config: const WatermarkConfig(text: 'CONFIDENTIAL', opacity: 0),
    );
    expect(layer, WatermarkLayer.none);
  });

  test('watermark layer resolves to static without dynamic content', () {
    final layer = resolveWatermarkLayer(
      hasDynamicContent: false,
      config: const WatermarkConfig(text: 'CONFIDENTIAL'),
    );
    expect(layer, WatermarkLayer.staticLayer);
  });

  test('watermark layer resolves to dynamic with dynamic content', () {
    final layer = resolveWatermarkLayer(
      hasDynamicContent: true,
      config: const WatermarkConfig(text: 'CONFIDENTIAL'),
    );
    expect(layer, WatermarkLayer.dynamicLayer);
  });
}
