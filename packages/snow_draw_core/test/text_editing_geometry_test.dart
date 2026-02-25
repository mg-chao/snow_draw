import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_editing_geometry.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  test('resolveTextEditingGeometry stays in sync with rect helper', () {
    const data = TextData(text: 'Geometry Probe', autoResize: false);
    const origin = DrawPoint(x: 24, y: 32);
    const currentRect = DrawRect(minX: 24, minY: 32, maxX: 184, maxY: 80);

    final geometry = resolveTextEditingGeometry(
      origin: origin,
      currentRect: currentRect,
      data: data,
      allowShrinkHeight: true,
    );
    final rect = resolveTextEditingRect(
      origin: origin,
      currentRect: currentRect,
      data: data,
      allowShrinkHeight: true,
    );

    expect(geometry.rect, rect);
    expect(geometry.layout.height, greaterThan(0));
    expect(geometry.layout.lineHeight, greaterThan(0));
  });

  test('initial and auto-resize geometry wrappers mirror rect helpers', () {
    const data = TextData(text: 'A\nB');
    const position = DrawPoint(x: 10, y: 12);

    final initialGeometry = resolveInitialTextEditingGeometry(
      position: position,
      data: data,
    );
    final initialRect = resolveInitialTextEditingRect(
      position: position,
      data: data,
    );
    expect(initialGeometry.rect, initialRect);

    final autoResizeGeometry = resolveAutoResizeTextEditingGeometry(
      origin: position,
      data: data,
    );
    final autoResizeRect = resolveAutoResizeTextEditingRect(
      origin: position,
      data: data,
    );
    expect(autoResizeGeometry.rect, autoResizeRect);
    expect(autoResizeGeometry.layout.width, greaterThan(0));
  });
}
