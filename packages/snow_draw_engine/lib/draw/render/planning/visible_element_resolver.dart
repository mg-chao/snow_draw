import '../../models/document_state.dart';
import '../../models/element_state.dart';
import '../../types/draw_rect.dart';
import '../../utils/selection_calculator.dart';
import '../rect_intersection.dart';

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

    if (!_isInViewport(preview, viewportRect)) {
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

    if (!_isInViewport(preview, viewportRect)) {
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

bool _isInViewport(ElementState element, DrawRect viewportRect) =>
    rectsIntersect(
      SelectionCalculator.computeElementWorldAabb(element),
      viewportRect,
    );
