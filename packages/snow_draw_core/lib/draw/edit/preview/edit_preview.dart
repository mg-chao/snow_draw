import 'package:meta/meta.dart';

import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../services/selection_geometry_resolver.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';

@immutable
class SelectionPreview {
  const SelectionPreview({
    required this.bounds,
    required this.center,
    required this.rotation,
  });
  final DrawRect bounds;
  final DrawPoint center;
  final double? rotation;
}

@immutable
class EditPreview {
  const EditPreview({
    required this.previewElementsById,
    required this.selectionPreview,
  });
  final Map<String, ElementState> previewElementsById;
  final SelectionPreview? selectionPreview;

  static const none = EditPreview(
    previewElementsById: {},
    selectionPreview: null,
  );
}

SelectionPreview? buildSelectionPreview({
  required DrawState state,
  required EditContext context,
  required Map<String, ElementState> previewElementsById,
  DrawRect? multiSelectBounds,
  double? multiSelectRotation,
}) {
  final elementMap = state.domain.document.elementMap;
  final selectedElements = context.selectedIdsAtStart
      .map((id) => previewElementsById[id] ?? elementMap[id])
      .whereType<ElementState>()
      .toList(growable: false);
  if (selectedElements.isEmpty) {
    return null;
  }

  final geometry = SelectionGeometryResolver.resolve(
    selectedElements: selectedElements,
    selectionOverlay: state.application.selectionOverlay,
    overlayBoundsOverride: multiSelectBounds ?? context.startBounds,
    overlayRotationOverride: multiSelectRotation,
  );

  return SelectionPreview(
    bounds: geometry.bounds!,
    center: geometry.center!,
    rotation: geometry.rotation,
  );
}
