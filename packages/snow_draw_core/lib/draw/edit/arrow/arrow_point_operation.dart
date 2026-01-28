import 'dart:ui';

import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/arrow_polyline_binding_adjuster.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/rectangle/rectangle_data.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_style.dart';
import '../../utils/snapping_mode.dart';
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
      throw const EditMissingDataError(
        dataName: 'arrow element',
        operationName: 'ArrowPointOperation.createContext',
      );
    }
    final data = element.data as ArrowData;
    final rawPoints = _resolveWorldPoints(element, data);
    final useVirtualPoints =
        data.arrowType == ArrowType.polyline &&
        typedParams.pointKind == ArrowPointKind.addable;
    final points = _resolveWorldPoints(
      element,
      data,
      includeVirtual: useVirtualPoints,
    );
    if (points.length < 2) {
      throw const EditMissingDataError(
        dataName: 'arrow points',
        operationName: 'ArrowPointOperation.createContext',
      );
    }

    final addableBendControls =
        useVirtualPoints
            ? ArrowPointUtils.resolvePolylineBendControlSegments(
                elementId: element.id,
                data: data,
                rawPoints: rawPoints,
                segmentPoints: points,
              )
            : const <bool>[];
    final isBendControlSegment =
        useVirtualPoints &&
        typedParams.pointIndex >= 0 &&
        typedParams.pointIndex < addableBendControls.length &&
        addableBendControls[typedParams.pointIndex];

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
      arrowType: data.arrowType,
      pointKind: typedParams.pointKind,
      pointIndex: typedParams.pointIndex,
      isBendControlSegment: isBendControlSegment,
      dragOffset: dragOffset,
      bindingTargetCache: BindingTargetCache(),
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
    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    final data = element?.data is ArrowData
        ? element!.data as ArrowData
        : null;
    return ArrowPointTransform(
      currentPosition: startPosition,
      points: typedContext.initialPoints,
      startBinding: data?.startBinding,
      endBinding: data?.endBinding,
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

    var localPosition = _toLocalPosition(
      typedContext.elementRect,
      typedContext.rotation,
      currentPosition,
    );
    final snapConfig = config.snap;
    final gridConfig = config.grid;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: modifiers.snapOverride,
    );
    final shouldGridSnap = snappingMode == SnappingMode.grid;
    if (shouldGridSnap) {
      final target = localPosition.translate(typedContext.dragOffset);
      final snappedTarget = _snapTargetToGrid(
        target: target,
        rect: typedContext.elementRect,
        rotation: typedContext.rotation,
        gridSize: gridConfig.size,
      );
      localPosition = snappedTarget - typedContext.dragOffset;
    }

    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    final data = element?.data is ArrowData
        ? element!.data as ArrowData
        : null;
    final zoom = state.application.view.camera.zoom;
    final effectiveZoom = zoom == 0 ? 1.0 : zoom;
    final bindingDistance = snapConfig.arrowBindingDistance / effectiveZoom;
    final bindingSearchDistance =
        ArrowBindingUtils.resolveBindingSearchDistance(bindingDistance);
    final allowNewBinding =
        snapConfig.enableArrowBinding &&
        !modifiers.snapOverride &&
        snappingMode != SnappingMode.grid;
    final bindingSearchPoint = _toWorldPosition(
      typedContext.elementRect,
      typedContext.rotation,
      localPosition.translate(typedContext.dragOffset),
    );
    final bindingTargets =
        element == null || bindingDistance <= 0
            ? const <ElementState>[]
            : _resolveBindingTargetsCached(
                state: state,
                context: typedContext,
                position: bindingSearchPoint,
                distance: bindingSearchDistance,
              );
    final result = _compute(
      context: typedContext,
      currentPosition: localPosition,
      didInsert: typedTransform.didInsert,
      config: config,
      zoom: zoom,
      startBinding: typedTransform.startBinding ?? data?.startBinding,
      endBinding: typedTransform.endBinding ?? data?.endBinding,
      bindingTargets: bindingTargets,
      bindingDistance: bindingDistance,
      allowNewBinding: allowNewBinding,
    );

    final nextTransform = typedTransform.copyWith(
      currentPosition: localPosition,
      points: result.points,
      activeIndex: result.activeIndex,
      didInsert: result.didInsert,
      shouldDelete: result.shouldDelete,
      hasChanges: result.hasChanges,
      startBinding: result.startBinding,
      endBinding: result.endBinding,
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

    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    if (element == null || element.data is! ArrowData) {
      return state.copyWith(application: state.application.toIdle());
    }

    final data = element.data as ArrowData;
    if (data.arrowType == ArrowType.polyline) {
      points = List<DrawPoint>.from(
        ArrowGeometry.normalizePolylinePoints(points),
      );
    }

    // Transform local-space points to world space, then back to local space
    // with the new rect center. This preserves world-space positions while
    // keeping the same rotation angle.
    final result = computeArrowRectAndPoints(
      localPoints: points,
      oldRect: typedContext.elementRect,
      rotation: typedContext.rotation,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );

    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: result.localPoints,
      rect: result.rect,
    );

    final updatedData = data.copyWith(
      points: normalized,
      startBinding: typedTransform.startBinding,
      endBinding: typedTransform.endBinding,
    );
    final updatedElement = element.copyWith(
      rect: result.rect,
      data: updatedData,
    );
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

    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    if (element == null || element.data is! ArrowData) {
      return EditPreview.none;
    }

    final data = element.data as ArrowData;

    // Transform local-space points to world space, then back to local space
    // with the new rect center. This preserves world-space positions while
    // keeping the same rotation angle.
    final result = computeArrowRectAndPoints(
      localPoints: typedTransform.points,
      oldRect: typedContext.elementRect,
      rotation: typedContext.rotation,
      arrowType: data.arrowType,
      strokeWidth: data.strokeWidth,
    );

    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: result.localPoints,
      rect: result.rect,
    );

    final updatedData = data.copyWith(
      points: normalized,
      startBinding: typedTransform.startBinding,
      endBinding: typedTransform.endBinding,
    );
    final updatedElement = element.copyWith(
      rect: result.rect,
      data: updatedData,
    );

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
    required this.arrowType,
    required this.pointKind,
    required this.pointIndex,
    required this.isBendControlSegment,
    required this.dragOffset,
    required BindingTargetCache bindingTargetCache,
  }) : _bindingTargetCache = bindingTargetCache;

  final String elementId;
  final DrawRect elementRect;
  final double rotation;
  final List<DrawPoint> initialPoints;
  final ArrowType arrowType;
  final ArrowPointKind pointKind;
  final int pointIndex;
  final bool isBendControlSegment;
  final DrawPoint dragOffset;
  final BindingTargetCache _bindingTargetCache;
}

