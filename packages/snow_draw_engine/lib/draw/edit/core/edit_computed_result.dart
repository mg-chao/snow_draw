import '../../models/element_state.dart';
import '../../types/draw_rect.dart';

/// Shared geometry result for edit preview and commit.
class EditComputedResult {
  const EditComputedResult({
    required this.updatedElements,
    this.orderedElementIds,
    this.multiSelectBounds,
    this.multiSelectRotation,
  });
  final Map<String, ElementState> updatedElements;
  final List<String>? orderedElementIds;
  final DrawRect? multiSelectBounds;
  final double? multiSelectRotation;
}
