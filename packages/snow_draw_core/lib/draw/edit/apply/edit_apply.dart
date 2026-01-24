import 'dart:developer' as developer;

import 'package:meta/meta.dart';

import '../../core/coordinates/overlay_space.dart';
import '../../core/coordinates/world_space.dart';
import '../../elements/types/text/text_bounds.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/element_geometry.dart';
import '../../types/resize_mode.dart';

/// Single-source-of-truth geometry application for editing.
///
/// Both preview (render/hit-test) and commit (FinishEdit) should use this
/// module, so that geometry behavior cannot silently diverge.
@immutable
class EditApply {
  const EditApply._();

  static Map<String, ElementState> applyMoveToElements({
    required Map<String, ElementMoveSnapshot> snapshots,
    required Set<String> selectedIds,
    required double dx,
    required double dy,
    required Map<String, ElementState> currentElementsById,
  }) {
    final result = <String, ElementState>{};
    for (final id in selectedIds) {
      final snapshot = snapshots[id];
      final current = currentElementsById[id];
      if (snapshot == null || current == null) {
        continue;
      }

      final newCenter = snapshot.center.translate(DrawPoint(x: dx, y: dy));
      final halfWidth = current.rect.width / 2;
      final halfHeight = current.rect.height / 2;
      final newRect = DrawRect(
        minX: newCenter.x - halfWidth,
        minY: newCenter.y - halfHeight,
        maxX: newCenter.x + halfWidth,
        maxY: newCenter.y + halfHeight,
      );
      result[id] = current.copyWith(rect: newRect);
    }
    return result;
  }

  static Map<String, ElementState> applyRotateToElements({
    required Map<String, ElementRotateSnapshot> snapshots,
    required Set<String> selectedIds,
    required DrawPoint pivot,
    required double deltaAngle,
    required Map<String, ElementState> currentElementsById,
  }) {
    final result = <String, ElementState>{};
    const space = WorldSpace();
    for (final id in selectedIds) {
      final snapshot = snapshots[id];
      final current = currentElementsById[id];
      if (snapshot == null || current == null) {
        continue;
      }

      final newRotation = snapshot.rotation + deltaAngle;
      final newCenter = space.rotatePoint(
        point: snapshot.center,
        center: pivot,
        angle: deltaAngle,
      );

      final halfWidth = current.rect.width / 2;
      final halfHeight = current.rect.height / 2;
      final newRect = DrawRect(
        minX: newCenter.x - halfWidth,
        minY: newCenter.y - halfHeight,
        maxX: newCenter.x + halfWidth,
        maxY: newCenter.y + halfHeight,
      );

      result[id] = current.copyWith(rect: newRect, rotation: newRotation);
    }
    return result;
  }

  static Map<String, ElementState> applyResizeToElements({
    required Map<String, ElementResizeSnapshot> snapshots,
    required Set<String> selectedIds,
    required ResizeEditContext context,
    required DrawRect newSelectionBounds,
    required double scaleX,
    required double scaleY,
    required DrawPoint anchor,
    required Map<String, ElementState> currentElementsById,
  }) {
    final isSingleSelect = selectedIds.length == 1;
    final hasRotation = context.hasRotation;
    final keepTextCenter = anchor == context.startBounds.center;
    final isVerticalResize =
        context.resizeMode == ResizeMode.top ||
        context.resizeMode == ResizeMode.bottom;
    // Epsilon tolerance for floating-point comparisons when checking if text
    // height or font size has meaningfully changed during resize operations.
    const textHeightTolerance = 0.01;

    final result = <String, ElementState>{};
    for (final id in selectedIds) {
      final snapshot = snapshots[id];
      final current = currentElementsById[id];
      if (snapshot == null || current == null) {
        continue;
      }

      final startElement = current.copyWith(
        rect: snapshot.rect,
        rotation: snapshot.rotation,
      );
      var resized = _applyResize(
        element: startElement,
        startBounds: context.startBounds,
        newSelectionBounds: newSelectionBounds,
        scaleX: scaleX,
        scaleY: scaleY,
        anchor: anchor,
        overlayRotation: context.rotation,
        isSingleSelect: isSingleSelect,
        hasRotation: hasRotation,
      );
      // Special handling for text elements during resize:
      // 1. Preserve aspect ratio during vertical resize by scaling width
      // 2. Fit font size to match the new height
      // 3. Clamp rect to layout constraints
      // 4. Disable autoResize mode after manual resize
      if (resized.data is TextData) {
        var data = resized.data as TextData;
        var rect = resized.rect;
        final heightDelta = (rect.height - startElement.rect.height).abs();
        // During vertical resize, allow width scaling if horizontal scale is ~1.0
        final allowWidthScale =
            isVerticalResize &&
            (scaleX - 1).abs() <= textHeightTolerance;
        // Preserve aspect ratio: scale width proportionally to height change
        if (allowWidthScale && heightDelta > textHeightTolerance) {
          final startHeight = startElement.rect.height;
          final heightScale = startHeight <= 0
              ? 1.0
              : rect.height / startHeight;
          if (heightScale.isFinite &&
              heightScale > 0 &&
              (heightScale - 1).abs() > textHeightTolerance) {
            final newWidth = rect.width * heightScale;
            if (newWidth.isFinite && newWidth > 0) {
              final centerX = rect.centerX;
              rect = rect.copyWith(
                minX: centerX - newWidth / 2,
                maxX: centerX + newWidth / 2,
              );
            }
          }
        }
        // Adjust font size to fit the new height while respecting max width
        if (heightDelta > textHeightTolerance) {
          final fittedFontSize = fitTextFontSizeToHeight(
            data: data,
            targetHeight: rect.height,
            maxWidth: rect.width,
          );
          if ((fittedFontSize - data.fontSize).abs() > textHeightTolerance) {
            data = data.copyWith(fontSize: fittedFontSize);
          }
        }
        final clampedRect = clampTextRectToLayout(
          rect: rect,
          startRect: startElement.rect,
          anchor: anchor,
          data: data,
          keepCenter: keepTextCenter,
        );
        if (data.autoResize) {
          data = data.copyWith(autoResize: false);
        }
        if (clampedRect != resized.rect || data != resized.data) {
          resized = resized.copyWith(rect: clampedRect, data: data);
        }
      }
      result[id] = resized;
    }

    return result;
  }

