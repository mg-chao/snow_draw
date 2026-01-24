import 'package:meta/meta.dart';

import '../types/draw_rect.dart';
import 'selection_state.dart';

/// Multi-select lifecycle rules.
///
/// Centralizes updates for:
/// - SelectionState.multiSelectOverlay
///
/// The overlay resets whenever the selection set changes.
/// Rotation is updated only after rotate finishes.
/// Bounds are updated after move/resize finishes.
@immutable
class MultiSelectLifecycle {
  const MultiSelectLifecycle._();

  /// Applies selection changes; resets overlay on change.
  static SelectionState onSelectionChanged(
    SelectionState current,
    Set<String> newSelectedIds, {
    DrawRect? newOverlayBounds,
  }) {
    if (_setEquals(current.selectedIds, newSelectedIds)) {
      return current.copyWith(selectedIds: newSelectedIds);
    }

    return SelectionState(
      selectedIds: newSelectedIds,
      multiSelectOverlay: newSelectedIds.length > 1 && newOverlayBounds != null
          ? MultiSelectOverlayState(bounds: newOverlayBounds)
          : null,
      selectionVersion: current.selectionVersion + 1,
    );
  }

  /// Applies rotation finish: update rotation, keep bounds.
  static SelectionState onRotateFinished(
    SelectionState current, {
    required double newRotation,
    DrawRect? bounds,
  }) {
    final currentOverlay = current.multiSelectOverlay;
    final nextBounds = bounds ?? currentOverlay?.bounds;
    if (nextBounds == null) {
      return current;
    }

    return current.copyWith(
      multiSelectOverlay: MultiSelectOverlayState(
        bounds: nextBounds,
        rotation: newRotation,
      ),
    );
  }

  /// Applies move finish: keep rotation, update bounds.
  static SelectionState onMoveFinished(
    SelectionState current, {
    required DrawRect newBounds,
  }) {
    final rotation = current.multiSelectOverlay?.rotation ?? 0.0;
    return current.copyWith(
      multiSelectOverlay: MultiSelectOverlayState(
        bounds: newBounds,
        rotation: rotation,
      ),
    );
  }

  /// Applies resize finish: keep rotation, update bounds.
  static SelectionState onResizeFinished(
    SelectionState current, {
    required DrawRect newBounds,
  }) {
    final rotation = current.multiSelectOverlay?.rotation ?? 0.0;
    return current.copyWith(
      multiSelectOverlay: MultiSelectOverlayState(
        bounds: newBounds,
        rotation: rotation,
      ),
    );
  }

  /// Clears selection state.
  static SelectionState onSelectionCleared(SelectionState current) =>
      SelectionState(selectionVersion: current.selectionVersion + 1);

  static bool _setEquals<T>(Set<T> a, Set<T> b) {
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
}
