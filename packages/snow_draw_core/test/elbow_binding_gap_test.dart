import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test('elbow binding gap grows when an arrowhead is present', () {
    const rect = DrawRect(minX: 0, minY: 0, maxX: 200, maxY: 100);
    final element = ElementState(
      id: 'rect-1',
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(strokeWidth: 2),
    );
    const binding = ArrowBinding(
      elementId: 'rect-1',
      anchor: DrawPoint(x: 1, y: 0.5),
    );

    final anchor = ArrowBindingUtils.resolveElbowAnchorPoint(
      binding: binding,
      target: element,
    );
    final withoutArrowhead = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: binding,
      target: element,
      hasArrowhead: false,
    );
    final withArrowhead = ArrowBindingUtils.resolveElbowBoundPoint(
      binding: binding,
      target: element,
      hasArrowhead: true,
    );

    expect(anchor, isNotNull);
    expect(withoutArrowhead, isNotNull);
    expect(withArrowhead, isNotNull);

    final baseGap = ArrowBindingUtils.elbowBindingGapBase;
    final arrowGap =
        ArrowBindingUtils.elbowBindingGapBase *
        ArrowBindingUtils.elbowArrowheadGapMultiplier;

    final anchorPoint = anchor!;
    final noArrow = withoutArrowhead!;
    final withArrow = withArrowhead!;

    expect(noArrow.y, closeTo(anchorPoint.y, 1e-6));
    expect(withArrow.y, closeTo(anchorPoint.y, 1e-6));
    expect(noArrow.x - anchorPoint.x, closeTo(baseGap, 1e-6));
    expect(withArrow.x - anchorPoint.x, closeTo(arrowGap, 1e-6));
    expect(withArrow.x, greaterThan(noArrow.x));
  });
}
