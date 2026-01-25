import 'dart:ui';

import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_style.dart';
import '../apply/edit_apply.dart';
import '../core/edit_errors.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../preview/edit_preview.dart';

class ArrowPointOperation extends EditOperation {
  const ArrowPointOperation();

  @override
  EditOperationId get id => EditOperationIds.arrowPoint;

  @override
  HistoryMetadata createHistoryMetadata({
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.createHistoryMetadata',
    );
    return HistoryMetadata.forEdit(
      operationType: 'Arrow point',
      elementIds: typedContext.selectedIdsAtStart,
    );
  }

  @override
  ArrowPointEditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final typedParams = requireParams<ArrowPointOperationParams>(
      params,
      operationName: 'ArrowPointOperation.createContext',
    );
    final element = state.domain.document.getElementById(typedParams.elementId);
    if (element == null || element.data is! ArrowData) {
      throw EditMissingDataError(
        dataName: 'arrow element',
        operationName: 'ArrowPointOperation.createContext',
      );
    }
    final data = element.data as ArrowData;
    final points = _resolveWorldPoints(element, data);
    if (points.length < 2) {
      throw EditMissingDataError(
        dataName: 'arrow points',
        operationName: 'ArrowPointOperation.createContext',
      );
    }

    final startBounds = requireSelectionBounds(
      selectionData: SelectionDataComputer.compute(state),
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'ArrowPointOperation.createContext',
    );

    final localStartPosition = _toLocalPosition(
      element.rect,
      element.rotation,
      position,
    );
    final pointPosition = _resolvePointPosition(
      points: points,
      kind: typedParams.pointKind,
      index: typedParams.pointIndex,
      arrowType: data.arrowType,
    );
    final dragOffset = pointPosition - localStartPosition;
    final selectedIdsAtStart = {...state.domain.selection.selectedIds};

    return ArrowPointEditContext(
      startPosition: localStartPosition,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: state.domain.selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
      elementId: element.id,
      elementRect: element.rect,
      rotation: element.rotation,
      initialPoints: List<DrawPoint>.unmodifiable(points),
      pointKind: typedParams.pointKind,
      pointIndex: typedParams.pointIndex,
      dragOffset: dragOffset,
    );
  }

  @override
  ArrowPointTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.initialTransform',
    );
    return ArrowPointTransform(
      currentPosition: startPosition,
      points: typedContext.initialPoints,
      activeIndex: null,
      hasChanges: false,
    );
  }

  @override
  EditUpdateResult<EditTransform> update({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
    required DrawConfig config,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.update',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.update',
    );

    final localPosition = _toLocalPosition(
      typedContext.elementRect,
      typedContext.rotation,
      currentPosition,
    );
    final zoom = state.application.view.camera.zoom;
    final result = _compute(
      context: typedContext,
      currentPosition: localPosition,
      didInsert: typedTransform.didInsert,
      config: config,
      zoom: zoom,
    );

    final nextTransform = typedTransform.copyWith(
      currentPosition: localPosition,
      points: result.points,
      activeIndex: result.activeIndex,
      didInsert: result.didInsert,
      shouldDelete: result.shouldDelete,
      hasChanges: result.hasChanges,
    );

    return EditUpdateResult<EditTransform>(transform: nextTransform);
  }

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.finish',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.finish',
    );
    if (!typedTransform.hasChanges) {
      return state.copyWith(application: state.application.toIdle());
    }

    var points = List<DrawPoint>.from(typedTransform.points);
    if (typedTransform.shouldDelete &&
        typedTransform.activeIndex != null &&
        typedTransform.activeIndex! > 0 &&
        typedTransform.activeIndex! < points.length - 1) {
      points.removeAt(typedTransform.activeIndex!);
    }

    if (points.length < 2) {
      return state.copyWith(application: state.application.toIdle());
    }

    final element = state.domain.document.getElementById(typedContext.elementId);
    if (element == null || element.data is! ArrowData) {
      return state.copyWith(application: state.application.toIdle());
    }

    final data = element.data as ArrowData;
    final rect = _calculateArrowRect(
      points: points,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: points,
      rect: rect,
    );

    final updatedData = data.copyWith(
      points: normalized,
    );
    final updatedElement = element.copyWith(rect: rect, data: updatedData);
    final updatedElements = EditApply.replaceElementsById(
      elements: state.domain.document.elements,
      replacementsById: {updatedElement.id: updatedElement},
    );

    return state.copyWith(
      domain: state.domain.copyWith(
        document: state.domain.document.copyWith(elements: updatedElements),
      ),
      application: state.application.copyWith(interaction: const IdleState()),
    );
  }

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.buildPreview',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.buildPreview',
    );
    if (!typedTransform.hasChanges) {
      return EditPreview.none;
    }

    final element = state.domain.document.getElementById(typedContext.elementId);
    if (element == null || element.data is! ArrowData) {
      return EditPreview.none;
    }

    final data = element.data as ArrowData;
    final rect = _calculateArrowRect(
      points: typedTransform.points,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: typedTransform.points,
      rect: rect,
    );

    final updatedData = data.copyWith(
      points: normalized,
    );
    final updatedElement = element.copyWith(rect: rect, data: updatedData);

    return buildEditPreview(
      state: state,
      context: typedContext,
      previewElementsById: {updatedElement.id: updatedElement},
    );
  }
}

