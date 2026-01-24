import '../core/coordinates/element_space.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import 'calculators/create_calculator.dart';

/// Editing geometry facade.
///
/// `StateCalculator` used to contain all geometry logic. It now delegates to
/// specialized calculators while keeping the public API stable for reducers
/// and input handlers.
class StateCalculator {
  StateCalculator._();

  static DrawPoint rotatePointToLocal({
    required DrawPoint point,
    required DrawPoint center,
    required double rotation,
  }) {
    final space = ElementSpace(rotation: rotation, origin: center);
    return space.fromWorld(point);
  }

  static DrawPoint rotatePointFromLocal({
    required DrawPoint point,
    required DrawPoint center,
    required double rotation,
  }) {
    final space = ElementSpace(rotation: rotation, origin: center);
    return space.toWorld(point);
  }

  static List<ElementState> moveElements({
    required DrawState state,
    required double dx,
    required double dy,
  }) {
    final selectedIds = state.domain.selection.selectedIds;

    return state.domain.document.elements.map((element) {
      if (!selectedIds.contains(element.id)) {
        return element;
      }
      return element.movedBy(dx, dy);
    }).toList();
  }

  static DrawRect calculateCreateRect({
    required DrawPoint startPosition,
    required DrawPoint currentPosition,
    required bool maintainAspectRatio,
    required bool createFromCenter,
  }) => CreateCalculator.calculateCreateRect(
    startPosition: startPosition,
    currentPosition: currentPosition,
    maintainAspectRatio: maintainAspectRatio,
    createFromCenter: createFromCenter,
  );
}
