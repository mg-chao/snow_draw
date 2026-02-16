import '../../draw/models/document_state.dart';
import '../../draw/models/element_state.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/utils/selection_calculator.dart';

/// Queries visible document elements in z-order without preview replacements.
///
/// This is the base scene query used by both static and dynamic painters.
List<ElementState> resolveBaseVisibleElementScene({
  required DocumentState document,
  required DrawRect viewportRect,
  int? minOrderIndex,
  int? maxOrderIndex,
}) => document.queryElementsInRectOrdered(
  viewportRect,
  minOrderIndex: minOrderIndex,
  maxOrderIndex: maxOrderIndex,
);

/// Builds a z-ordered list of visible elements with preview replacements.
///
/// Callers can pass [baseVisibleElements] to reuse a cached viewport query.
List<ElementState> resolveVisibleElementScene({
  required DocumentState document,
  required DrawRect viewportRect,
  required Map<String, ElementState> previewElementsById,
  List<ElementState>? baseVisibleElements,
  int? minOrderIndex,
  int? maxOrderIndex,
  String? excludedElementId,
}) {
  final visibleElements =
      baseVisibleElements ??
      resolveBaseVisibleElementScene(
        document: document,
        viewportRect: viewportRect,
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

  var addedPreviewOnlyElement = false;
  for (final preview in previewElementsById.values) {
    if (preview.id == excludedElementId ||
        effectiveById.containsKey(preview.id)) {
      continue;
    }

    final orderIndex = _resolveOrderIndex(document: document, element: preview);
    if (minOrderIndex != null && orderIndex < minOrderIndex) {
      continue;
    }
    if (maxOrderIndex != null && orderIndex > maxOrderIndex) {
      continue;
    }

    final aabb = SelectionCalculator.computeElementWorldAabb(preview);
    if (!_rectsIntersect(aabb, viewportRect)) {
      continue;
    }
    effectiveById[preview.id] = preview;
    addedPreviewOnlyElement = true;
  }

  if (effectiveById.isEmpty) {
    return <ElementState>[];
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
