import 'package:meta/meta.dart';

import '../types/draw_point.dart';
import '../types/draw_rect.dart';

@immutable
class SelectionGeometry {
  const SelectionGeometry({
    this.bounds,
    this.center,
    this.rotation,
    this.hasSelection = false,
    this.isMultiSelect = false,
  });
  final DrawRect? bounds;
  final DrawPoint? center;
  final double? rotation;
  final bool hasSelection;
  final bool isMultiSelect;

  bool get isSingleSelect => hasSelection && !isMultiSelect;

  static const none = SelectionGeometry();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SelectionGeometry &&
          other.bounds == bounds &&
          other.center == center &&
          other.rotation == rotation &&
          other.hasSelection == hasSelection &&
          other.isMultiSelect == isMultiSelect;

  @override
  int get hashCode =>
      Object.hash(bounds, center, rotation, hasSelection, isMultiSelect);

  @override
  String toString() =>
      'SelectionGeometry('
      'bounds: $bounds, '
      'center: $center, '
      'rotation: $rotation, '
      'hasSelection: $hasSelection, '
      'isMultiSelect: $isMultiSelect'
      ')';
}
