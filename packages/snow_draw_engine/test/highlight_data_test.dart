import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/types/draw_color.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  test('HighlightData.fromJson requires canonical payload fields', () {
    expect(
      () => HighlightData.fromJson(const {}),
      throwsA(anyOf(isA<TypeError>(), isA<FormatException>())),
    );
  });

  test('HighlightData.fromJson decodes supported shape names', () {
    final rectangle = HighlightData.fromJson(const {
      'shape': 'rectangle',
      'color': 0xFFF5222D,
      'strokeColor': 0xFF000000,
      'strokeWidth': 0.0,
    });
    final ellipse = HighlightData.fromJson(const {
      'shape': 'ellipse',
      'color': 0xFFF5222D,
      'strokeColor': 0xFF000000,
      'strokeWidth': 0.0,
    });

    expect(rectangle.shape, HighlightShape.rectangle);
    expect(ellipse.shape, HighlightShape.ellipse);
  });

  test('HighlightData.fromJson rejects unsupported shape names', () {
    expect(
      () => HighlightData.fromJson(const {
        'shape': 'triangle',
        'color': 0xFFF5222D,
        'strokeColor': 0xFF000000,
        'strokeWidth': 0.0,
      }),
      throwsA(isA<FormatException>()),
    );
  });

  test('HighlightData.withElementStyle applies highlight style fields', () {
    const style = ElementStyleConfig(
      color: DrawColor(0xFF00FF00),
      textStrokeColor: DrawColor(0xFF0000FF),
      textStrokeWidth: 3,
      highlightShape: HighlightShape.ellipse,
    );

    expect(
      const HighlightData().withElementStyle(style),
      const HighlightData(
        shape: HighlightShape.ellipse,
        color: DrawColor(0xFF00FF00),
        strokeColor: DrawColor(0xFF0000FF),
        strokeWidth: 3,
      ),
    );
  });

  test('HighlightData.withStyleUpdate applies highlight shape and strokes', () {
    const update = ElementStyleUpdate(
      color: DrawColor(0xFF112233),
      textStrokeColor: DrawColor(0xFF445566),
      textStrokeWidth: 4,
      highlightShape: HighlightShape.ellipse,
    );

    expect(
      const HighlightData().withStyleUpdate(update),
      const HighlightData(
        shape: HighlightShape.ellipse,
        color: DrawColor(0xFF112233),
        strokeColor: DrawColor(0xFF445566),
        strokeWidth: 4,
      ),
    );
  });
}
