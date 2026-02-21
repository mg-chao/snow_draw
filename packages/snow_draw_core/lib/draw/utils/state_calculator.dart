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