@immutable
final class ArrowPointEditContext extends EditContext {
  const ArrowPointEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
    required this.elementId,
    required this.elementRect,
    required this.rotation,
    required this.initialPoints,
    required this.pointKind,
    required this.pointIndex,
    required this.dragOffset,
  });

  final String elementId;
  final DrawRect elementRect;
  final double rotation;
  final List<DrawPoint> initialPoints;
  final ArrowPointKind pointKind;
  final int pointIndex;
  final DrawPoint dragOffset;
}

@immutable
final class _ArrowPointComputation {
  const _ArrowPointComputation({
    required this.points,
    required this.didInsert,
    required this.shouldDelete,
    required this.activeIndex,
    required this.hasChanges,
  });

  final List<DrawPoint> points;
  final bool didInsert;
  final bool shouldDelete;
  final int? activeIndex;
  final bool hasChanges;
}

_ArrowPointComputation _compute({
  required ArrowPointEditContext context,
  required DrawPoint currentPosition,
  required bool didInsert,
  required DrawConfig config,
  required double zoom,
}) {
  final basePoints = List<DrawPoint>.from(context.initialPoints);
  final effectiveZoom = zoom == 0 ? 1.0 : zoom;
  final handleTolerance =
      config.selection.interaction.handleTolerance / effectiveZoom;
  final addThreshold = handleTolerance;
  final deleteThreshold = handleTolerance;
  final loopThreshold = handleTolerance * 1.5;

  final target = currentPosition.translate(context.dragOffset);
  var updatedPoints = basePoints;
  var nextDidInsert = didInsert;
  int? activeIndex;

  if (context.pointKind == ArrowPointKind.addable) {
    if (context.pointIndex < 0 ||
        context.pointIndex >= basePoints.length - 1) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: false,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
      );
    }
    if (!nextDidInsert) {
      final distanceSq =
          currentPosition.distanceSquared(context.startPosition);
      if (distanceSq >= addThreshold * addThreshold) {
        nextDidInsert = true;
      } else {
        return _ArrowPointComputation(
          points: basePoints,
          didInsert: false,
          shouldDelete: false,
          activeIndex: null,
          hasChanges: false,
        );
      }
    }
    activeIndex = context.pointIndex + 1;
    updatedPoints = List<DrawPoint>.from(basePoints)
      ..insert(activeIndex, target);
  } else {
    final index = switch (context.pointKind) {
      ArrowPointKind.loopStart => 0,
      ArrowPointKind.loopEnd => basePoints.length - 1,
      _ => context.pointIndex,
    };
    if (index < 0 || index >= basePoints.length) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: nextDidInsert,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
      );
    }
    updatedPoints = List<DrawPoint>.from(basePoints);
    updatedPoints[index] = target;
    activeIndex = index;
  }

  if (activeIndex == 0 || activeIndex == updatedPoints.length - 1) {
    final start = updatedPoints.first;
    final end = updatedPoints.last;
    if (start.distanceSquared(end) <= loopThreshold * loopThreshold) {
      if (activeIndex == 0) {
        updatedPoints[0] = end;
      } else {
        updatedPoints[updatedPoints.length - 1] = start;
      }
    }
  }

  var shouldDelete = false;
  final resolvedIndex = activeIndex;
  if (resolvedIndex > 0 && resolvedIndex < updatedPoints.length - 1) {
    final targetPoint = updatedPoints[resolvedIndex];
    final prev = updatedPoints[resolvedIndex - 1];
    final next = updatedPoints[resolvedIndex + 1];
    if (targetPoint.distanceSquared(prev) <=
            deleteThreshold * deleteThreshold ||
        targetPoint.distanceSquared(next) <=
            deleteThreshold * deleteThreshold) {
      shouldDelete = true;
    }
  }

  final hasChanges = !_pointsEqual(basePoints, updatedPoints) || nextDidInsert;

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    didInsert: nextDidInsert,
    shouldDelete: shouldDelete,
    activeIndex: activeIndex,
    hasChanges: hasChanges,
  );
}

