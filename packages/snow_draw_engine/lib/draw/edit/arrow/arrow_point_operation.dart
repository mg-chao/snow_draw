import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_core_bridge.dart';
import '../../elements/types/arrow/arrow_core_ops.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_focus.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/arrow/arrow_two_point_layout.dart';
import '../../elements/types/arrow/elbow/elbow_editing.dart';
import '../../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../../elements/types/line/line_data.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/selection_overlay_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_style.dart';
import '../../utils/arrow_point_metrics.dart';
import '../../utils/camera_zoom.dart';
import '../../utils/combined_element_lookup.dart';
import '../../utils/list_equality.dart';
import '../../utils/snapping_mode.dart';
import '../core/edit_computed_result.dart';
import '../core/edit_errors.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../core/standard_finish_mixin.dart';

class ArrowPointOperation extends EditOperation with StandardFinishMixin {
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
    if (element == null || element.data is! ArrowLikeData) {
      throw const EditMissingDataError(
        dataName: 'arrow element',
        operationName: 'ArrowPointOperation.createContext',
      );
    }
    final data = element.data as ArrowLikeData;
    final resolved = ArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
    final points = List<DrawPoint>.unmodifiable(resolved);
    if (points.length < 2) {
      throw const EditMissingDataError(
        dataName: 'arrow points',
        operationName: 'ArrowPointOperation.createContext',
      );
    }
    final fixedSegments = data.fixedSegments ?? const [];
    final shouldReleaseSegment =
        typedParams.isDoubleClick &&
        data.arrowType == ArrowType.elbow &&
        typedParams.pointKind == ArrowPointKind.addable &&
        fixedSegments.any(
          (segment) => segment.index == typedParams.pointIndex + 1,
        );
    final shouldDeletePoint =
        typedParams.isDoubleClick &&
        !shouldReleaseSegment &&
        typedParams.pointKind == ArrowPointKind.turning &&
        typedParams.pointIndex > 0 &&
        typedParams.pointIndex < points.length - 1;

    final startBounds = requireSelectionBounds(
      selectionData: SelectionDataComputer.compute(state),
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'ArrowPointOperation.createContext',
    );
    final elementSpace = element.rotation == 0
        ? null
        : ElementSpace(rotation: element.rotation, origin: element.rect.center);

    final localStartPosition = elementSpace?.fromWorld(position) ?? position;
    final pointPosition = _resolvePointPosition(
      state: state,
      element: element,
      data: data,
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
      initialFixedSegments: List<ElbowFixedSegment>.unmodifiable(fixedSegments),
      arrowType: data.arrowType,
      pointKind: typedParams.pointKind,
      pointIndex: typedParams.pointIndex,
      dragOffset: dragOffset,
      baseElement: element,
      elementSpace: elementSpace,
      releaseFixedSegment: shouldReleaseSegment,
      deletePointOnStart: shouldDeletePoint,
      isLineElement: data is LineData,
      startArrowhead: data.startArrowhead,
      endArrowhead: data.endArrowhead,
      initialStartBinding: data.startBinding,
      initialEndBinding: data.endBinding,
      hasBindableTargets: state.domain.document.hasArrowBindableElements,
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
    final baseElement = typedContext.baseElement;
    final data = baseElement.data as ArrowLikeData;
    var points = typedContext.initialPoints;
    var fixedSegments = data.fixedSegments;
    var hasChanges = false;
    if (typedContext.deletePointOnStart) {
      return ArrowPointTransform(
        currentPosition: startPosition,
        points: points,
        fixedSegments: fixedSegments,
        startBinding: data.startBinding,
        endBinding: data.endBinding,
        activeIndex: typedContext.pointIndex,
        shouldDelete: true,
        hasChanges: true,
      );
    }
    final arrowData = data is ArrowData ? data : null;
    if (typedContext.releaseFixedSegment &&
        arrowData != null &&
        data.arrowType == ArrowType.elbow) {
      final segmentIndex = typedContext.pointIndex + 1;
      final currentArrow = toCoreArrowState(
        element: baseElement,
        data: data,
        localPointsOverride: points,
        fixedSegmentsOverride: fixedSegments,
        startBindingOverride: data.startBinding,
        endBindingOverride: data.endBinding,
      );
      final releasePatch = releaseCoreFixedSegment(
        arrow: currentArrow,
        segmentIndex: segmentIndex,
      );
      final releasedArrow = core.applyArrowPatch(currentArrow, releasePatch);
      final updatedFixed = toLocalFixedSegmentsFromCoreArrow(
        releasedArrow,
        baseElement,
      );
      final updated = computeElbowEdit(
        element: baseElement,
        data: arrowData,
        lookup: CombinedElementLookup(base: state.domain.document.elementMap),
        localPointsOverride: points,
        fixedSegmentsOverride: updatedFixed,
        engineContext: _coreContextForState(
          state: state,
          isBindingEnabled: true,
        ),
      );
      points = updated.localPoints;
      fixedSegments = updated.fixedSegments;
      hasChanges = true;
    }
    return ArrowPointTransform(
      currentPosition: startPosition,
      points: points,
      fixedSegments: fixedSegments,
      startBinding: data.startBinding,
      endBinding: data.endBinding,
      hasChanges: hasChanges,
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
    if (typedContext.releaseFixedSegment || typedContext.deletePointOnStart) {
      return EditUpdateResult<EditTransform>(transform: typedTransform);
    }

    var localPosition = typedContext.toLocal(currentPosition);
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
        context: typedContext,
        gridSize: gridConfig.size,
      );
      localPosition = snappedTarget - typedContext.dragOffset;
    }

