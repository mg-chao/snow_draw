import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('RectangleData.fromJson uses defaults', () {
    final data = RectangleData.fromJson(const {});

    expect(data.cornerRadius, ConfigDefaults.defaultCornerRadius);
    expect(data.fillColor, ConfigDefaults.defaultFillColor);
    expect(data.color, ConfigDefaults.defaultColor);
    expect(data.strokeWidth, ConfigDefaults.defaultStrokeWidth);
    expect(data.strokeStyle, ConfigDefaults.defaultStrokeStyle);
    expect(data.fillStyle, ConfigDefaults.defaultFillStyle);
  });

  test('RectangleData.fromJson keeps legacy strokeColor fallback', () {
    final data = RectangleData.fromJson(const {'strokeColor': 0xFF123456});

    expect(data.color, const DrawColor(0xFF123456));
  });

  test('RectangleData.fromJson falls back for invalid enum values', () {
    final data = RectangleData.fromJson(const {
      'strokeStyle': 'invalid',
      'fillStyle': 'invalid',
    });

    expect(data.strokeStyle, ConfigDefaults.defaultStrokeStyle);
    expect(data.fillStyle, ConfigDefaults.defaultFillStyle);
  });

  test('RectangleData.withStyleUpdate keeps values not included in update', () {
    const data = RectangleData(
      cornerRadius: 10,
      fillColor: DrawColor(0xFF010203),
      color: DrawColor(0xFF0A0B0C),
      strokeWidth: 5,
      strokeStyle: StrokeStyle.dashed,
      fillStyle: FillStyle.crossLine,
    );

    const update = ElementStyleUpdate(strokeWidth: 3);
    final updated = data.withStyleUpdate(update) as RectangleData;

    expect(updated.strokeWidth, 3);
    expect(updated.cornerRadius, data.cornerRadius);
    expect(updated.fillColor, data.fillColor);
    expect(updated.color, data.color);
    expect(updated.strokeStyle, data.strokeStyle);
    expect(updated.fillStyle, data.fillStyle);
  });
}
