import 'package:meta/meta.dart';

import '../types/draw_rect.dart';

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
    this.selectionVersion = 0,
  });
  final Set<String> selectedIds;
  final int selectionVersion;

  bool get hasSelection => selectedIds.isNotEmpty;
  bool get isMultiSelect => selectedIds.length > 1;
  bool get isSingleSelect => selectedIds.length == 1;
  int get count => selectedIds.length;

  SelectionState copyWith({Set<String>? selectedIds, int? selectionVersion}) =>
      SelectionState(
        selectedIds: selectedIds ?? this.selectedIds,
        selectionVersion: selectionVersion ?? this.selectionVersion,
      );

  /// Sets single selection.
  SelectionState withSelected(String elementId) =>
      _withSelectedIds({elementId});

  /// Sets multi-selection.
  SelectionState withSelectedIds(Set<String> ids) => _withSelectedIds(ids);

  /// Adds an element to the selection.
  SelectionState withAdded(String elementId) {
    if (selectedIds.contains(elementId)) {
      return this;
    }
    return _withSelectedIds({...selectedIds, elementId});
  }

  /// Removes an element from the selection.
  SelectionState withRemoved(String elementId) {
    if (!selectedIds.contains(elementId)) {
      return this;
    }
    final newIds = {...selectedIds}..remove(elementId);
    return _withSelectedIds(newIds);
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
    return SelectionState(selectionVersion: selectionVersion + 1);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionState &&
          _setEquals(selectedIds, other.selectedIds) &&
          other.selectionVersion == selectionVersion;

  @override
  int get hashCode =>
      Object.hash(Object.hashAllUnordered(selectedIds), selectionVersion);

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
      'version: $selectionVersion)';

  SelectionState _withSelectedIds(Set<String> ids) {
    if (_setEquals(selectedIds, ids)) {
      return this;
    }
    return SelectionState(
      selectedIds: ids,
      selectionVersion: selectionVersion + 1,
    );
  }
}
