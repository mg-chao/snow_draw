import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/utils/binding_highlight_visibility.dart';

void main() {
  test('hovered arrow handles suppress binding highlight', () {
    const handle = ArrowPointHandle(
      elementId: 'arrow',
      kind: ArrowPointKind.turning,
      index: 0,
      position: DrawPoint.zero,
    );

    expect(
      resolveHoverBindingHighlightId(
        hoveredBindingElementId: 'rect',
        hoveredArrowHandle: handle,
      ),
      isNull,
    );
  });

  test('binding highlight stays when no arrow handle is hovered', () {
    expect(
      resolveHoverBindingHighlightId(
        hoveredBindingElementId: 'rect',
        hoveredArrowHandle: null,
      ),
      'rect',
    );
  });
}
