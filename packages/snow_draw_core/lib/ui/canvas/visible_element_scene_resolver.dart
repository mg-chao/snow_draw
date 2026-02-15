import '../../draw/models/document_state.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/utils/selection_calculator.dart';

/// Builds a z-ordered list of visible elements with preview replacements.
///
/// This resolver keeps document ordering stable even when preview geometry
/// moves an element into the viewport from outside the spatial index query
/// bounds.
List<ElementState> resolveVisibleElementScene({
  required DocumentState document,
  required DrawRect viewportRect,
  required Map<String, ElementState> previewElementsById,
  int? minOrderIndex,
  int? maxOrderIndex,
  String? excludedElementId,
}) {
  final visibleElements = document.queryElementsInRectOrdered(
    viewportRect,
    minOrderIndex: minOrderIndex,
    maxOrderIndex: maxOrderIndex,
  );

  if (previewElementsById.isEmpty && excludedElementId == null) {
    return visibleElements;
  }

  final effectiveById = <String, ElementState>{};
  for (final element in visibleElements) {
    if (element.id == excludedElementId) {
      continue;
    }
    final preview = previewElementsById[element.id];
    final effective = preview ?? element;
    if (preview != null) {
      final aabb = SelectionCalculator.computeElementWorldAabb(effective);
      if (!_rectsIntersect(aabb, viewportRect)) {
        continue;
      }
    }
    effectiveById[element.id] = effective;
  }

  for (final preview in previewElementsById.values) {
    if (preview.id == excludedElementId ||
        effectiveById.containsKey(preview.id)) {
      continue;
    }
    final orderIndex = document.getOrderIndex(preview.id);
    if (orderIndex != null) {
      if (minOrderIndex != null && orderIndex < minOrderIndex) {
        continue;
      }
      if (maxOrderIndex != null && orderIndex > maxOrderIndex) {
        continue;
      }
    }

    final aabb = SelectionCalculator.computeElementWorldAabb(preview);
    if (!_rectsIntersect(aabb, viewportRect)) {
      continue;
    }
    effectiveById[preview.id] = preview;
  }

  final effectiveElements = effectiveById.values.toList();
  if (effectiveElements.length < 2) {
    return effectiveElements;
  }

  final orderById = <String, int>{
    for (final element in effectiveElements)
      element.id: document.getOrderIndex(element.id) ?? element.zIndex,
  };

  effectiveElements.sort((a, b) {
    final orderComparison = orderById[a.id]!.compareTo(orderById[b.id]!);
    if (orderComparison != 0) {
      return orderComparison;
    }
    return a.id.compareTo(b.id);
  });
  return effectiveElements;
}

bool _rectsIntersect(DrawRect a, DrawRect b) =>
    a.minX <= b.maxX &&
    a.maxX >= b.minX &&
    a.minY <= b.maxY &&
    a.maxY >= b.minY;
