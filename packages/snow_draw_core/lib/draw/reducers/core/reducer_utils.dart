import 'dart:math';

import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/multi_select_lifecycle.dart';
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
DrawState applySelectionChange(
  DrawState state,
  Set<String> selectedIds, {
  bool forceRefreshOverlay = false,
}) {
  final selectionUnchanged = _setEquals(
    state.domain.selection.selectedIds,
    selectedIds,
  );

  if (selectionUnchanged && !forceRefreshOverlay) {
    return state;
  }

  final document = state.domain.document;
  final selectedElements = selectedIds
      .map(document.getElementById)
      .whereType<ElementState>()
      .toList();
  final overlayBounds = selectedElements.length > 1
      ? SelectionCalculator.computeSelectionBoundsForElements(selectedElements)
      : null;

  final currentOverlay = state.application.selectionOverlay;
  final nextOverlay =
      selectionUnchanged && forceRefreshOverlay && overlayBounds != null
      ? MultiSelectLifecycle.onMoveFinished(
          currentOverlay,
          newBounds: overlayBounds,
        )
      : MultiSelectLifecycle.onSelectionChanged(
          selectedIds,
          newOverlayBounds: overlayBounds,
        );

  if (selectionUnchanged) {
    if (nextOverlay == currentOverlay) {
      return state;
    }
    return state.copyWith(
      application: state.application.copyWith(selectionOverlay: nextOverlay),
    );
  }

  final nextApplication = nextOverlay == currentOverlay
      ? state.application
      : state.application.copyWith(selectionOverlay: nextOverlay);

  return state.copyWith(
    domain: state.domain.copyWith(
      selection: state.domain.selection.withSelectedIds(selectedIds),
    ),
    application: nextApplication,
  );
}

bool _setEquals<T>(Set<T> a, Set<T> b) =>
    identical(a, b) || (a.length == b.length && a.containsAll(b));