    final startBinding =
        typedTransform.startBinding ?? typedContext.initialStartBinding;
    final endBinding =
        typedTransform.endBinding ?? typedContext.initialEndBinding;
    final shouldLookupBindings =
        _requiresBindingLookup(typedContext) &&
        (typedContext.hasBindableTargets ||
            startBinding != null ||
            endBinding != null);
    final allowNewBinding =
        snapConfig.enableArrowBinding &&
        !modifiers.snapOverride &&
        snappingMode != SnappingMode.grid;
    final bindingDistance = shouldLookupBindings
        ? resolveZoomAdjustedDistance(
            distance: snapConfig.arrowBindingDistance,
            zoom: state.application.view.camera.zoom,
          )
        : 0.0;
    final coreEngineContext = _coreContextForState(
      state: state,
      isBindingEnabled: snapConfig.enableArrowBinding,
    );

    final result = _compute(
      state: state,
      context: typedContext,
      currentPosition: localPosition,
      didInsert: typedTransform.didInsert,
      modifiers: modifiers,
      config: config,
      startBinding: startBinding,
      endBinding: endBinding,
      startArrowhead: typedContext.startArrowhead,
      endArrowhead: typedContext.endArrowhead,
      shouldLookupBindings: shouldLookupBindings,
      bindingDistance: bindingDistance,
      allowNewBinding: allowNewBinding,
      coreEngineContext: coreEngineContext,
    );

    if (_isNoOpArrowTransformUpdate(previous: typedTransform, next: result)) {
      return EditUpdateResult<EditTransform>(transform: typedTransform);
    }

    final nextTransform = typedTransform.copyWith(
      currentPosition: localPosition,
      points: result.points,
      fixedSegments: result.fixedSegments,
      activeIndex: result.activeIndex,
      didInsert: result.didInsert,
      shouldDelete: result.shouldDelete,
      hasChanges: result.hasChanges,
      startBinding: result.startBinding,
      endBinding: result.endBinding,
      orderedElementIds: result.orderedElementIds,
    );

    return EditUpdateResult<EditTransform>(transform: nextTransform);
  }

  @override
  EditComputedResult? computeResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => _computeArrowResult(
    state: state,
    context: context,
    transform: transform,
    applyDeletion: false,
  );

  @override
  EditComputedResult? computeFinishResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) => _computeArrowResult(
    state: state,
    context: context,
    transform: transform,
    applyDeletion: true,
  );

  @override
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  }) => current;

  EditComputedResult? _computeArrowResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
    required bool applyDeletion,
  }) {
    final typedContext = requireContext<ArrowPointEditContext>(
      context,
      operationName: 'ArrowPointOperation.computeResult',
    );
    final typedTransform = requireTransform<ArrowPointTransform>(
      transform,
      operationName: 'ArrowPointOperation.computeResult',
    );
    if (!typedTransform.hasChanges) {
      return null;
    }

    final localPoints = applyDeletion
        ? _applyPointDeletion(typedTransform)
        : typedTransform.points;
    if (localPoints.length < 2) {
      return null;
    }

    final updatedElement = _buildUpdatedElement(
      element: typedContext.baseElement,
      context: typedContext,
      transform: typedTransform,
      elementMap: state.domain.document.elementMap,
      localPoints: localPoints,
      coreEngineContext: _coreContextForState(
        state: state,
        isBindingEnabled: true,
      ),
      finalize: applyDeletion,
    );

    return EditComputedResult(
      updatedElements: {updatedElement.id: updatedElement},
      orderedElementIds: typedTransform.orderedElementIds,
    );
  }
}