@immutable
final class _ArrowPointComputation {
  const _ArrowPointComputation({
    required this.points,
    required this.didInsert,
    required this.shouldDelete,
    required this.activeIndex,
    required this.hasChanges,
    required this.startBinding,
    required this.endBinding,
  });

  final List<DrawPoint> points;
  final bool didInsert;
  final bool shouldDelete;
  final int? activeIndex;
  final bool hasChanges;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
}

_ArrowPointComputation _compute({
  required ArrowPointEditContext context,
  required DrawPoint currentPosition,
  required bool didInsert,
  required DrawConfig config,
  required double zoom,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required List<ElementState> bindingTargets,
  required double bindingDistance,
  required bool allowNewBinding,
}) {
  final basePoints = List<DrawPoint>.from(context.initialPoints);
  final effectiveZoom = zoom == 0 ? 1.0 : zoom;
  final handleTolerance =
      config.selection.interaction.handleTolerance / effectiveZoom;
  final addThreshold = handleTolerance;
  final deleteThreshold = handleTolerance;
  final loopThreshold = handleTolerance * 1.5;
  final isPolyline = context.arrowType == ArrowType.polyline;

  var target = currentPosition.translate(context.dragOffset);
  var updatedPoints = basePoints;
  var nextDidInsert = didInsert;
  var nextStartBinding = startBinding;
  var nextEndBinding = endBinding;
  int? activeIndex;

  if (context.pointKind == ArrowPointKind.addable) {
    if (context.pointIndex < 0 || context.pointIndex >= basePoints.length - 1) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: false,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
      );
    }
    if (isPolyline) {
      final isBendControl = context.isBendControlSegment;
      if (!nextDidInsert && !isBendControl) {
        final distanceSq = currentPosition.distanceSquared(
          context.startPosition,
        );
        if (distanceSq >= addThreshold * addThreshold) {
          nextDidInsert = true;
        } else {
          return _ArrowPointComputation(
            points: basePoints,
            didInsert: false,
            shouldDelete: false,
            activeIndex: null,
            hasChanges: false,
            startBinding: nextStartBinding,
            endBinding: nextEndBinding,
          );
        }
      }
      updatedPoints = _movePolylineSegment(
        points: basePoints,
        segmentIndex: context.pointIndex,
        target: target,
      );
      activeIndex = _resolveNearestSegmentIndex(
        points: updatedPoints,
        target: target,
      );
    } else {
      if (!nextDidInsert) {
        final distanceSq = currentPosition.distanceSquared(
          context.startPosition,
        );
        if (distanceSq >= addThreshold * addThreshold) {
          nextDidInsert = true;
        } else {
          return _ArrowPointComputation(
            points: basePoints,
            didInsert: false,
            shouldDelete: false,
            activeIndex: null,
            hasChanges: false,
            startBinding: nextStartBinding,
            endBinding: nextEndBinding,
          );
        }
      }
      activeIndex = context.pointIndex + 1;
      updatedPoints = List<DrawPoint>.from(basePoints)
        ..insert(activeIndex, target);
    }
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
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
      );
    }
    if (isPolyline && index != 0 && index != basePoints.length - 1) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: nextDidInsert,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
      );
    }
    final isEndpoint = index == 0 || index == basePoints.length - 1;
    if (isEndpoint) {
      final existingBinding = index == 0 ? nextStartBinding : nextEndBinding;
      final referencePoint = isPolyline
          ? null
          : basePoints.length > 1
              ? _toWorldPosition(
                  context.elementRect,
                  context.rotation,
                  basePoints[index == 0 ? 1 : basePoints.length - 2],
                )
              : null;
      final candidate = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: _toWorldPosition(
          context.elementRect,
          context.rotation,
          target,
        ),
        targets: bindingTargets,
        snapDistance: bindingDistance,
        preferredBinding: existingBinding,
        allowNewBinding: allowNewBinding,
        referencePoint: referencePoint,
      );
      if (candidate != null) {
        target = _toLocalPosition(
          context.elementRect,
          context.rotation,
          candidate.snapPoint,
        );
        if (index == 0) {
          nextStartBinding = candidate.binding;
        } else {
          nextEndBinding = candidate.binding;
        }
      } else {
        if (index == 0) {
          nextStartBinding = null;
        } else {
          nextEndBinding = null;
        }
      }
    }
    if (isPolyline) {
      updatedPoints = _movePolylineEndpoint(
        points: basePoints,
        index: index,
        target: target,
      );
      activeIndex = index == 0 ? 0 : updatedPoints.length - 1;
      final binding = index == 0 ? nextStartBinding : nextEndBinding;
      if (binding != null) {
        final targetElement =
            _findBindingTarget(bindingTargets, binding.elementId);
        if (targetElement != null) {
          final basePoints = List<DrawPoint>.from(updatedPoints);
          updatedPoints = adjustPolylinePointsForBinding(
            points: updatedPoints,
            binding: binding,
            target: targetElement,
            isStart: index == 0,
          );
          syncPolylineBindingAutoPoints(
            elementId: context.elementId,
            before: basePoints,
            after: updatedPoints,
          );
          activeIndex = index == 0 ? 0 : updatedPoints.length - 1;
        }
      }
    } else {
      updatedPoints = List<DrawPoint>.from(basePoints);
      updatedPoints[index] = target;
      activeIndex = index;
    }
  }

  final resolvedActiveIndex = activeIndex;
  if (context.pointKind != ArrowPointKind.addable &&
      resolvedActiveIndex != null &&
      (resolvedActiveIndex == 0 ||
          resolvedActiveIndex == updatedPoints.length - 1)) {
    final start = updatedPoints.first;
    final end = updatedPoints.last;
    if (start.distanceSquared(end) <= loopThreshold * loopThreshold) {
      if (isPolyline) {
        updatedPoints = _mergePolylineLoopPoints(
          points: updatedPoints,
          activeIndex: resolvedActiveIndex,
        );
        activeIndex =
            resolvedActiveIndex == 0 ? 0 : updatedPoints.length - 1;
      } else {
        if (resolvedActiveIndex == 0) {
          updatedPoints[0] = end;
        } else {
          updatedPoints[updatedPoints.length - 1] = start;
        }
      }
    }
  }

  var shouldDelete = false;
  if (!isPolyline) {
    final resolvedIndex = activeIndex;
    if (resolvedIndex != null &&
        resolvedIndex > 0 &&
        resolvedIndex < updatedPoints.length - 1) {
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
  }

  final hasChanges = !_pointsEqual(basePoints, updatedPoints) || nextDidInsert;
  final bindingChanged =
      nextStartBinding != startBinding || nextEndBinding != endBinding;

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    didInsert: nextDidInsert,
    shouldDelete: shouldDelete,
    activeIndex: activeIndex,
    hasChanges: hasChanges || bindingChanged,
    startBinding: nextStartBinding,
    endBinding: nextEndBinding,
  );
}


