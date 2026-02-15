import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/models/global_elements_state.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('draw config provides highlight style defaults', () {
    final config = DrawConfig();

    expect(config.highlightStyle.color, ConfigDefaults.defaultHighlightColor);
    expect(
      config.highlightStyle.textStrokeColor,
      ConfigDefaults.defaultHighlightStrokeColor,
    );
    expect(config.highlightStyle.textStrokeWidth, 0);
    expect(config.highlightStyle.highlightShape, HighlightShape.rectangle);
  });

  test('global elements provide highlight mask and watermark defaults', () {
    const globals = GlobalElementsState();

    expect(globals.highlightMask.maskColor, ConfigDefaults.defaultMaskColor);
    expect(globals.highlightMask.maskOpacity, 0);
    expect(globals.watermark.color, ConfigDefaults.defaultWatermarkColor);
    expect(globals.watermark.text, ConfigDefaults.defaultWatermarkText);
    expect(globals.watermark.fontSize, ConfigDefaults.defaultWatermarkFontSize);
    expect(globals.watermark.fontSize, 16);
    expect(
      globals.watermark.fontFamily,
      ConfigDefaults.defaultWatermarkFontFamily,
    );
    expect(globals.watermark.angle, ConfigDefaults.defaultWatermarkAngle);
    expect(globals.watermark.gap, ConfigDefaults.defaultWatermarkGap);
    expect(
      globals.watermark.gap,
      inInclusiveRange(
        ConfigDefaults.minWatermarkGap,
        ConfigDefaults.maxWatermarkGap,
      ),
    );
    expect(globals.watermark.opacity, ConfigDefaults.defaultWatermarkOpacity);
    expect(globals.watermark.opacity, 0.16);
  });

  test('watermark config enforces minimum gap', () {
    expect(
      () => WatermarkConfig(gap: ConfigDefaults.minWatermarkGap - 1),
      throwsA(isA<AssertionError>()),
    );
  });
}
