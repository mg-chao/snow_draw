import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('ArrowBindingUtils candidate tie-break', () {
    test(
      'resolveBindingCandidate stays deterministic for equal score and z-index',
      () {
        final targets = _overlappingTargets();
        const point = DrawPoint(x: 50, y: 50);

        final resultFromAB = ArrowBindingUtils.resolveBindingCandidate(
          worldPoint: point,
          targets: targets,
          snapDistance: 24,
        );
        final resultFromBA = ArrowBindingUtils.resolveBindingCandidate(
          worldPoint: point,
          targets: targets.reversed,
          snapDistance: 24,
        );

        expect(resultFromAB, isNotNull);
        expect(resultFromBA, isNotNull);
        expect(resultFromAB!.binding.elementId, 'a');
        expect(resultFromBA!.binding.elementId, 'a');
      },
    );

    test(
      'resolveElbowBindingCandidate is deterministic for equal candidates',
      () {
        final targets = _overlappingTargets();
        const point = DrawPoint(x: 50, y: 50);

        final resultFromAB = ArrowBindingUtils.resolveElbowBindingCandidate(
          worldPoint: point,
          targets: targets,
          snapDistance: 24,
          hasArrowhead: false,
        );
        final resultFromBA = ArrowBindingUtils.resolveElbowBindingCandidate(
          worldPoint: point,
          targets: targets.reversed,
          snapDistance: 24,
          hasArrowhead: false,
        );

        expect(resultFromAB, isNotNull);
        expect(resultFromBA, isNotNull);
        expect(resultFromAB!.binding.elementId, 'a');
        expect(resultFromBA!.binding.elementId, 'a');
      },
    );
  });
}

List<ElementState> _overlappingTargets() => const [
  ElementState(
    id: 'a',
    rect: DrawRect(minX: 20, minY: 20, maxX: 100, maxY: 100),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  ),
  ElementState(
    id: 'b',
    rect: DrawRect(minX: 20, minY: 20, maxX: 100, maxY: 100),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  ),
];
