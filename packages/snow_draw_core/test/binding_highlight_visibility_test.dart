import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/utils/binding_highlight_visibility.dart';

void main() {
  test('hovered arrow handles suppress binding highlight', () {
    final handle = ArrowPointHandle(
      elementId: 'arrow',
      kind: ArrowPointKind.turning,
      index: 0,
      position: DrawPoint.zero,
    );

    final result = resolveHoverBindingHighlightId(
      hoveredBindingElementId: 'rect',
      hoveredArrowHandle: handle,
    );

    expect(result, isNull);
  });

  test('binding highlight stays when no arrow handle is hovered', () {
    final result = resolveHoverBindingHighlightId(
      hoveredBindingElementId: 'rect',
      hoveredArrowHandle: null,
    );

    expect(result, 'rect');
  });
}