List<DrawPoint> _resolveWorldPoints(
  ElementState element,
  ArrowData data, {
  bool includeVirtual = false,
}) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  final effective = data.arrowType == ArrowType.polyline
      ? ArrowGeometry.expandPolylinePoints(
          resolved,
          includeVirtual: includeVirtual,
        )
      : resolved;
  return effective
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}

List<ElementState> _resolveBindingTargets(
  DrawState state,
  String excludeId,
  DrawPoint position,
  double distance,
) {
  final document = state.domain.document;
  final entries = document.spatialIndex.searchPointEntries(position, distance);
  final targets = <ElementState>[];
  for (final entry in entries) {
    final element = document.getElementById(entry.id);
    if (element == null) {
      continue;
    }
    if (element.opacity <= 0 ||
        element.id == excludeId ||
        element.data is! RectangleData) {
      continue;
    }
    targets.add(element);
  }
  return targets;
}

ElementState? _findBindingTarget(List<ElementState> targets, String targetId) {
  for (final target in targets) {
    if (target.id == targetId) {
      return target;
    }
  }
  return null;
}

List<ElementState> _resolveBindingTargetsCached({
  required DrawState state,
  required ArrowPointEditContext context,
  required DrawPoint position,
  required double distance,
}) {
  final cache = context._bindingTargetCache;
  final elementsVersion = state.domain.document.elementsVersion;
  final threshold = distance * 0.4;
  if (cache.isValid(
    position: position,
    threshold: threshold,
    distance: distance,
    elementsVersion: elementsVersion,
  )) {
    return cache.targets;
  }

  final targets = _resolveBindingTargets(
    state,
    context.elementId,
    position,
    distance,
  );
  cache.update(
    position: position,
    distance: distance,
    elementsVersion: elementsVersion,
    targets: targets,
  );
  return targets;
}

