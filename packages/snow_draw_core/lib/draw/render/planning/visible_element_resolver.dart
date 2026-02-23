import 'package:snow_draw_core/snow_draw_core.dart';

/// Builds a z-ordered list of visible elements with preview replacements.
List<ElementState> resolveVisibleElementScene({
  required DocumentState document,
  required DrawRect viewportRect,
  required Map<String, ElementState> previewElementsById,
  String? excludedElementId,
}) {
  final visibleElements = document.queryElementsInRectOrdered(viewportRect);

  if (previewElementsById.isEmpty && excludedElementId == null) {
    return visibleElements;
  }

  final effectiveById = <String, ElementState>{};
  for (final element in visibleElements) {
    final elementId = element.id;
    if (elementId == excludedElementId) {
      continue;
    }

    final preview = previewElementsById[elementId];
    if (preview == null) {
      effectiveById[elementId] = element;
      continue;
    }

    final previewAabb = SelectionCalculator.computeElementWorldAabb(preview);
    if (!_rectsIntersect(previewAabb, viewportRect)) {
      continue;
    }
    effectiveById[elementId] = preview;
  }

  var addedPreviewOnlyElement = false;
  for (final preview in previewElementsById.values) {
    final previewId = preview.id;
    if (previewId == excludedElementId ||
        effectiveById.containsKey(previewId)) {
      continue;
    }

    final aabb = SelectionCalculator.computeElementWorldAabb(preview);
    if (!_rectsIntersect(aabb, viewportRect)) {
      continue;
    }
    effectiveById[previewId] = preview;
    addedPreviewOnlyElement = true;
  }

  final effectiveElements = effectiveById.values.toList();
  if (!addedPreviewOnlyElement || effectiveElements.length < 2) {
    return effectiveElements;
  }

  final orderById = <String, int>{
    for (final element in effectiveElements)
      element.id: _resolveOrderIndex(document: document, element: element),
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

int _resolveOrderIndex({
  required DocumentState document,
  required ElementState element,
}) => document.getOrderIndex(element.id) ?? element.zIndex;

bool _rectsIntersect(DrawRect a, DrawRect b) =>
    a.minX <= b.maxX &&
    a.maxX >= b.minX &&
    a.minY <= b.maxY &&
    a.maxY >= b.minY;