/// Removes the active point when [ArrowPointTransform.shouldDelete] is set.
///
/// Returns the original points list when no deletion is needed.
List<DrawPoint> _applyPointDeletion(ArrowPointTransform transform) {
  if (!transform.shouldDelete ||
      transform.activeIndex == null ||
      transform.activeIndex! <= 0 ||
      transform.activeIndex! >= transform.points.length - 1) {
    return transform.points;
  }
  return List<DrawPoint>.from(transform.points)
    ..removeAt(transform.activeIndex!);
}

/// Builds the updated [ElementState] for both `finish` and `buildPreview`,
/// eliminating the duplicated elbow-edit + rect/normalize pipeline.
ElementState _buildUpdatedElement({
  required ElementState element,
  required ArrowPointEditContext context,
  required ArrowPointTransform transform,
  required Map<String, ElementState> elementMap,
  required List<DrawPoint> localPoints,
  required core.EngineContext coreEngineContext,
  bool finalize = false,
}) {
  final data = element.data as ArrowLikeData;
  final arrowData = data is ArrowData ? data : null;
  final dataWithBindings = data.copyWith(
    startBinding: transform.startBinding,
    endBinding: transform.endBinding,
  );
  if (data.arrowType != ArrowType.elbow &&
      context.rotation == 0 &&
      localPoints.length == 2) {
    final layout = computeArrowTwoPointLayout(
      first: localPoints.first,
      second: localPoints.last,
    );
    final updatedData = dataWithBindings.copyWith(
      points: layout.normalizedPoints,
    );
    return element.copyWith(rect: layout.rect, data: updatedData);
  }
  if (data.arrowType == ArrowType.elbow && arrowData != null) {
    final fixedSegments =
        transform.fixedSegments ?? const <ElbowFixedSegment>[];
    final elbowData = arrowData.copyWith(
      startBinding: transform.startBinding,
      endBinding: transform.endBinding,
    );
    final updated = computeElbowEdit(
      element: element,
      data: elbowData,
      lookup: CombinedElementLookup(base: elementMap),
      localPointsOverride: localPoints,
      fixedSegmentsOverride: fixedSegments,
      engineContext: coreEngineContext,
      finalize: finalize,
    );
    final geometry = resolveArrowGeometryUpdate(
      localPoints: updated.localPoints,
      oldRect: context.elementRect,
      rotation: context.rotation,
      arrowType: data.arrowType,
    );
    final transformedFixedSegments = transformFixedSegments(
      segments: updated.fixedSegments,
      oldRect: context.elementRect,
      newRect: geometry.rect,
      rotation: context.rotation,
    );
    final updatedData = dataWithBindings.copyWith(
      points: geometry.normalizedPoints,
      fixedSegments: transformedFixedSegments,
      startIsSpecial: updated.startIsSpecial,
      endIsSpecial: updated.endIsSpecial,
    );
    return element.copyWith(rect: geometry.rect, data: updatedData);
  }

  final geometry = resolveArrowGeometryUpdate(
    localPoints: localPoints,
    oldRect: context.elementRect,
    rotation: context.rotation,
    arrowType: data.arrowType,
  );
  final updatedData = dataWithBindings.copyWith(
    points: geometry.normalizedPoints,
  );
  return element.copyWith(rect: geometry.rect, data: updatedData);
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
    required this.initialFixedSegments,
    required this.arrowType,
    required this.pointKind,
    required this.pointIndex,
    required this.dragOffset,
    required this.baseElement,
    required ElementSpace? elementSpace,
    required this.releaseFixedSegment,
    required this.deletePointOnStart,
    required this.startArrowhead,
    required this.endArrowhead,
    required this.initialStartBinding,
    required this.initialEndBinding,
    required this.hasBindableTargets,
    this.isLineElement = false,
  }) : _elementSpace = elementSpace;

  final String elementId;
  final DrawRect elementRect;
  final double rotation;
  final List<DrawPoint> initialPoints;
  final List<ElbowFixedSegment> initialFixedSegments;
  final ArrowType arrowType;
  final ArrowPointKind pointKind;
  final int pointIndex;
  final DrawPoint dragOffset;
  final ElementState baseElement;
  final bool releaseFixedSegment;
  final bool deletePointOnStart;
  final bool isLineElement;
  final ArrowheadStyle startArrowhead;
  final ArrowheadStyle endArrowhead;
  final ArrowBinding? initialStartBinding;
  final ArrowBinding? initialEndBinding;
  final bool hasBindableTargets;
  final ElementSpace? _elementSpace;

  @override
  bool get hasSnapshots => initialPoints.length >= 2;

  DrawPoint toLocal(DrawPoint position) {
    final space = _elementSpace;
    return space == null ? position : space.fromWorld(position);
  }

  DrawPoint toWorld(DrawPoint position) {
    final space = _elementSpace;
    return space == null ? position : space.toWorld(position);
  }
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
    required this.fixedSegments,
    required this.orderedElementIds,
  });

  final List<DrawPoint> points;
  final bool didInsert;
  final bool shouldDelete;
  final int? activeIndex;
  final bool hasChanges;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final List<ElbowFixedSegment>? fixedSegments;
  final List<String>? orderedElementIds;
}