class BindingTargetCache {
  DrawPoint? _lastPosition;
  double _lastDistance = 0;
  var _elementsVersion = -1;
  List<ElementState> _targets = const [];

  List<ElementState> get targets => _targets;

  bool isValid({
    required DrawPoint position,
    required double threshold,
    required double distance,
    required int elementsVersion,
  }) {
    if (_lastPosition == null) {
      return false;
    }
    if (_elementsVersion != elementsVersion) {
      return false;
    }
    if (_lastDistance != distance) {
      return false;
    }
    if (threshold <= 0) {
      return false;
    }
    return _lastPosition!.distanceSquared(position) <= threshold * threshold;
  }

  void update({
    required DrawPoint position,
    required double distance,
    required int elementsVersion,
    required List<ElementState> targets,
  }) {
    _lastPosition = position;
    _lastDistance = distance;
    _elementsVersion = elementsVersion;
    _targets = targets;
  }
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

DrawPoint _toLocalPosition(DrawRect rect, double rotation, DrawPoint position) {
  if (rotation == 0) {
    return position;
  }
  final space = ElementSpace(rotation: rotation, origin: rect.center);
  return space.fromWorld(position);
}

DrawPoint _toWorldPosition(DrawRect rect, double rotation, DrawPoint position) {
  if (rotation == 0) {
    return position;
  }
  final space = ElementSpace(rotation: rotation, origin: rect.center);
  return space.toWorld(position);
}

DrawPoint _snapTargetToGrid({
  required DrawPoint target,
  required DrawRect rect,
  required double rotation,
  required double gridSize,
}) {
  if (gridSize <= 0) {
    return target;
  }
  final worldTarget = _toWorldPosition(rect, rotation, target);
  final snappedWorld = gridSnapService.snapPoint(
    point: worldTarget,
    gridSize: gridSize,
  );
  return _toLocalPosition(rect, rotation, snappedWorld);
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

List<DrawPoint> _movePolylineSegment({
  required List<DrawPoint> points,
  required int segmentIndex,
  required DrawPoint target,
}) {
  if (segmentIndex < 0 || segmentIndex >= points.length - 1) {
    return points;
  }
  if (segmentIndex == 0 || segmentIndex == points.length - 2) {
    return _offsetPolylineEndpointSegment(
      points: points,
      segmentIndex: segmentIndex,
      target: target,
    );
  }
  final start = points[segmentIndex];
  final end = points[segmentIndex + 1];
  final isHorizontal = _segmentIsHorizontal(start, end);
  final updated = List<DrawPoint>.from(points);
  if (isHorizontal) {
    updated[segmentIndex] = DrawPoint(x: start.x, y: target.y);
    updated[segmentIndex + 1] = DrawPoint(x: end.x, y: target.y);
  } else {
    updated[segmentIndex] = DrawPoint(x: target.x, y: start.y);
    updated[segmentIndex + 1] = DrawPoint(x: target.x, y: end.y);
  }
  return updated;
}

List<DrawPoint> _offsetPolylineEndpointSegment({
  required List<DrawPoint> points,
  required int segmentIndex,
  required DrawPoint target,
}) {
  if (points.length < 2 ||
      segmentIndex < 0 ||
      segmentIndex >= points.length - 1) {
    return points;
  }
  final start = points[segmentIndex];
  final end = points[segmentIndex + 1];
  final isHorizontal = _segmentIsHorizontal(start, end);
  final movedStart = isHorizontal
      ? DrawPoint(x: start.x, y: target.y)
      : DrawPoint(x: target.x, y: start.y);
  final movedEnd = isHorizontal
      ? DrawPoint(x: end.x, y: target.y)
      : DrawPoint(x: target.x, y: end.y);
  if (points.length == 2 && segmentIndex == 0) {
    return [start, movedStart, movedEnd, end];
  }
  if (segmentIndex == 0) {
    return [start, movedStart, movedEnd, ...points.sublist(2)];
  }
  return [...points.sublist(0, points.length - 2), movedStart, movedEnd, end];
}

int? _resolveNearestSegmentIndex({
  required List<DrawPoint> points,
  required DrawPoint target,
}) {
  if (points.length < 2) {
    return null;
  }
  var nearestIndex = 0;
  var nearestDistance = double.infinity;
  for (var i = 0; i < points.length - 1; i++) {
    final mid = DrawPoint(
      x: (points[i].x + points[i + 1].x) / 2,
      y: (points[i].y + points[i + 1].y) / 2,
    );
    final distance = target.distanceSquared(mid);
    if (distance < nearestDistance) {
      nearestDistance = distance;
      nearestIndex = i;
    }
  }
  return nearestIndex;
}

List<DrawPoint> _movePolylineEndpoint({
  required List<DrawPoint> points,
  required int index,
  required DrawPoint target,
}) {
  final updated = List<DrawPoint>.from(points);
  if (index < 0 || index >= updated.length) {
    return updated;
  }
  updated[index] = target;
  if (updated.length < 3) {
    return updated;
  }
  if (index == 0) {
    final next = updated[1];
    final wasHorizontal = _segmentIsHorizontal(points[0], points[1]);
    updated[1] = DrawPoint(
      x: wasHorizontal ? next.x : target.x,
      y: wasHorizontal ? target.y : next.y,
    );
  } else if (index == updated.length - 1) {
    final prev = updated[updated.length - 2];
    final wasHorizontal = _segmentIsHorizontal(
      points[points.length - 2],
      points[points.length - 1],
    );
    updated[updated.length - 2] = DrawPoint(
      x: wasHorizontal ? prev.x : target.x,
      y: wasHorizontal ? target.y : prev.y,
    );
  }
  return updated;
}

DrawPoint _alignPolylineNeighbor({
  required DrawPoint anchor,
  required DrawPoint neighbor,
  required bool wasHorizontal,
}) =>
    wasHorizontal
        ? DrawPoint(x: neighbor.x, y: anchor.y)
        : DrawPoint(x: anchor.x, y: neighbor.y);

List<DrawPoint> _mergePolylineLoopPoints({
  required List<DrawPoint> points,
  required int activeIndex,
}) {
  if (points.length < 2) {
    return List<DrawPoint>.from(points);
  }

  final updated = List<DrawPoint>.from(points);
  final lastIndex = updated.length - 1;

  if (activeIndex == 0) {
    final end = updated[lastIndex];
    updated[0] = end;
    if (updated.length > 1) {
      final wasHorizontal = _segmentIsHorizontal(points[0], points[1]);
      updated[1] = _alignPolylineNeighbor(
        anchor: end,
        neighbor: updated[1],
        wasHorizontal: wasHorizontal,
      );
    }
  } else if (activeIndex == lastIndex) {
    final start = updated[0];
    updated[lastIndex] = start;
    if (updated.length > 1) {
      final wasHorizontal = _segmentIsHorizontal(
        points[lastIndex - 1],
        points[lastIndex],
      );
      updated[lastIndex - 1] = _alignPolylineNeighbor(
        anchor: start,
        neighbor: updated[lastIndex - 1],
        wasHorizontal: wasHorizontal,
      );
    }
  }

  return updated;
}

bool _segmentIsHorizontal(DrawPoint start, DrawPoint end) =>
    ArrowGeometry.isPolylineSegmentHorizontal(start, end);
