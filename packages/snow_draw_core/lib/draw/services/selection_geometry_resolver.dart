import '../models/element_state.dart';
import '../models/selection_geometry.dart';
import '../models/selection_overlay_state.dart';
import '../types/draw_rect.dart';
import '../utils/selection_calculator.dart';

/// Resolves selection overlay geometry from a single computation path.
class SelectionGeometryResolver {
  const SelectionGeometryResolver._();

  static SelectionGeometry resolve({
    required List<ElementState> selectedElements,
    required SelectionOverlayState selectionOverlay,
    DrawRect? selectionBounds,
    DrawRect? overlayBoundsOverride,
    double? overlayRotationOverride,
  }) {
    if (selectedElements.isEmpty) {
      return SelectionGeometry.none;
    }

    if (selectedElements.length == 1) {
      final element = selectedElements.first;
      return SelectionGeometry(
        bounds: element.rect,
        center: element.center,
        rotation: element.rotation == 0.0 ? null : element.rotation,
        hasSelection: true,
      );
    }

    final overlay = selectionOverlay.multiSelectOverlay;
    final bounds =
        overlayBoundsOverride ??
        overlay?.bounds ??
        selectionBounds ??
        SelectionCalculator.computeSelectionBoundsForElements(
          selectedElements,
        )!;

    final rotation = overlayRotationOverride ?? overlay?.rotation ?? 0.0;

    return SelectionGeometry(
      bounds: bounds,
      center: bounds.center,
      rotation: rotation == 0.0 ? null : rotation,
      hasSelection: true,
      isMultiSelect: true,
    );
  }
}