bool _isNoOpArrowTransformUpdate({
  required ArrowPointTransform previous,
  required _ArrowPointComputation next,
}) =>
    previous.didInsert == next.didInsert &&
    previous.shouldDelete == next.shouldDelete &&
    previous.hasChanges == next.hasChanges &&
    previous.activeIndex == next.activeIndex &&
    previous.startBinding == next.startBinding &&
    previous.endBinding == next.endBinding &&
    nullableListEquals(previous.orderedElementIds, next.orderedElementIds) &&
    pointListEquals(previous.points, next.points) &&
    fixedSegmentStructureEquals(previous.fixedSegments, next.fixedSegments);

_ArrowPointComputation _compute({
  required DrawState state,
  required ArrowPointEditContext context,
  required DrawPoint currentPosition,
  required bool didInsert,
  required EditModifiers modifiers,
  required DrawConfig config,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  required bool shouldLookupBindings,
  required double bindingDistance,
  required bool allowNewBinding,
  required core.EngineContext coreEngineContext,
}) {
  final basePoints = context.initialPoints;
  final baseFixedSegments = context.initialFixedSegments;
  final handleTolerance = resolveZoomAdjustedDistance(
    distance: config.selection.interaction.handleTolerance,
    zoom: state.application.view.camera.zoom,
  );
  final thresholdSquared = handleTolerance * handleTolerance;
  final loopThreshold = resolveArrowPointLoopThreshold(handleTolerance);
  final baseFixedSegmentsResult = baseFixedSegments.isEmpty
      ? null
      : baseFixedSegments;

  var target = currentPosition.translate(context.dragOffset);
  var updatedPoints = basePoints;
  var nextDidInsert = didInsert;
  final nextStartBinding = startBinding;
  final nextEndBinding = endBinding;
  late final int activeIndex;

  final focusEndpoint = _resolveFocusEndpoint(context.pointKind);
  if (focusEndpoint != null) {
    return _computeFocusComputation(
      state: state,
      context: context,
      basePoints: basePoints,
      baseFixedSegments: baseFixedSegmentsResult,
      target: target,
      startBinding: startBinding,
      endBinding: endBinding,
      endpoint: focusEndpoint,
      switchToInsideBinding: modifiers.fromCenter,
      coreEngineContext: coreEngineContext,
    );
  }

  if (context.pointKind == ArrowPointKind.addable) {
    final hasValidPointIndex = _isValidAddablePointIndex(
      index: context.pointIndex,
      pointCount: basePoints.length,
    );
    if (!hasValidPointIndex) {
      return _noOpComputation(
        points: basePoints,
        didInsert: false,
        startBinding: startBinding,
        endBinding: endBinding,
        fixedSegments: baseFixedSegmentsResult,
      );
    }
    if (context.arrowType == ArrowType.elbow) {
      return _computeElbowAddableComputation(
        state: state,
        context: context,
        target: target,
        basePoints: basePoints,
        baseFixedSegments: baseFixedSegments,
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
        coreEngineContext: coreEngineContext,
      );
    }
    if (!nextDidInsert) {
      final distanceSq = currentPosition.distanceSquared(context.startPosition);
      if (distanceSq >= thresholdSquared) {
        nextDidInsert = true;
      } else {
        return _noOpComputation(
          points: basePoints,
          didInsert: false,
          startBinding: startBinding,
          endBinding: endBinding,
          fixedSegments: baseFixedSegmentsResult,
        );
      }
    }
    activeIndex = context.pointIndex + 1;
    updatedPoints = List<DrawPoint>.from(basePoints)
      ..insert(activeIndex, target);
  } else {
    final index = _resolveDraggedPointIndex(
      pointKind: context.pointKind,
      pointIndex: context.pointIndex,
      pointCount: basePoints.length,
    );
    if (index == null) {
      return _noOpComputation(
        points: basePoints,
        didInsert: nextDidInsert,
        startBinding: startBinding,
        endBinding: endBinding,
        fixedSegments: baseFixedSegmentsResult,
      );
    }
    final isEndpoint = index == 0 || index == basePoints.length - 1;
    if (isEndpoint) {
      final oppositeIndex = index == 0 ? basePoints.length - 1 : 0;
      if (target.distanceSquared(basePoints[oppositeIndex]) <=
          loopThreshold * loopThreshold) {
        target = basePoints[oppositeIndex];
      }
      final endpointComputation = _computeCoreEndpointDragComputation(
        state: state,
        context: context,
        basePoints: basePoints,
        baseFixedSegments: baseFixedSegmentsResult,
        draggedIndex: index,
        target: target,
        startBinding: startBinding,
        endBinding: endBinding,
        shouldLookupBindings: shouldLookupBindings,
        allowNewBinding: allowNewBinding,
        bindingDistance: bindingDistance,
        coreEngineContext: coreEngineContext,
      );
      return endpointComputation;
    }
    updatedPoints = List<DrawPoint>.from(basePoints);
    updatedPoints[index] = target;
    activeIndex = index;
  }

  if (context.pointKind != ArrowPointKind.addable &&
      (activeIndex == 0 || activeIndex == updatedPoints.length - 1)) {
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
  if (activeIndex > 0 && activeIndex < updatedPoints.length - 1) {
    final targetPoint = updatedPoints[activeIndex];
    final prev = updatedPoints[activeIndex - 1];
    final next = updatedPoints[activeIndex + 1];
    if (targetPoint.distanceSquared(prev) <= thresholdSquared ||
        targetPoint.distanceSquared(next) <= thresholdSquared) {
      shouldDelete = true;
    }
  }

  final hasChanges =
      !pointListEquals(basePoints, updatedPoints) || nextDidInsert;
  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    didInsert: nextDidInsert,
    shouldDelete: shouldDelete,
    activeIndex: activeIndex,
    hasChanges: hasChanges,
    startBinding: startBinding,
    endBinding: endBinding,
    fixedSegments: baseFixedSegmentsResult,
    orderedElementIds: null,
  );
}

