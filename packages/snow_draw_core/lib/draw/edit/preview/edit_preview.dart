import 'package:meta/meta.dart';

import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../services/element_index_service.dart';
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

  ElementState effectiveElement(ElementState element) =>
      previewElementsById[element.id] ?? element;
}

SelectionPreview? buildSelectionPreview({
  required DrawState state,
  required EditContext context,
  required Map<String, ElementState> previewElementsById,
  DrawRect? multiSelectBounds,
  double? multiSelectRotation,
}) {
  if (!state.domain.selection.hasSelection) {
    return null;
  }

  final selectedIds = context.selectedIdsAtStart;
  final index = ElementIndexService(state.domain.document.elements);
  final selectedElements = <ElementState>[];
  for (final id in selectedIds) {
    final element = previewElementsById[id] ?? index[id];
    if (element != null) {
      selectedElements.add(element);
    }
  }

  final geometry = SelectionGeometryResolver.resolve(
    selectedElements: selectedElements,
    selection: state.domain.selection,
    overlayBoundsOverride: multiSelectBounds ?? context.startBounds,
    overlayRotationOverride: multiSelectRotation,
  );

  final bounds = geometry.bounds;
  final center = geometry.center;
  if (bounds == null || center == null) {
    return null;
  }

  return SelectionPreview(
    bounds: bounds,
    center: center,
    rotation: geometry.rotation,
  );
}
