import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../../core/coordinates/overlay_space.dart';
import '../../core/coordinates/world_space.dart';
import '../../elements/types/arrow/arrow_core.dart' as core;
import '../../elements/types/arrow/arrow_core_bridge.dart';
import '../../elements/types/arrow/arrow_core_geometry_adapter.dart';
import '../../elements/types/arrow/arrow_core_ops.dart';
import '../../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../../elements/types/connector/connector_data.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../elements/types/text/text_bounds.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/element_state.dart';
import '../../services/text/text_metrics_service.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/element_geometry.dart';
import '../../types/element_style.dart';
import '../../types/resize_mode.dart';

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
    final offset = DrawPoint(x: dx, y: dy);
    _visitSelectedSnapshots<ElementMoveSnapshot>(
      selectedIds: selectedIds,
      snapshots: snapshots,
      currentElementsById: currentElementsById,
      visitor: (id, snapshot, current) {
        final newCenter = snapshot.center.translate(offset);
        result[id] = current.copyWith(
          rect: _rectFromCenter(
            center: newCenter,
            width: current.rect.width,
            height: current.rect.height,
          ),
        );
      },
    );
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
    _visitSelectedSnapshots<ElementRotateSnapshot>(
      selectedIds: selectedIds,
      snapshots: snapshots,
      currentElementsById: currentElementsById,
      visitor: (id, snapshot, current) {
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
      },
    );
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
    _visitSelectedSnapshots<ElementResizeSnapshot>(
      selectedIds: selectedIds,
      snapshots: snapshots,
      currentElementsById: currentElementsById,
      visitor: (id, snapshot, current) {
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

        final resizedData = resized.data;
        if (resizedData is TextData) {
          resized = _applyTextResize(
            element: resized,
            startRect: startElement.rect,
            anchor: anchor,
            keepCenter: keepTextCenter,
            isVerticalResize: isVerticalResize,
            scaleX: scaleX,
            textMetricsService: context.textMetricsService,
          );
        } else if (resizedData is SerialNumberData) {
          resized = _applySerialNumberResize(
            element: resized,
            startRect: startElement.rect,
          );
        } else if (resizedData is ConnectorData) {
          resized = _applyArrowResize(
            element: resized,
            data: resizedData,
            flipX: scaleX < 0,
            flipY: scaleY < 0,
          );
        }

        result[id] = resized;
      },
    );

    return result;
  }

  /// Returns a list where elements with matching ids are replaced.
  ///
  /// The original order is preserved.
  static List<ElementState> replaceElementsById({
    required List<ElementState> elements,
    required Map<String, ElementState> replacementsById,
  }) {
    if (replacementsById.isEmpty || elements.isEmpty) {
      return elements;
    }

    List<ElementState>? updatedElements;
    for (var index = 0; index < elements.length; index++) {
      final current = elements[index];
      final replacement = replacementsById[current.id];
      if (replacement == null) {
        continue;
      }
      if (replacement == current) {
        continue;
      }

      updatedElements ??= List<ElementState>.of(elements, growable: false);
      updatedElements[index] = replacement;
    }
    return updatedElements ?? elements;
  }

  /// Reorders [elements] to match [orderedElementIds] and normalizes z-index.
  ///
  /// Returns the original list when the provided id ordering is invalid.
  static List<ElementState> reorderElementsByIdOrder({
    required List<ElementState> elements,
    required List<String>? orderedElementIds,
  }) {
    if (orderedElementIds == null || elements.isEmpty) {
      return elements;
    }
    if (orderedElementIds.length != elements.length) {
      return elements;
    }

    final byId = <String, ElementState>{
      for (final element in elements) element.id: element,
    };
    if (byId.length != elements.length) {
      return elements;
    }

    final seenIds = <String>{};
    final reordered = <ElementState>[];
    for (final id in orderedElementIds) {
      if (!seenIds.add(id)) {
        return elements;
      }
      final element = byId[id];
      if (element == null) {
        return elements;
      }
      reordered.add(element);
    }

    final sameOrder = _sameElementOrder(
      current: elements,
      candidate: reordered,
    );
    if (sameOrder) {
      return _reindexElementsIfNeeded(elements);
    }

    return _reindexElementsIfNeeded(List<ElementState>.unmodifiable(reordered));
  }
}

bool _sameElementOrder({
  required List<ElementState> current,
  required List<ElementState> candidate,
}) {
  if (identical(current, candidate)) {
    return true;
  }
  if (current.length != candidate.length) {
    return false;
  }
  for (var i = 0; i < current.length; i++) {
    if (current[i].id != candidate[i].id) {
      return false;
    }
  }
  return true;
}

