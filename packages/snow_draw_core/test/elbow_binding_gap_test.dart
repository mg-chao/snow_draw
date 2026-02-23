import 'package:test/test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test('elbow binding gap grows when an arrowhead is present', () {
    const element = ElementState(
      id: 'rect-1',
      rect: DrawRect(maxX: 200, maxY: 100),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 1, y: 0.5),
    );

    final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
      binding: binding,
      target: element,
    )!;
    final withoutArrowhead = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: binding,
      target: element,
      hasArrowhead: false,
    )!;
    final withArrowhead = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: binding,
      target: element,
      hasArrowhead: true,
    )!;

    const baseGap = ArrowBindingUtils.elbowBindingGapBase;
    const arrowGap =
        ArrowBindingUtils.elbowBindingGapBase *
        ArrowBindingUtils.elbowArrowheadGapMultiplier;

    expect(withoutArrowhead.y, closeTo(anchor.y, 1e-6));
    expect(withArrowhead.y, closeTo(anchor.y, 1e-6));
    expect(withoutArrowhead.x - anchor.x, closeTo(baseGap, 1e-6));
    expect(withArrowhead.x - anchor.x, closeTo(arrowGap, 1e-6));
    expect(withArrowhead.x, greaterThan(withoutArrowhead.x));
  });
}
