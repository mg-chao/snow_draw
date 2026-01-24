import 'dart:math';

import '../core/coordinates/element_space.dart';
import '../models/draw_state.dart';
import '../models/element_state.dart';
import '../models/selection_state.dart';
import '../types/draw_point.dart';
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

  static DrawRect? computeSelectionBounds(DrawState state) {
    final selected = getSelectedElements(state);
    return computeSelectionBoundsForElements(selected);
  }

  static DrawRect? computeSelectionBoundsForElements(
    List<ElementState> selected,
  ) {
    if (selected.isEmpty) {
      return null;
    }
    if (selected.length == 1) {
      return selected.first.rect;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final element in selected) {
      final aabb = computeElementWorldAabb(element);
      minX = min(minX, aabb.minX);
      minY = min(minY, aabb.minY);
      maxX = max(maxX, aabb.maxX);
      maxY = max(maxY, aabb.maxY);
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  static DrawRect? computeOverlayBounds(DrawState state) {
    if (!state.domain.selection.hasSelection) {
      return null;
    }

    final selected = getSelectedElements(state);
    return computeOverlayBoundsForSelection(
      selectedElements: selected,
      selection: state.domain.selection,
    );
  }

  static double? computeOverlayRotation(DrawState state) {
    if (!state.domain.selection.hasSelection) {
      return null;
    }

    final selected = getSelectedElements(state);
    return computeOverlayRotationForSelection(
      selectedElements: selected,
      selection: state.domain.selection,
    );
  }

  static DrawPoint? computeOverlayCenter(DrawState state) {
    if (!state.domain.selection.hasSelection) {
      return null;
    }

    final selected = getSelectedElements(state);
    return computeOverlayCenterForSelection(
      selectedElements: selected,
      selection: state.domain.selection,
    );
  }

  static double? getSelectionRotation(DrawState state) {
    if (!state.domain.selection.hasSelection) {
      return null;
    }

    final selected = getSelectedElements(state);
    return getSelectionRotationForElements(selected);
  }

  static DrawPoint? getSelectionCenter(DrawState state) {
    if (!state.domain.selection.hasSelection) {
      return null;
    }

    final selected = getSelectedElements(state);
    return getSelectionCenterForElements(selected);
  }

  static DrawRect? computeOverlayBoundsForSelection({
    required List<ElementState> selectedElements,
    required SelectionState selection,
  }) {
    if (selectedElements.isEmpty) {
      return null;
    }
    if (selectedElements.length == 1) {
      return selectedElements.first.rect;
    }

    return selection.multiSelectOverlay?.bounds ??
        computeSelectionBoundsForElements(selectedElements);
  }

  static double? computeOverlayRotationForSelection({
    required List<ElementState> selectedElements,
    required SelectionState selection,
  }) {
    if (selectedElements.isEmpty) {
      return null;
    }

    final rotation = selectedElements.length == 1
        ? selectedElements.first.rotation
        : (selection.multiSelectOverlay?.rotation ?? 0.0);
    return rotation == 0.0 ? null : rotation;
  }

  static DrawPoint? computeOverlayCenterForSelection({
    required List<ElementState> selectedElements,
    required SelectionState selection,
  }) {
    if (selectedElements.isEmpty) {
      return null;
    }
    if (selectedElements.length == 1) {
      return selectedElements.first.center;
    }

    return computeOverlayBoundsForSelection(
      selectedElements: selectedElements,
      selection: selection,
    )?.center;
  }

  static double? getSelectionRotationForElements(
    List<ElementState> selectedElements,
  ) {
    if (selectedElements.length != 1) {
      return null;
    }
    return selectedElements.first.rotation;
  }

  static DrawPoint? getSelectionCenterForElements(
    List<ElementState> selectedElements,
  ) {
    if (selectedElements.length != 1) {
      return null;
    }
    return selectedElements.first.center;
  }

  static DrawRect computeElementWorldAabb(ElementState element) {
    final rect = element.rect;
    final rotation = element.rotation;
    if (rotation == 0) {
      return rect;
    }

    final center = rect.center;
    final space = ElementSpace(rotation: rotation, origin: center);
    final halfWidth = rect.width / 2;
    final halfHeight = rect.height / 2;

    final localCorners = <DrawPoint>[
      DrawPoint(x: -halfWidth, y: -halfHeight),
      DrawPoint(x: halfWidth, y: -halfHeight),
      DrawPoint(x: halfWidth, y: halfHeight),
      DrawPoint(x: -halfWidth, y: halfHeight),
    ];

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final p in localCorners) {
      final rotatedCorner = space.toWorld(
        DrawPoint(x: center.x + p.x, y: center.y + p.y),
      );
      final x = rotatedCorner.x;
      final y = rotatedCorner.y;
      if (x < minX) {
        minX = x;
      }
      if (y < minY) {
        minY = y;
      }
      if (x > maxX) {
        maxX = x;
      }
      if (y > maxY) {
        maxY = y;
      }
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