/// Calculates accurate bounding rect for arrow, accounting for curved paths.
DrawRect _calculateArrowRect({
  required List<DrawPoint> points,
  required ArrowType arrowType,
  required double strokeWidth,
}) {
  return ArrowGeometry.calculatePathBounds(
    worldPoints: points,
    arrowType: arrowType,
  );
}

DrawRect _rectFromPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var minY = points.first.y;
  var maxX = points.first.x;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    if (point.x < minX) {
      minX = point.x;
    }
    if (point.y < minY) {
      minY = point.y;
    }
    if (point.x > maxX) {
      maxX = point.x;
    }
    if (point.y > maxY) {
      maxY = point.y;
    }
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

List<DrawPoint> _resolveWorldPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

DrawPoint _resolvePointPosition({
  required List<DrawPoint> points,
  required ArrowPointKind kind,
  required int index,
  required ArrowType arrowType,
}) {
  if (kind == ArrowPointKind.addable) {
    if (index < 0 || index >= points.length - 1) {
      return points.first;
    }

    // For curved arrows with 3+ points, calculate point on the actual curve
    if (arrowType == ArrowType.curved && points.length >= 3) {
      final offsetPoints = points
          .map((p) => Offset(p.x, p.y))
          .toList(growable: false);
      final curvePoint = ArrowGeometry.calculateCurvePoint(
        points: offsetPoints,
        segmentIndex: index,
        t: 0.5,
      );
      if (curvePoint != null) {
        return DrawPoint(x: curvePoint.dx, y: curvePoint.dy);
      }
    }

    // For straight and polyline arrows, use linear midpoint
    final start = points[index];
    final end = points[index + 1];
    return DrawPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2);
  }
  final resolvedIndex = switch (kind) {
    ArrowPointKind.loopStart => 0,
    ArrowPointKind.loopEnd => points.length - 1,
    _ => index,
  };
  return points[resolvedIndex.clamp(0, points.length - 1)];
}

DrawPoint _toLocalPosition(
  DrawRect rect,
  double rotation,
  DrawPoint position,
) {
  if (rotation == 0) {
    return position;
  }
  final space = ElementSpace(rotation: rotation, origin: rect.center);
  return space.fromWorld(position);
}

bool _pointsEqual(List<DrawPoint> a, List<DrawPoint> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
