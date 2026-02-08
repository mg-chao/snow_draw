import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('draw config provides highlight defaults', () {
    final config = DrawConfig();

    expect(config.highlightStyle.color, ConfigDefaults.defaultHighlightColor);
    expect(
      config.highlightStyle.textStrokeColor,
      ConfigDefaults.defaultHighlightColor,
    );
    expect(config.highlightStyle.textStrokeWidth, 0);
    expect(config.highlightStyle.highlightShape, HighlightShape.rectangle);

    expect(config.highlight.maskColor, ConfigDefaults.defaultMaskColor);
    expect(config.highlight.maskOpacity, 0);
  });
}
