import 'package:meta/meta.dart';

import '../types/draw_rect.dart';
import 'multi_select_lifecycle.dart';

@immutable
class MultiSelectOverlayState {
  const MultiSelectOverlayState({required this.bounds, this.rotation = 0.0});

  /// Axis-aligned overlay bounds in the overlay's local (unrotated) frame.
  final DrawRect bounds;

  /// Overlay rotation in radians.
  final double rotation;

  MultiSelectOverlayState copyWith({DrawRect? bounds, double? rotation}) =>
      MultiSelectOverlayState(
        bounds: bounds ?? this.bounds,
        rotation: rotation ?? this.rotation,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiSelectOverlayState &&
          other.bounds == bounds &&
          other.rotation == rotation;

  @override
  int get hashCode => Object.hash(bounds, rotation);

  @override
  String toString() =>
      'MultiSelectOverlayState(bounds: $bounds, rotation: $rotation)';
}

@immutable
class SelectionState {
  const SelectionState({
    this.selectedIds = const {},
    this.multiSelectOverlay,
    this.selectionVersion = 0,
  });
  final Set<String> selectedIds;
  final int selectionVersion;

  /// Persistent overlay state for multi-select sessions.
  ///
  /// This keeps the multi-select bounds/rotation stable across edit operations
  /// until the selected set changes.
  final MultiSelectOverlayState? multiSelectOverlay;

  bool get hasSelection => selectedIds.isNotEmpty;
  bool get isMultiSelect => selectedIds.length > 1;
  bool get isSingleSelect => selectedIds.length == 1;
  int get count => selectedIds.length;

  SelectionState copyWith({
    Set<String>? selectedIds,
    MultiSelectOverlayState? multiSelectOverlay,
    bool resetMultiSelectOverlay = false,
    int? selectionVersion,
  }) => SelectionState(
    selectedIds: selectedIds ?? this.selectedIds,
    multiSelectOverlay: resetMultiSelectOverlay
        ? null
        : (multiSelectOverlay ?? this.multiSelectOverlay),
    selectionVersion: selectionVersion ?? this.selectionVersion,
  );

  /// Sets single selection.
  ///
  /// Note: resets multi-select overlay when the selection changes.
  SelectionState withSelected(String elementId) =>
      MultiSelectLifecycle.onSelectionChanged(this, {elementId});

  /// Sets multi-selection.
  ///
  /// Note: resets multi-select overlay when the selection changes.
  SelectionState withSelectedIds(Set<String> ids) =>
      MultiSelectLifecycle.onSelectionChanged(this, ids);

  /// Adds an element to the selection.
  ///
  /// Note: resets multi-select overlay when the selection changes.
  SelectionState withAdded(String elementId) {
    if (selectedIds.contains(elementId)) {
      return this;
    }
    return MultiSelectLifecycle.onSelectionChanged(this, {
      ...selectedIds,
      elementId,
    });
  }

  /// Removes an element from the selection.
  ///
  /// Note: resets multi-select overlay when the selection changes.
  SelectionState withRemoved(String elementId) {
    if (!selectedIds.contains(elementId)) {
      return this;
    }
    final newIds = {...selectedIds}..remove(elementId);
    return MultiSelectLifecycle.onSelectionChanged(this, newIds);
  }

  /// Toggles an element's selection state.
  SelectionState withToggled(String elementId) =>
      selectedIds.contains(elementId)
      ? withRemoved(elementId)
      : withAdded(elementId);

  /// Clears selection.
  SelectionState cleared() {
    if (selectedIds.isEmpty) {
      return this;
    }
    return MultiSelectLifecycle.onSelectionCleared(this);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionState &&
          _setEquals(selectedIds, other.selectedIds) &&
          other.multiSelectOverlay == multiSelectOverlay &&
          other.selectionVersion == selectionVersion;

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(selectedIds),
    multiSelectOverlay,
    selectionVersion,
  );

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

  @override
  String toString() =>
      'SelectionState('
      'ids: ${selectedIds.length}, '
      'overlay: ${multiSelectOverlay != null}, '
      'version: $selectionVersion)';
}
