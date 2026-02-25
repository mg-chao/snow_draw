import 'dart:math' as math;

import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../types/draw_rect.dart';

class SelectionCalculator {
  SelectionCalculator._();

  static List<ElementState> getSelectedElements(DrawState state) {
    final document = state.domain.document;
    return state.domain.selection.selectedIds
        .map(document.getElementById)
        .whereType<ElementState>()
        .toList();
  }

  static DrawRect? computeSelectionBoundsForElements(
    List<ElementState> selected,
  ) {
    if (selected.isEmpty) {
      return null;
    }
    final singleElement = _singleSelectedElement(selected);
    if (singleElement != null) {
      return singleElement.rect;
    }

    var bounds = computeElementWorldAabb(selected.first);
    for (var i = 1; i < selected.length; i++) {
      bounds = _expandBounds(bounds, computeElementWorldAabb(selected[i]));
    }
    return bounds;
  }

  static DrawRect computeElementWorldAabb(ElementState element) {
    final rect = element.rect;
    final rotation = element.rotation;
    if (rotation == 0) {
      return rect;
    }

    final center = rect.center;
    final halfWidth = rect.width.abs() / 2;
    final halfHeight = rect.height.abs() / 2;
    final cosTheta = math.cos(rotation).abs();
    final sinTheta = math.sin(rotation).abs();
    final xExtent = halfWidth * cosTheta + halfHeight * sinTheta;
    final yExtent = halfWidth * sinTheta + halfHeight * cosTheta;
    return DrawRect(
      minX: center.x - xExtent,
      minY: center.y - yExtent,
      maxX: center.x + xExtent,
      maxY: center.y + yExtent,
    );
  }

  static ElementState? _singleSelectedElement(List<ElementState> selected) =>
      selected.length == 1 ? selected.first : null;

  static DrawRect _expandBounds(DrawRect a, DrawRect b) => DrawRect(
    minX: math.min(a.minX, b.minX),
    minY: math.min(a.minY, b.minY),
    maxX: math.max(a.maxX, b.maxX),
    maxY: math.max(a.maxY, b.maxY),
  );
}
