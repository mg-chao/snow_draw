import 'package:meta/meta.dart';

import 'selection_state.dart';

/// Application-layer selection overlay state.
///
/// This holds transient UI-only overlay data and does not participate in
/// undo/redo or serialization.
@immutable
class SelectionOverlayState {
  const SelectionOverlayState({this.multiSelectOverlay});

  final MultiSelectOverlayState? multiSelectOverlay;

  bool get hasOverlay => multiSelectOverlay != null;

  SelectionOverlayState copyWith({
    MultiSelectOverlayState? multiSelectOverlay,
    bool resetMultiSelectOverlay = false,
  }) => SelectionOverlayState(
    multiSelectOverlay: resetMultiSelectOverlay
        ? null
        : (multiSelectOverlay ?? this.multiSelectOverlay),
  );

  static const empty = SelectionOverlayState();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionOverlayState &&
          other.multiSelectOverlay == multiSelectOverlay;

  @override
  int get hashCode => multiSelectOverlay.hashCode;

  @override
  String toString() =>
      'SelectionOverlayState(multiSelectOverlay: '
      '${multiSelectOverlay != null})';
}
