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

const _resizeTolerance = 0.01;

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
      result[id] = current.copyWith(
        rect: _rectFromCenter(
          center: newCenter,
          width: current.rect.width,
          height: current.rect.height,
        ),
      );
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
      result[id] = current.copyWith(
        rect: _rectFromCenter(
          center: newCenter,
          width: current.rect.width,
          height: current.rect.height,
        ),
        rotation: newRotation,
      );
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

      if (resized.data is TextData) {
        resized = _applyTextResize(
          element: resized,
          startRect: startElement.rect,
          anchor: anchor,
          keepCenter: keepTextCenter,
          isVerticalResize: isVerticalResize,
          scaleX: scaleX,
        );
      }

      if (resized.data is SerialNumberData) {
        resized = _applySerialNumberResize(
          element: resized,
          startRect: startElement.rect,
        );
      }

      if (resized.data is ArrowData) {
        resized = _applyArrowResize(
          element: resized,
          startRect: startElement.rect,
        );
      }

      result[id] = resized;
    }

    return result;
  }

  /// Returns a list where elements with matching ids are replaced.
  ///
  /// The original order is preserved. When [resolveIndex] is provided, it is
  /// used as an O(1) id-to-index lookup fast path.
  static List<ElementState> replaceElementsById({
    required List<ElementState> elements,
    required Map<String, ElementState> replacementsById,
    // Optional fast path for O(1) id-to-index lookup.
    // Unresolved ids fall back to a linear scan.
    int? Function(String id)? resolveIndex,
  }) {
    if (replacementsById.isEmpty || elements.isEmpty) {
      return elements;
    }

    List<ElementState>? result;
    void applyReplacement(int index, ElementState replacement) {
      result ??= List<ElementState>.of(elements, growable: false);
      result![index] = replacement;
    }

    final pending = <String, ElementState>{};
    if (resolveIndex != null) {
      for (final entry in replacementsById.entries) {
        final index = resolveIndex(entry.key);
        if (!_isResolvedIndexValid(
          index: index,
          id: entry.key,
          elements: elements,
        )) {
          pending[entry.key] = entry.value;
          continue;
        }

        final resolvedIndex = index!;
        final replacement = entry.value;
        final current = (result ?? elements)[resolvedIndex];
        if (replacement == current) {
          continue;
        }

        applyReplacement(resolvedIndex, replacement);
      }
    } else {
      pending.addAll(replacementsById);
    }

    if (pending.isEmpty) {
      return result ?? elements;
    }

    for (var i = 0; i < elements.length; i++) {
      final current = (result ?? elements)[i];
      final replacement = pending[current.id];
      if (replacement == null || replacement == current) {
        continue;
      }

      applyReplacement(i, replacement);
    }

    return result ?? elements;
  }
}

bool _isResolvedIndexValid({
  required int? index,
  required String id,
  required List<ElementState> elements,
}) {
  if (index == null || index < 0 || index >= elements.length) {
    return false;
  }
  return elements[index].id == id;
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
      (hasRotation || startBounds.width == 0 || startBounds.height == 0)) {
    return element.copyWith(rect: newSelectionBounds);
  }

  if (hasRotation) {
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

  return element.copyWith(
    rect: DrawRect(
      minX: math.min(x1, x2),
      minY: math.min(y1, y2),
      maxX: math.max(x1, x2),
      maxY: math.max(y1, y2),
    ),
  );
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

  return element.copyWith(
    rect: _rectFromCenter(
      center: newCenterWorldOfElement,
      width: newWidth,
      height: newHeight,
    ),
  );
}

ElementState _applyTextResize({
  required ElementState element,
  required DrawRect startRect,
  required DrawPoint anchor,
  required bool keepCenter,
  required bool isVerticalResize,
  required double scaleX,
}) {
  final originalData = element.data as TextData;
  var data = originalData;
  var rect = element.rect;
  final heightDelta = (rect.height - startRect.height).abs();
  final allowWidthScale =
      isVerticalResize && (scaleX - 1).abs() <= _resizeTolerance;

  if (allowWidthScale && heightDelta > _resizeTolerance) {
    final startHeight = startRect.height;
    if (startHeight > 0) {
      final heightScale = rect.height / startHeight;
      if (heightScale.isFinite &&
          heightScale > 0 &&
          (heightScale - 1).abs() > _resizeTolerance) {
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
  }

  if (heightDelta > _resizeTolerance) {
    final fittedFontSize = fitTextFontSizeToHeight(
      data: data,
      targetHeight: rect.height,
      maxWidth: rect.width,
    );
    if ((fittedFontSize - data.fontSize).abs() > _resizeTolerance) {
      data = data.copyWith(fontSize: fittedFontSize);
    }
  }

  final clampedRect = clampTextRectToLayout(
    rect: rect,
    startRect: startRect,
    anchor: anchor,
    data: data,
    keepCenter: keepCenter,
  );
  if (data.autoResize) {
    data = data.copyWith(autoResize: false);
  }
  if (clampedRect == element.rect && data == originalData) {
    return element;
  }
  return element.copyWith(rect: clampedRect, data: data);
}

ElementState _applySerialNumberResize({
  required ElementState element,
  required DrawRect startRect,
}) {
  final originalData = element.data as SerialNumberData;
  var data = originalData;
  final startDiameter = math.min(startRect.width, startRect.height);
  final nextDiameter = math.min(element.rect.width, element.rect.height);
  if (startDiameter > 0 && nextDiameter > 0) {
    final scale = nextDiameter / startDiameter;
    if (scale.isFinite && scale > 0) {
      final nextFontSize = data.fontSize * scale;
      if ((nextFontSize - data.fontSize).abs() > _resizeTolerance) {
        data = data.copyWith(fontSize: nextFontSize);
      }
    }
  }
  if (data == originalData) {
    return element;
  }
  return element.copyWith(data: data);
}

ElementState _applyArrowResize({
  required ElementState element,
  required DrawRect startRect,
}) {
  final data = element.data as ArrowData;
  final fixedSegments = data.fixedSegments;
  if (data.arrowType != ArrowType.elbow ||
      fixedSegments == null ||
      fixedSegments.isEmpty) {
    return element;
  }

  final scaled = _scaleFixedSegments(
    fixedSegments: fixedSegments,
    oldRect: startRect,
    newRect: element.rect,
  );
  if (fixedSegmentListEquals(fixedSegments, scaled)) {
    return element;
  }
  return element.copyWith(data: data.copyWith(fixedSegments: scaled));
}

List<ElbowFixedSegment> _scaleFixedSegments({
  required List<ElbowFixedSegment> fixedSegments,
  required DrawRect oldRect,
  required DrawRect newRect,
}) {
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

DrawRect _rectFromCenter({
  required DrawPoint center,
  required double width,
  required double height,
}) {
  final halfWidth = width / 2;
  final halfHeight = height / 2;
  return DrawRect(
    minX: center.x - halfWidth,
    minY: center.y - halfHeight,
    maxX: center.x + halfWidth,
    maxY: center.y + halfHeight,
  );
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