_ArrowPointComputation _computeFocusComputation({
  required DrawState state,
  required ArrowPointEditContext context,
  required List<DrawPoint> basePoints,
  required List<ElbowFixedSegment>? baseFixedSegments,
  required DrawPoint target,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowFocusEndpoint endpoint,
  required bool switchToInsideBinding,
  required core.EngineContext coreEngineContext,
}) {
  final data = context.baseElement.data as ArrowLikeData;
  if (data.arrowType == ArrowType.elbow) {
    return _noOpComputation(
      points: basePoints,
      didInsert: false,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: baseFixedSegments,
    );
  }

  final dragSourceData = data.copyWith(
    startBinding: startBinding,
    endBinding: endBinding,
  );
  final dragSourceElement = context.baseElement.copyWith(data: dragSourceData);
  final dragResult = dragArrowFocusPoint(
    element: dragSourceElement,
    data: dragSourceData,
    elementsById: state.domain.document.elementMap,
    draggedEndpoint: endpoint,
    pointer: context.toWorld(target),
    engineContext: coreEngineContext,
    switchToInsideBinding: switchToInsideBinding,
    orderedElementIds: state.domain.document.elements
        .map((element) => element.id)
        .toList(growable: false),
  );
  final nextData = dragResult.element.data;
  if (nextData is! ArrowLikeData) {
    return _noOpComputation(
      points: basePoints,
      didInsert: false,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: baseFixedSegments,
    );
  }

  final worldPoints = ArrowGeometry.resolveWorldPoints(
    rect: dragResult.element.rect,
    normalizedPoints: nextData.points,
  );
  if (worldPoints.length < 2) {
    return _noOpComputation(
      points: basePoints,
      didInsert: false,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: baseFixedSegments,
    );
  }
  final localPoints = worldToLocalPoints(context.baseElement, worldPoints);

  final nextStartBinding = nextData.startBinding;
  final nextEndBinding = nextData.endBinding;
  final nextFixedSegments = nextData.fixedSegments;
  final pointsChanged = !pointListEquals(basePoints, localPoints);
  final bindingsChanged =
      nextStartBinding != startBinding || nextEndBinding != endBinding;
  final segmentsChanged = !fixedSegmentStructureEqualsWithTolerance(
    baseFixedSegments,
    nextFixedSegments,
  );
  final activeIndex = endpoint == ArrowFocusEndpoint.start
      ? 0
      : localPoints.length - 1;

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(localPoints),
    didInsert: false,
    shouldDelete: false,
    activeIndex: activeIndex,
    hasChanges:
        dragResult.hasChanges ||
        pointsChanged ||
        bindingsChanged ||
        segmentsChanged,
    startBinding: nextStartBinding,
    endBinding: nextEndBinding,
    fixedSegments: nextFixedSegments,
    orderedElementIds: dragResult.orderedElementIds,
  );
}

