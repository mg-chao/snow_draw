import 'package:meta/meta.dart';

import '../types/draw_point.dart';
import '../types/draw_rect.dart';
import 'draw_state.dart' show DrawState;
import 'element_state.dart';
import 'models.dart' show DrawState;

/// Immutable snapshot of selection-derived data.
///
/// This is intended to be computed from a specific [DrawState] instance (and
/// optionally an edit preview/session) and then reused by callers within a
/// single frame or event handler.
@immutable
class SelectionDerivedData {
  const SelectionDerivedData({
    required this.selectedElements,
    this.selectionBounds,
    this.overlayBounds,
    this.overlayRotation,
    this.overlayCenter,
    this.selectionRotation,
    this.selectionCenter,
  });
  final List<ElementState> selectedElements;

  /// Axis-aligned selection bounds in world coordinates.
  final DrawRect? selectionBounds;

  /// Overlay bounds used for rendering handles and overlays.
  ///
  /// For multi-select, this represents the unrotated bounds in the overlay's
  /// local frame (callers may render it rotated by [overlayRotation] around its
  /// center).
  final DrawRect? overlayBounds;

  /// Overlay rotation in radians (null when zero or when selection is empty).
  final double? overlayRotation;

  /// Overlay center in world coordinates.
  final DrawPoint? overlayCenter;

  /// Single-select rotation in radians (null when not a single selection).
  final double? selectionRotation;

  /// Single-select center in world coordinates (null when not a single
  /// selection).
  final DrawPoint? selectionCenter;

  bool get hasSelection => selectedElements.isNotEmpty;
  bool get isSingleSelect => selectedElements.length == 1;
  bool get isMultiSelect => selectedElements.length > 1;

  static const empty = SelectionDerivedData(selectedElements: []);
}
