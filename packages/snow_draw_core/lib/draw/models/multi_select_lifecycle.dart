import 'package:meta/meta.dart';

import '../types/draw_rect.dart';
import 'selection_overlay_state.dart';
import 'selection_state.dart';

/// Multi-select overlay lifecycle rules.
///
/// Centralizes updates for transient overlay state:
/// - Overlay resets whenever the selection set changes.
/// - Rotation updates after rotate finishes.
/// - Bounds update after move/resize finishes.
@immutable
class MultiSelectLifecycle {
  const MultiSelectLifecycle._();

  /// Applies selection changes; resets overlay on change.
  static SelectionOverlayState onSelectionChanged(
    SelectionOverlayState current,
    Set<String> newSelectedIds, {
    DrawRect? newOverlayBounds,
  }) {
    if (newSelectedIds.length <= 1 || newOverlayBounds == null) {
      return SelectionOverlayState.empty;
    }
    return SelectionOverlayState(
      multiSelectOverlay: MultiSelectOverlayState(bounds: newOverlayBounds),
    );
  }

  /// Applies rotation finish: update rotation, keep bounds.
  static SelectionOverlayState onRotateFinished(
    SelectionOverlayState current, {
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
  static SelectionOverlayState onMoveFinished(
    SelectionOverlayState current, {
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
  static SelectionOverlayState onResizeFinished(
    SelectionOverlayState current, {
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
  static SelectionOverlayState onSelectionCleared(SelectionOverlayState _) =>
      SelectionOverlayState.empty;
}
