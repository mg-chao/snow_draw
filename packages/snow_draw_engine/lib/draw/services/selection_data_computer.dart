import '../models/draw_state.dart';
import '../models/selection_derived_data.dart';
import '../utils/selection_calculator.dart';
import 'selection_geometry_resolver.dart';

/// Pure (stateless) computer for selection-derived data.
class SelectionDataComputer {
  const SelectionDataComputer._();

  /// Computes a full [SelectionDerivedData] snapshot for a specific state.
  static SelectionDerivedData compute(DrawState state) {
    final selectedElements = SelectionCalculator.getSelectedElements(state);
    if (selectedElements.isEmpty) {
      return SelectionDerivedData.empty;
    }

    final selectionBounds =
        SelectionCalculator.computeSelectionBoundsForElements(
          selectedElements,
        )!;
    final geometry = SelectionGeometryResolver.resolve(
      selectedElements: selectedElements,
      selectionOverlay: state.application.selectionOverlay,
      selectionBounds: selectionBounds,
    );
    final singleSelectedElement = selectedElements.length == 1
        ? selectedElements.first
        : null;

    return SelectionDerivedData(
      selectedElements: selectedElements,
      selectionBounds: selectionBounds,
      overlayBounds: geometry.bounds,
      overlayRotation: geometry.rotation,
      overlayCenter: geometry.center,
      selectionRotation: singleSelectedElement?.rotation,
      selectionCenter: singleSelectedElement?.center,
    );
  }
}
