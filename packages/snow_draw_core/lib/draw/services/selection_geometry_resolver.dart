import '../models/element_state.dart';
import '../models/selection_geometry.dart';
import '../models/selection_state.dart';
import '../types/draw_rect.dart';
import '../utils/selection_calculator.dart';

/// Resolves selection overlay geometry from a single computation path.
class SelectionGeometryResolver {
  const SelectionGeometryResolver._();

  static SelectionGeometry resolve({
    required List<ElementState> selectedElements,
    required SelectionState selection,
    DrawRect? selectionBounds,
    DrawRect? overlayBoundsOverride,
    double? overlayRotationOverride,
  }) {
    if (selectedElements.isEmpty) {
      return SelectionGeometry.none;
    }

    final isMultiSelect = selectedElements.length > 1;
    if (!isMultiSelect) {
      final element = selectedElements.first;
      return SelectionGeometry(
        bounds: element.rect,
        center: element.center,
        rotation: _nullIfZero(element.rotation),
        hasSelection: true,
      );
    }

    final fallbackBounds =
        selectionBounds ??
        SelectionCalculator.computeSelectionBoundsForElements(selectedElements);
    final bounds =
        overlayBoundsOverride ??
        selection.multiSelectOverlay?.bounds ??
        fallbackBounds;
    if (bounds == null) {
      return const SelectionGeometry(hasSelection: true, isMultiSelect: true);
    }

    final rotation =
        overlayRotationOverride ??
        selection.multiSelectOverlay?.rotation ??
        0.0;

    return SelectionGeometry(
      bounds: bounds,
      center: bounds.center,
      rotation: _nullIfZero(rotation),
      hasSelection: true,
      isMultiSelect: true,
    );
  }

  static double? _nullIfZero(double value) => value == 0.0 ? null : value;
}
