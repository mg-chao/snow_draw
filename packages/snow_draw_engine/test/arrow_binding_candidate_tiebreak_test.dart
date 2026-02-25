import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowBindingUtils candidate tie-break', () {
    test(
      'resolveBindingCandidate stays deterministic for equal score and z-index',
      () {
        _expectStableWinner(
          (targets) => ArrowBindingUtils.resolveBindingCandidate(
            worldPoint: _testPoint,
            targets: targets,
            snapDistance: _snapDistance,
          ),
        );
      },
    );

    test(
      'resolveElbowBindingCandidate is deterministic for equal candidates',
      () {
        _expectStableWinner(
          (targets) => ArrowBindingUtils.resolveElbowBindingCandidate(
            worldPoint: _testPoint,
            targets: targets,
            snapDistance: _snapDistance,
            hasArrowhead: false,
          ),
        );
      },
    );
  });
}

const _testPoint = DrawPoint(x: 50, y: 50);
const _snapDistance = 24.0;

void _expectStableWinner(
  ArrowBindingResult? Function(Iterable<ElementState> targets) resolve,
) {
  final targets = _overlappingTargets();

  final resultFromAB = resolve(targets);
  final resultFromBA = resolve(targets.reversed);

  expect(resultFromAB?.binding.elementId, 'a');
  expect(resultFromBA?.binding.elementId, 'a');
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
