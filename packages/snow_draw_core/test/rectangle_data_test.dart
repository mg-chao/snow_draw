import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('RectangleData.fromJson requires canonical payload fields', () {
    expect(
      () => RectangleData.fromJson(const {}),
      throwsA(anyOf(isA<TypeError>(), isA<FormatException>())),
    );
  });

  test('RectangleData.fromJson rejects invalid enum values', () {
    expect(
      () => RectangleData.fromJson({
        'cornerRadius': ConfigDefaults.defaultCornerRadius,
        'fillColor': ConfigDefaults.defaultFillColor.toARGB32(),
        'color': ConfigDefaults.defaultColor.toARGB32(),
        'strokeWidth': ConfigDefaults.defaultStrokeWidth,
        'strokeStyle': 'invalid',
        'fillStyle': 'invalid',
      }),
      throwsA(isA<FormatException>()),
    );
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
