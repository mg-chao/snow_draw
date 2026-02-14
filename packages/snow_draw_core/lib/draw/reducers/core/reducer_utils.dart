import 'dart:math';

import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../services/selection_geometry_resolver.dart';
import '../../types/draw_rect.dart';
import '../../utils/selection_calculator.dart';

/// Normalize angle to [-pi, pi].
double normalizeAngle(double angle) => atan2(sin(angle), cos(angle));

/// Returns true when the two rectangles intersect (touching counts as
/// intersecting).
bool rectsIntersect(DrawRect a, DrawRect b) =>
    a.minX <= b.maxX &&
    a.maxX >= b.minX &&
    a.minY <= b.maxY &&
    a.maxY >= b.minY;

/// Resolves the next z-index for a newly appended element.
///
/// Uses the highest explicit z-index in [elements] rather than list length so
/// new elements remain top-most even when existing z-indices are sparse or
/// stale.
int resolveNextZIndex(Iterable<ElementState> elements) {
  var maxZIndex = -1;
  for (final element in elements) {
    if (element.zIndex > maxZIndex) {
      maxZIndex = element.zIndex;
    }
  }
  return maxZIndex + 1;
}

/// Applies a selection change.
///
/// Handles the single-select vs. multi-select cache/bounds behavior
/// consistently.
DrawState applySelectionChange(DrawState state, Set<String> selectedIds) {
  // No-op when the selected set doesn't change. This avoids rebuilding the
  // selection state and accidentally wiping multi-select overlay state.
  if (_setEquals(state.domain.selection.selectedIds, selectedIds)) {
    return state;
  }

  final document = state.domain.document;
  final selectedElements = <ElementState>[];
  for (final id in selectedIds) {
    final element = document.getElementById(id);
    if (element != null) {
      selectedElements.add(element);
    }
  }
  final selectionBounds = SelectionCalculator.computeSelectionBoundsForElements(
    selectedElements,
  );
  final geometry = SelectionGeometryResolver.resolve(
    selectedElements: selectedElements,
    selectionOverlay: state.application.selectionOverlay,
    selectionBounds: selectionBounds,
    overlayBoundsOverride: selectedElements.length > 1 ? selectionBounds : null,
    overlayRotationOverride: 0,
  );
  final overlayBounds = geometry.isMultiSelect ? geometry.bounds : null;

  final nextSelection = state.domain.selection.withSelectedIds(selectedIds);
  final nextOverlay = MultiSelectLifecycle.onSelectionChanged(
    state.application.selectionOverlay,
    selectedIds,
    newOverlayBounds: overlayBounds,
  );

  return state.copyWith(
    domain: state.domain.copyWith(selection: nextSelection),
    application: state.application.copyWith(selectionOverlay: nextOverlay),
  );
}

bool _setEquals<T>(Set<T> a, Set<T> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (final item in a) {
    if (!b.contains(item)) {
      return false;
    }
  }
  return true;
}