_ArrowPointComputation _computeCoreEndpointDragComputation({
  required DrawState state,
  required ArrowPointEditContext context,
  required List<DrawPoint> basePoints,
  required List<ElbowFixedSegment>? baseFixedSegments,
  required int draggedIndex,
  required DrawPoint target,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required double bindingDistance,
  required core.EngineContext coreEngineContext,
}) {
  final data = context.baseElement.data as ArrowLikeData;
  final fixedSegmentsForCore = data.arrowType == ArrowType.elbow
      ? (baseFixedSegments ?? const <ElbowFixedSegment>[])
      : null;

  final arrow = toCoreArrowState(
    element: context.baseElement,
    data: data,
    localPointsOverride: basePoints,
    fixedSegmentsOverride: fixedSegmentsForCore,
    startBindingOverride: startBinding,
    endBindingOverride: endBinding,
  );
  final worldTarget = context.toWorld(target);
  final activeBinding = draggedIndex == 0 ? startBinding : endBinding;
  final oppositeBinding = draggedIndex == 0 ? endBinding : startBinding;
  final bindables = _resolveCoreEndpointBindables(
    state: state,
    worldTarget: worldTarget,
    excludedElementId: context.elementId,
    shouldLookupBindings: shouldLookupBindings,
    allowNewBinding: allowNewBinding,
    bindingDistance: bindingDistance,
    activeBinding: activeBinding,
    oppositeBinding: oppositeBinding,
  );
  final dragContext = shouldLookupBindings
      ? coreEngineContext
      : _coreContextWithBindingDisabled(coreEngineContext);

  final dragPoint = <double>[worldTarget.x - arrow.x, worldTarget.y - arrow.y];
  final dragResult = computeCoreEndpointDrag(
    arrow: arrow,
    draggedPoints: <int, core.Point>{draggedIndex: dragPoint},
    pointer: toCorePoint(worldTarget),
    bindables: bindables,
    context: dragContext,
    options: const <String, dynamic>{'complexBindings': true},
  );
  final applied = applyCoreEngineResult(
    arrow: arrow,
    bindables: collectCoreBindableRelations(
      state.domain.document.elementMap.values,
    ),
    result: dragResult,
    orderedElementIds: state.domain.document.elements
        .map((element) => element.id)
        .toList(growable: false),
  );
  final draggedArrow = applied.arrow;
  final worldPoints = coreArrowWorldPoints(draggedArrow);
  if (worldPoints.length < 2) {
    return _noOpComputation(
      points: basePoints,
      didInsert: false,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: baseFixedSegments,
    );
  }

  final localPoints = worldToLocalPoints(context.baseElement, worldPoints);
  final nextFixedSegments = data.arrowType == ArrowType.elbow
      ? toLocalFixedSegmentsFromCoreArrow(draggedArrow, context.baseElement)
      : baseFixedSegments;
  final nextStartBinding = fromCoreBinding(draggedArrow.startBinding);
  final nextEndBinding = fromCoreBinding(draggedArrow.endBinding);

  final pointsChanged = !pointListEquals(basePoints, localPoints);
  final bindingsChanged =
      nextStartBinding != startBinding || nextEndBinding != endBinding;
  final segmentsChanged =
      data.arrowType == ArrowType.elbow &&
      !fixedSegmentStructureEqualsWithTolerance(
        baseFixedSegments,
        nextFixedSegments,
      );
  final activeIndex = draggedIndex < 0
      ? 0
      : draggedIndex >= localPoints.length
      ? localPoints.length - 1
      : draggedIndex;
  final orderedElementIds = reorderedElementIdsFromCoreResult(applied);
  final orderChanged = didCoreEngineResultReorder(applied);

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(localPoints),
    didInsert: false,
    shouldDelete: false,
    activeIndex: activeIndex,
    hasChanges:
        pointsChanged || bindingsChanged || segmentsChanged || orderChanged,
    startBinding: nextStartBinding,
    endBinding: nextEndBinding,
    fixedSegments: nextFixedSegments,
    orderedElementIds: orderedElementIds,
  );
}

