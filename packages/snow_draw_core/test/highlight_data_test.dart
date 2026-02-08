import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('HighlightData.fromJson uses defaults', () {
    final data = HighlightData.fromJson(const {});

    expect(data.shape, ConfigDefaults.defaultHighlightShape);
    expect(data.color, ConfigDefaults.defaultHighlightColor);
    expect(data.strokeColor, ConfigDefaults.defaultHighlightColor);
    expect(data.strokeWidth, 0);
  });

  test('HighlightData.withElementStyle applies highlight style fields', () {
    const style = ElementStyleConfig(
      color: Color(0xFF00FF00),
      textStrokeColor: Color(0xFF0000FF),
      textStrokeWidth: 3,
      highlightShape: HighlightShape.ellipse,
    );

    const data = HighlightData();
    final updated = data.withElementStyle(style) as HighlightData;

    expect(updated.color, style.color);
    expect(updated.strokeColor, style.textStrokeColor);
    expect(updated.strokeWidth, style.textStrokeWidth);
    expect(updated.shape, style.highlightShape);
  });
}
