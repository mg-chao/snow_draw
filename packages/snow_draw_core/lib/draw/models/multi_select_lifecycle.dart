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
    Set<String> newSelectedIds, {
    DrawRect? newOverlayBounds,
  }) {
    if (newSelectedIds.length < 2 || newOverlayBounds == null) {
      return SelectionOverlayState.empty;
    }
    return SelectionOverlayState(
      multiSelectOverlay: MultiSelectOverlayState(bounds: newOverlayBounds),
    );
  }

  /// Applies rotation finish: update rotation and bounds.
  static SelectionOverlayState onRotateFinished(
    SelectionOverlayState current, {
    required double newRotation,
    required DrawRect bounds,
  }) => current.copyWith(
    multiSelectOverlay: MultiSelectOverlayState(
      bounds: bounds,
      rotation: newRotation,
    ),
  );

  /// Applies move finish: keep rotation, update bounds.
  static SelectionOverlayState onMoveFinished(
    SelectionOverlayState current, {
    required DrawRect newBounds,
  }) => current.copyWith(
    multiSelectOverlay: MultiSelectOverlayState(
      bounds: newBounds,
      rotation: current.multiSelectOverlay?.rotation ?? 0.0,
    ),
  );

  /// Applies resize finish: keep rotation, update bounds.
  static SelectionOverlayState onResizeFinished(
    SelectionOverlayState current, {
    required DrawRect newBounds,
  }) => onMoveFinished(current, newBounds: newBounds);

  /// Clears selection state.
  static SelectionOverlayState onSelectionCleared() =>
      SelectionOverlayState.empty;
}
