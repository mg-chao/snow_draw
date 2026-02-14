import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../core/coordinates/overlay_space.dart';
import '../../core/coordinates/world_space.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_bounds.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/element_geometry.dart';
import '../../types/element_style.dart';
import '../../types/resize_mode.dart';
import '../../utils/list_equality.dart';

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
      final data = current.data;
      if (data is ArrowLikeData && data.arrowType == ArrowType.elbow) {
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
        // During vertical resize, allow width scaling
        // if horizontal scale is ~1.0
        final allowWidthScale =
            isVerticalResize && (scaleX - 1).abs() <= textHeightTolerance;
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
      if (resized.data is SerialNumberData) {
        var data = resized.data as SerialNumberData;
        final startRect = startElement.rect;
        final startDiameter = math.min(startRect.width, startRect.height);
        final nextDiameter = math.min(resized.rect.width, resized.rect.height);
        if (startDiameter > 0 && nextDiameter > 0) {
          final scale = nextDiameter / startDiameter;
          if (scale.isFinite && scale > 0) {
            final nextFontSize = data.fontSize * scale;
            if ((nextFontSize - data.fontSize).abs() > textHeightTolerance) {
              data = data.copyWith(fontSize: nextFontSize);
            }
          }
        }
        if (data != resized.data) {
          resized = resized.copyWith(data: data);
        }
      }
      if (resized.data is ArrowData) {
        var data = resized.data as ArrowData;
        final fixedSegments = data.fixedSegments;
        if (data.arrowType == ArrowType.elbow &&
            fixedSegments != null &&
            fixedSegments.isNotEmpty) {
          final scaled = _scaleFixedSegments(
            fixedSegments: fixedSegments,
            oldRect: startElement.rect,
            newRect: resized.rect,
          );
          if (scaled != null &&
              !fixedSegmentListEquals(fixedSegments, scaled)) {
            data = data.copyWith(fixedSegments: scaled);
            resized = resized.copyWith(data: data);
          }
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
    if (replacementsById.isEmpty || elements.isEmpty) {
      return elements;
    }

    List<ElementState>? result;
    for (var i = 0; i < elements.length; i++) {
      final current = elements[i];
      final replacement = replacementsById[current.id];
      if (replacement == null || replacement == current) {
        continue;
      }

      result ??= List<ElementState>.of(elements, growable: false);
      result[i] = replacement;
    }

    return result ?? elements;
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
  if (isSingleSelect && (startBounds.width == 0 || startBounds.height == 0)) {
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

List<ElbowFixedSegment>? _scaleFixedSegments({
  required List<ElbowFixedSegment> fixedSegments,
  required DrawRect oldRect,
  required DrawRect newRect,
}) {
  if (fixedSegments.isEmpty) {
    return null;
  }
  final scaled = fixedSegments
      .map(
        (segment) => segment.copyWith(
          start: _scalePoint(segment.start, oldRect, newRect),
          end: _scalePoint(segment.end, oldRect, newRect),
        ),
      )
      .toList(growable: false);
  return List<ElbowFixedSegment>.unmodifiable(scaled);
}

DrawPoint _scalePoint(DrawPoint point, DrawRect oldRect, DrawRect newRect) {
  final oldWidth = oldRect.width;
  final oldHeight = oldRect.height;
  final newWidth = newRect.width;
  final newHeight = newRect.height;
  final nx = oldWidth == 0 ? 0.0 : (point.x - oldRect.minX) / oldWidth;
  final ny = oldHeight == 0 ? 0.0 : (point.y - oldRect.minY) / oldHeight;
  return DrawPoint(
    x: newRect.minX + nx * newWidth,
    y: newRect.minY + ny * newHeight,
  );
}
