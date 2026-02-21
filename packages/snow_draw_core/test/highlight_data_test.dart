import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';

void main() {
  test('HighlightData.fromJson uses defaults', () {
    final data = HighlightData.fromJson(const {});

    expect(data.shape, ConfigDefaults.defaultHighlightShape);
    expect(data.color, ConfigDefaults.defaultHighlightColor);
    expect(data.strokeColor, ConfigDefaults.defaultHighlightStrokeColor);
    expect(data.strokeWidth, 0);
  });

  test('HighlightData.fromJson decodes supported shape names', () {
    final rectangle = HighlightData.fromJson(const {'shape': 'rectangle'});
    final ellipse = HighlightData.fromJson(const {'shape': 'ellipse'});

    expect(rectangle.shape, HighlightShape.rectangle);
    expect(ellipse.shape, HighlightShape.ellipse);
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