List<core.BindableState> _resolveCoreEndpointBindables({
  required DrawState state,
  required DrawPoint worldTarget,
  required String excludedElementId,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required double bindingDistance,
  required ArrowBinding? activeBinding,
  required ArrowBinding? oppositeBinding,
}) {
  if (!shouldLookupBindings) {
    return const <core.BindableState>[];
  }

  final document = state.domain.document;
  final bindableIds = <String>{};
  if (activeBinding != null) {
    bindableIds.add(activeBinding.elementId);
  }
  if (oppositeBinding != null) {
    bindableIds.add(oppositeBinding.elementId);
  }
  if (allowNewBinding && bindingDistance > 0) {
    document.visitArrowBindableElementsAtPoint(worldTarget, bindingDistance, (
      element,
    ) {
      bindableIds.add(element.id);
      return true;
    }, excludedElementId: excludedElementId);
  }
  if (bindableIds.isEmpty) {
    return const <core.BindableState>[];
  }

  final bindables = <core.BindableState>[];
  for (final id in bindableIds) {
    final element = document.elementMap[id];
    if (element == null ||
        element.opacity <= 0 ||
        !isArrowBindableElement(element)) {
      continue;
    }
    final bindable = toCoreBindableState(element);
    if (bindable != null) {
      bindables.add(bindable);
    }
  }
  return bindables;
}

core.EngineContext _coreContextWithBindingDisabled(
  core.EngineContext context,
) => buildCoreEngineContext(
  zoom: context.zoom,
  isBindingEnabled: false,
  bindMode: context.bindMode,
  maxCoordinate: context.maxCoordinate,
);

_ArrowPointComputation _computeElbowAddableComputation({
  required DrawState state,
  required ArrowPointEditContext context,
  required DrawPoint target,
  required List<DrawPoint> basePoints,
  required List<ElbowFixedSegment> baseFixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required core.EngineContext coreEngineContext,
}) {
  final data = context.baseElement.data;
  if (data is! ArrowData) {
    return _noOpComputation(
      points: basePoints,
      didInsert: false,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: baseFixedSegments,
    );
  }

  final segmentIndex = context.pointIndex + 1;
  final worldTarget = context.toWorld(target);
  final arrowState = toCoreArrowState(
    element: context.baseElement,
    data: data,
    localPointsOverride: basePoints,
    fixedSegmentsOverride: baseFixedSegments,
    startBindingOverride: startBinding,
    endBindingOverride: endBinding,
  );
  final dragResult = moveCoreFixedSegmentToPoint(
    arrow: arrowState,
    segmentIndex: segmentIndex,
    pointer: toCorePoint(worldTarget),
  );
  final movedArrow = core.applyArrowPatch(arrowState, dragResult.patch);
  final movedFixedSegments = toLocalFixedSegmentsFromCoreArrow(
    movedArrow,
    context.baseElement,
  );
  final updated = computeElbowEdit(
    element: context.baseElement,
    data: data,
    lookup: CombinedElementLookup(base: state.domain.document.elementMap),
    localPointsOverride: basePoints,
    fixedSegmentsOverride: movedFixedSegments,
    startBindingOverride: startBinding,
    endBindingOverride: endBinding,
    engineContext: coreEngineContext,
  );

  final pointsChanged = !pointListEquals(basePoints, updated.localPoints);
  final segmentsChanged = !fixedSegmentStructureEqualsWithTolerance(
    baseFixedSegments,
    updated.fixedSegments,
  );

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(updated.localPoints),
    didInsert: false,
    shouldDelete: false,
    activeIndex: _resolveElbowAddableActiveIndex(
      context: context,
      segmentIndex: dragResult.activeSegmentIndex ?? segmentIndex,
      pointCount: updated.localPoints.length,
    ),
    hasChanges: pointsChanged || segmentsChanged,
    startBinding: startBinding,
    endBinding: endBinding,
    fixedSegments: updated.fixedSegments,
    orderedElementIds: null,
  );
}

_ArrowPointComputation _noOpComputation({
  required List<DrawPoint> points,
  required bool didInsert,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required List<ElbowFixedSegment>? fixedSegments,
}) => _ArrowPointComputation(
  points: points,
  didInsert: didInsert,
  shouldDelete: false,
  activeIndex: null,
  hasChanges: false,
  startBinding: startBinding,
  endBinding: endBinding,
  fixedSegments: fixedSegments,
  orderedElementIds: null,
);

int? _resolveDraggedPointIndex({
  required ArrowPointKind pointKind,
  required int pointIndex,
  required int pointCount,
}) {
  final resolvedIndex = switch (pointKind) {
    ArrowPointKind.loopStart => 0,
    ArrowPointKind.loopEnd => pointCount - 1,
    ArrowPointKind.focusStart => 0,
    ArrowPointKind.focusEnd => pointCount - 1,
    _ => pointIndex,
  };
  if (resolvedIndex < 0 || resolvedIndex >= pointCount) {
    return null;
  }
  return resolvedIndex;
}