List<ElementState> _reindexElementsIfNeeded(List<ElementState> elements) {
  List<ElementState>? reindexed;
  for (var i = 0; i < elements.length; i++) {
    final element = elements[i];
    if (element.zIndex == i) {
      continue;
    }
    reindexed ??= List<ElementState>.of(elements, growable: false);
    reindexed[i] = element.copyWith(zIndex: i);
  }
  return reindexed ?? elements;
}

void _visitSelectedSnapshots<S>({
  required Set<String> selectedIds,
  required Map<String, S> snapshots,
  required Map<String, ElementState> currentElementsById,
  required void Function(String id, S snapshot, ElementState current) visitor,
}) {
  for (final id in selectedIds) {
    final snapshot = snapshots[id];
    final current = currentElementsById[id];
    if (snapshot == null || current == null) {
      continue;
    }
    visitor(id, snapshot, current);
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
  required TextMetricsService textMetricsService,
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
      textMetricsService: textMetricsService,
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
    textMetricsService: textMetricsService,
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
  required ConnectorData data,
  required bool flipX,
  required bool flipY,
}) {
  final nextPoints = flipX || flipY
      ? _flipNormalizedArrowPoints(data.points, flipX: flipX, flipY: flipY)
      : data.points;

  if (data.arrowType != ArrowType.elbow) {
    final nextData = data.copyWith(points: nextPoints);
    if (nextData == data) {
      return element;
    }
    return element.copyWith(data: nextData);
  }

  final worldPoints = resolveArrowWorldPoints(
    rect: element.rect,
    normalizedPoints: nextPoints,
  );
  final corePatch = computeCoreElbowResizePatch(
    startBinding: toCoreBinding(data.startBinding),
    endBinding: toCoreBinding(data.endBinding),
    fixedSegments: _toCoreFixedSegments(data.fixedSegments),
    points: toCorePoints(worldPoints),
    flipX: flipX,
    flipY: flipY,
  );
  final nextStartBinding = corePatch.containsKey('startBinding')
      ? fromCoreBinding(corePatch['startBinding'] as core.FixedPointBinding?)
      : data.startBinding;
  final nextEndBinding = corePatch.containsKey('endBinding')
      ? fromCoreBinding(corePatch['endBinding'] as core.FixedPointBinding?)
      : data.endBinding;
  final nextFixedSegments = corePatch.containsKey('fixedSegments')
      ? _fromCoreFixedSegments(corePatch['fixedSegments'] as List<Object?>?)
      : data.fixedSegments;

  final nextData = data.copyWith(
    points: nextPoints,
    startBinding: nextStartBinding,
    endBinding: nextEndBinding,
    fixedSegments: nextFixedSegments,
  );
  if (nextData == data) {
    return element;
  }
  return element.copyWith(data: nextData);
}

List<DrawPoint> _flipNormalizedArrowPoints(
  List<DrawPoint> points, {
  required bool flipX,
  required bool flipY,
}) => List<DrawPoint>.unmodifiable(
  points.map(
    (point) => DrawPoint(
      x: flipX ? (1 - point.x) : point.x,
      y: flipY ? (1 - point.y) : point.y,
      pressure: point.pressure,
    ),
  ),
);

List<core.FixedSegment>? _toCoreFixedSegments(
  List<ElbowFixedSegment>? fixedSegments,
) {
  if (fixedSegments == null || fixedSegments.isEmpty) {
    return null;
  }
  return fixedSegments
      .map(
        (segment) => core.FixedSegment(
          index: segment.index,
          start: <double>[segment.start.x, segment.start.y],
          end: <double>[segment.end.x, segment.end.y],
        ),
      )
      .toList(growable: false);
}

List<ElbowFixedSegment>? _fromCoreFixedSegments(List<Object?>? fixedSegments) {
  if (fixedSegments == null || fixedSegments.isEmpty) {
    return null;
  }
  final converted = <ElbowFixedSegment>[];
  for (final entry in fixedSegments) {
    if (entry is! core.FixedSegment) {
      continue;
    }
    converted.add(
      ElbowFixedSegment(
        index: entry.index,
        start: DrawPoint(x: entry.start[0], y: entry.start[1]),
        end: DrawPoint(x: entry.end[0], y: entry.end[1]),
      ),
    );
  }
  return converted.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(converted);
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
