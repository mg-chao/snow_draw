import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/models/global_elements_state.dart';
import 'package:test/test.dart';

void main() {
  test('draw config provides highlight style defaults', () {
    final highlightStyle = DrawConfig().highlightStyle;

    expect(highlightStyle.color, ConfigDefaults.defaultHighlightColor);
    expect(
      highlightStyle.textStrokeColor,
      ConfigDefaults.defaultHighlightStrokeColor,
    );
    expect(highlightStyle.textStrokeWidth, 0);
    expect(highlightStyle.highlightShape, ConfigDefaults.defaultHighlightShape);
  });

  test('global elements provide highlight mask and watermark defaults', () {
    const globals = GlobalElementsState();
    final highlightMask = globals.highlightMask;
    final watermark = globals.watermark;

    expect(highlightMask.maskColor, ConfigDefaults.defaultMaskColor);
    expect(highlightMask.maskOpacity, 0);
    expect(watermark.color, ConfigDefaults.defaultWatermarkColor);
    expect(watermark.text, ConfigDefaults.defaultWatermarkText);
    expect(watermark.fontSize, ConfigDefaults.defaultWatermarkFontSize);
    expect(watermark.fontFamily, ConfigDefaults.defaultWatermarkFontFamily);
    expect(watermark.angle, ConfigDefaults.defaultWatermarkAngle);
    expect(watermark.gap, ConfigDefaults.defaultWatermarkGap);
    expect(
      watermark.gap,
      inInclusiveRange(
        ConfigDefaults.minWatermarkGap,
        ConfigDefaults.maxWatermarkGap,
      ),
    );
    expect(watermark.opacity, ConfigDefaults.defaultWatermarkOpacity);
  });

  test('watermark config enforces minimum gap', () {
    expect(
      () => WatermarkConfig(gap: ConfigDefaults.minWatermarkGap - 1),
      throwsA(isA<AssertionError>()),
    );
  });
}