bool _isValidAddablePointIndex({required int index, required int pointCount}) =>
    index >= 0 && index < pointCount - 1;

bool _requiresBindingLookup(ArrowPointEditContext context) =>
    switch (context.pointKind) {
      ArrowPointKind.loopStart => true,
      ArrowPointKind.loopEnd => true,
      ArrowPointKind.focusStart => false,
      ArrowPointKind.focusEnd => false,
      ArrowPointKind.turning =>
        context.pointIndex == 0 ||
            context.pointIndex == context.initialPoints.length - 1,
      ArrowPointKind.addable => false,
    };

DrawPoint _resolvePointPosition({
  required DrawState state,
  required ElementState element,
  required ArrowLikeData data,
  required List<DrawPoint> points,
  required ArrowPointKind kind,
  required int index,
  required ArrowType arrowType,
}) {
  if (kind == ArrowPointKind.addable) {
    if (!_isValidAddablePointIndex(index: index, pointCount: points.length)) {
      return points.first;
    }

    // For curved arrows with 3+ points, calculate point on the actual curve
    if (arrowType == ArrowType.curved && points.length >= 3) {
      final curvePoint = ArrowGeometry.calculateCurveDrawPoint(
        points: points,
        segmentIndex: index,
        t: 0.5,
      );
      if (curvePoint != null) {
        return curvePoint;
      }
    }

    // For straight arrows, use linear midpoint
    final start = points[index];
    final end = points[index + 1];
    return DrawPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2);
  }
  final focusEndpoint = _resolveFocusEndpoint(kind);
  if (focusEndpoint != null) {
    return _resolveFocusPointPosition(
      state: state,
      element: element,
      data: data,
      fallbackPoints: points,
      endpoint: focusEndpoint,
    );
  }
  final resolvedIndex = switch (kind) {
    ArrowPointKind.loopStart => 0,
    ArrowPointKind.loopEnd => points.length - 1,
    _ => index,
  };
  return points[resolvedIndex.clamp(0, points.length - 1)];
}

ArrowFocusEndpoint? _resolveFocusEndpoint(ArrowPointKind kind) =>
    switch (kind) {
      ArrowPointKind.focusStart => ArrowFocusEndpoint.start,
      ArrowPointKind.focusEnd => ArrowFocusEndpoint.end,
      _ => null,
    };

DrawPoint _resolveFocusPointPosition({
  required DrawState state,
  required ElementState element,
  required ArrowLikeData data,
  required List<DrawPoint> fallbackPoints,
  required ArrowFocusEndpoint endpoint,
}) {
  final focusPoints = listVisibleArrowFocusPoints(
    element: element,
    data: data,
    elements: state.domain.document.elements,
    engineContext: buildCoreEngineContext(
      zoom: state.application.view.camera.zoom,
    ),
  );
  for (final focusPoint in focusPoints) {
    if (focusPoint.endpoint != endpoint) {
      continue;
    }
    return element.rotation == 0
        ? focusPoint.position
        : ElementSpace(
            rotation: element.rotation,
            origin: element.rect.center,
          ).fromWorld(focusPoint.position);
  }

  final fallbackIndex = endpoint == ArrowFocusEndpoint.start
      ? 0
      : fallbackPoints.length - 1;
  return fallbackPoints[fallbackIndex.clamp(0, fallbackPoints.length - 1)];
}

DrawPoint _snapTargetToGrid({
  required DrawPoint target,
  required ArrowPointEditContext context,
  required double gridSize,
}) {
  if (gridSize <= 0) {
    return target;
  }
  final worldTarget = context.toWorld(target);
  final snappedWorld = gridSnapService.snapPoint(
    point: worldTarget,
    gridSize: gridSize,
  );
  return context.toLocal(snappedWorld);
}

int _resolveElbowAddableActiveIndex({
  required ArrowPointEditContext context,
  required int segmentIndex,
  required int pointCount,
}) {
  final active = segmentIndex == 1
      ? context.pointIndex + 1
      : context.pointIndex;
  if (pointCount <= 0) {
    return 0;
  }
  if (active < 0) {
    return 0;
  }
  if (active >= pointCount) {
    return pointCount - 1;
  }
  return active;
}

core.EngineContext _coreContextForState({
  required DrawState state,
  required bool isBindingEnabled,
}) => buildCoreEngineContext(
  zoom: state.application.view.camera.zoom,
  isBindingEnabled: isBindingEnabled,
);