  static List<ElementState> replaceElementsById({
    required List<ElementState> elements,
    required Map<String, ElementState> replacementsById,
  }) {
    if (replacementsById.isEmpty) {
      return elements;
    }

    var hasActualChanges = false;
    for (final entry in replacementsById.entries) {
      final index = _findElementIndex(elements, entry.key);
      if (index != -1 && !identical(elements[index], entry.value)) {
        hasActualChanges = true;
        break;
      }
    }

    if (!hasActualChanges) {
      return elements;
    }

    assert(() {
      if (elements.length > 1000 && replacementsById.length < 10) {
        developer.log(
          'Performance hint: replacing ${replacementsById.length} '
          'elements in a list of ${elements.length}. Consider using '
          'indexed replacement.',
          name: 'EditApply',
        );
      }
      return true;
    }(), 'Performance logging for element replacement');

    return elements
        .map((e) => replacementsById[e.id] ?? e)
        .toList(growable: false);
  }

  static int _findElementIndex(List<ElementState> elements, String id) {
    for (var i = 0; i < elements.length; i++) {
      if (elements[i].id == id) {
        return i;
      }
    }
    return -1;
  }
}

ElementState _applyResize({
  required ElementState element,
  required DrawRect startBounds,
  required DrawRect newSelectionBounds,
  required double scaleX,
  required double scaleY,
  required DrawPoint anchor,
  required double overlayRotation,
  required bool isSingleSelect,
  required bool hasRotation,
}) {
  if (isSingleSelect &&
      (startBounds.width == 0 || startBounds.height == 0)) {
    return element.copyWith(rect: newSelectionBounds);
  }
  if (hasRotation) {
    if (isSingleSelect) {
      return element.copyWith(rect: newSelectionBounds);
    }
    return _applyMultiRotatedResize(
      element: element,
      startBounds: startBounds,
      newSelectionBounds: newSelectionBounds,
      scaleX: scaleX,
      scaleY: scaleY,
      overlayRotation: overlayRotation,
    );
  }
  return _applyDirectResize(
    element: element,
    anchor: anchor,
    scaleX: scaleX,
    scaleY: scaleY,
  );
}

ElementState _applyDirectResize({
  required ElementState element,
  required DrawPoint anchor,
  required double scaleX,
  required double scaleY,
}) {
  final r = element.rect;
  final a = anchor;

  final x1 = a.x + (r.minX - a.x) * scaleX;
  final x2 = a.x + (r.maxX - a.x) * scaleX;
  final y1 = a.y + (r.minY - a.y) * scaleY;
  final y2 = a.y + (r.maxY - a.y) * scaleY;

  final newRect = DrawRect(
    minX: x1 < x2 ? x1 : x2,
    minY: y1 < y2 ? y1 : y2,
    maxX: x1 < x2 ? x2 : x1,
    maxY: y1 < y2 ? y2 : y1,
  );

  return element.copyWith(rect: newRect);
}

ElementState _applyMultiRotatedResize({
  required ElementState element,
  required DrawRect startBounds,
  required DrawRect newSelectionBounds,
  required double scaleX,
  required double scaleY,
  required double overlayRotation,
}) {
  final startCenter = startBounds.center;
  final newCenter = newSelectionBounds.center;

  final startSpace = OverlaySpace(
    rotation: overlayRotation,
    origin: startCenter,
  );
  final newSpace = OverlaySpace(rotation: overlayRotation, origin: newCenter);

  final startRect = element.rect;
  final startCenterWorldOfElement = startRect.center;
  final startCenterLocal = startSpace.fromWorld(startCenterWorldOfElement);

  final flipX = scaleX < 0;
  final flipY = scaleY < 0;
  final baseX = flipX ? newSelectionBounds.maxX : newSelectionBounds.minX;
  final baseY = flipY ? newSelectionBounds.maxY : newSelectionBounds.minY;

  final newCenterLocal = DrawPoint(
    x: baseX + (startCenterLocal.x - startBounds.minX) * scaleX,
    y: baseY + (startCenterLocal.y - startBounds.minY) * scaleY,
  );
  final newCenterWorldOfElement = newSpace.toWorld(newCenterLocal);

  final newWidth = startRect.width * scaleX.abs();
  final newHeight = startRect.height * scaleY.abs();

  final newRect = DrawRect(
    minX: newCenterWorldOfElement.x - newWidth / 2,
    minY: newCenterWorldOfElement.y - newHeight / 2,
    maxX: newCenterWorldOfElement.x + newWidth / 2,
    maxY: newCenterWorldOfElement.y + newHeight / 2,
  );

  return element.copyWith(rect: newRect);
}
