import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_binding_snapper.dart';
import '../../elements/types/arrow/arrow_binding_target_cache.dart';
import '../../elements/types/arrow/arrow_data.dart';
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

const _defaultBindingCandidateCacheThresholdFactor = 0.35;
const _defaultBindingCandidateReferenceCacheThresholdFactor = 0.35;
const _linePointBindingCandidateCacheThresholdFactor = 0.45;
const _linePointBindingCandidateReferenceCacheThresholdFactor = 0.45;

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
      bindingTargetCache: ArrowBindingTargetCache(),
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
      final updatedFixed = (data.fixedSegments ?? const [])
          .where((segment) => segment.index != segmentIndex)
          .toList(growable: false);
      final updated = computeElbowEdit(
        element: baseElement,
        data: arrowData,
        lookup: CombinedElementLookup(base: state.domain.document.elementMap),
        localPointsOverride: points,
        fixedSegmentsOverride: updatedFixed,
        startBindingOverride: data.startBinding,
        endBindingOverride: data.endBinding,
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
        ? ArrowBindingSnapper.resolveBindingDistance(
            state: state,
            snapConfig: snapConfig,
          )
        : 0.0;

    final result = _compute(
      state: state,
      context: typedContext,
      currentPosition: localPosition,
      didInsert: typedTransform.didInsert,
      config: config,
      startBinding: startBinding,
      endBinding: endBinding,
      startArrowhead: typedContext.startArrowhead,
      endArrowhead: typedContext.endArrowhead,
      shouldLookupBindings: shouldLookupBindings,
      bindingDistance: bindingDistance,
      allowNewBinding: allowNewBinding,
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
      finalize: applyDeletion,
    );

    return EditComputedResult(
      updatedElements: {updatedElement.id: updatedElement},
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
      startBindingOverride: transform.startBinding,
      endBindingOverride: transform.endBinding,
      startBindingOverrideIsSet: true,
      endBindingOverrideIsSet: true,
      finalize: finalize,
    );
    final rectAndPoints = computeArrowRectAndPoints(
      localPoints: updated.localPoints,
      oldRect: context.elementRect,
      rotation: context.rotation,
      arrowType: data.arrowType,
    );
    final transformedFixedSegments = transformFixedSegments(
      segments: updated.fixedSegments,
      oldRect: context.elementRect,
      newRect: rectAndPoints.rect,
      rotation: context.rotation,
    );
    final normalized = ArrowGeometry.normalizePoints(
      worldPoints: rectAndPoints.localPoints,
      rect: rectAndPoints.rect,
    );
    final updatedData = dataWithBindings.copyWith(
      points: normalized,
      fixedSegments: transformedFixedSegments,
      startIsSpecial: updated.startIsSpecial,
      endIsSpecial: updated.endIsSpecial,
    );
    return element.copyWith(rect: rectAndPoints.rect, data: updatedData);
  }

  final rectAndPoints = computeArrowRectAndPoints(
    localPoints: localPoints,
    oldRect: context.elementRect,
    rotation: context.rotation,
    arrowType: data.arrowType,
  );
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: rectAndPoints.localPoints,
    rect: rectAndPoints.rect,
  );
  final updatedData = dataWithBindings.copyWith(points: normalized);
  return element.copyWith(rect: rectAndPoints.rect, data: updatedData);
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
    required ArrowBindingTargetCache bindingTargetCache,
    required this.startArrowhead,
    required this.endArrowhead,
    required this.initialStartBinding,
    required this.initialEndBinding,
    required this.hasBindableTargets,
    this.isLineElement = false,
  }) : _bindingTargetCache = bindingTargetCache,
       _elementSpace = elementSpace;

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
  final ArrowBindingTargetCache _bindingTargetCache;
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
  });

  final List<DrawPoint> points;
  final bool didInsert;
  final bool shouldDelete;
  final int? activeIndex;
  final bool hasChanges;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final List<ElbowFixedSegment>? fixedSegments;
}

@immutable
final class _BoundarySegmentDragResult {
  const _BoundarySegmentDragResult({
    required this.points,
    required this.fixedSegments,
  });

  final List<DrawPoint> points;
  final List<ElbowFixedSegment> fixedSegments;
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
    pointListEquals(previous.points, next.points) &&
    fixedSegmentStructureEquals(previous.fixedSegments, next.fixedSegments);

_ArrowPointComputation _compute({
  required DrawState state,
  required ArrowPointEditContext context,
  required DrawPoint currentPosition,
  required bool didInsert,
  required DrawConfig config,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  required bool shouldLookupBindings,
  required double bindingDistance,
  required bool allowNewBinding,
}) {
  final basePoints = context.initialPoints;
  final baseFixedSegments = context.initialFixedSegments;
  final handleTolerance = resolveZoomAdjustedDistance(
    distance: config.selection.interaction.handleTolerance,
    zoom: state.application.view.camera.zoom,
  );
  final addThreshold = handleTolerance;
  final deleteThreshold = handleTolerance;
  final loopThreshold = handleTolerance * 1.5;
  final baseFixedSegmentsResult = baseFixedSegments.isEmpty
      ? null
      : baseFixedSegments;

  var target = currentPosition.translate(context.dragOffset);
  var updatedPoints = basePoints;
  var nextDidInsert = didInsert;
  var nextStartBinding = startBinding;
  var nextEndBinding = endBinding;
  late final int activeIndex;

  if (context.pointKind == ArrowPointKind.addable) {
    final hasValidPointIndex = _isValidAddablePointIndex(
      index: context.pointIndex,
      pointCount: basePoints.length,
    );
    if (!hasValidPointIndex) {
      return _noOpComputation(
        points: basePoints,
        didInsert: false,
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
        fixedSegments: baseFixedSegmentsResult,
      );
    }
    if (context.arrowType == ArrowType.elbow) {
      return _computeElbowAddableComputation(
        context: context,
        target: target,
        basePoints: basePoints,
        baseFixedSegments: baseFixedSegments,
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
      );
    }
    if (!nextDidInsert) {
      final distanceSq = currentPosition.distanceSquared(context.startPosition);
      if (distanceSq >= addThreshold * addThreshold) {
        nextDidInsert = true;
      } else {
        return _noOpComputation(
          points: basePoints,
          didInsert: false,
          startBinding: nextStartBinding,
          endBinding: nextEndBinding,
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
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
        fixedSegments: baseFixedSegmentsResult,
      );
    }
    final isEndpoint = index == 0 || index == basePoints.length - 1;
    if (isEndpoint) {
      final existingBinding = index == 0 ? nextStartBinding : nextEndBinding;
      final referencePoint = basePoints.length > 1
          ? context.toWorld(basePoints[index == 0 ? 1 : basePoints.length - 2])
          : null;
      final worldTarget = context.toWorld(target);
      final hasArrowhead = index == 0
          ? startArrowhead != ArrowheadStyle.none
          : endArrowhead != ArrowheadStyle.none;
      final candidate = _resolveEndpointBindingCandidate(
        state: state,
        context: context,
        worldTarget: worldTarget,
        existingBinding: existingBinding,
        hasArrowhead: hasArrowhead,
        shouldLookupBindings: shouldLookupBindings,
        snapDistance: bindingDistance,
        allowNewBinding: allowNewBinding,
        referencePoint: referencePoint,
      );
      if (candidate != null) {
        target = context.toLocal(candidate.snapPoint);
        if (index == 0) {
          nextStartBinding = candidate.binding;
        } else {
          nextEndBinding = candidate.binding;
        }
      } else if (index == 0) {
        nextStartBinding = null;
      } else {
        nextEndBinding = null;
      }
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
    if (targetPoint.distanceSquared(prev) <=
            deleteThreshold * deleteThreshold ||
        targetPoint.distanceSquared(next) <=
            deleteThreshold * deleteThreshold) {
      shouldDelete = true;
    }
  }

  final hasChanges =
      !pointListEquals(basePoints, updatedPoints) || nextDidInsert;
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
    fixedSegments: baseFixedSegmentsResult,
  );
}

_ArrowPointComputation _computeElbowAddableComputation({
  required ArrowPointEditContext context,
  required DrawPoint target,
  required List<DrawPoint> basePoints,
  required List<ElbowFixedSegment> baseFixedSegments,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
}) {
  final segmentIndex = context.pointIndex + 1;
  final start = basePoints[segmentIndex - 1];
  final end = basePoints[segmentIndex];
  final dx = (start.x - end.x).abs();
  final dy = (start.y - end.y).abs();
  final isHorizontal = dy <= dx;

  final isBoundarySegment =
      segmentIndex == 1 || segmentIndex == basePoints.length - 1;
  if (isBoundarySegment) {
    final boundary = _applyBoundarySegmentDrag(
      basePoints: basePoints,
      baseFixedSegments: baseFixedSegments,
      segmentIndex: segmentIndex,
      target: target,
      isHorizontal: isHorizontal,
    );
    final fixedSegmentsResult = boundary.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(boundary.fixedSegments);
    final pointsChanged = !pointListEquals(basePoints, boundary.points);
    final segmentsChanged = !fixedSegmentStructureEqualsWithTolerance(
      baseFixedSegments,
      fixedSegmentsResult,
    );

    return _ArrowPointComputation(
      points: List<DrawPoint>.unmodifiable(boundary.points),
      didInsert: false,
      shouldDelete: false,
      activeIndex: segmentIndex == 1
          ? context.pointIndex + 1
          : context.pointIndex,
      hasChanges: pointsChanged || segmentsChanged,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: fixedSegmentsResult,
    );
  }

  final updatedPoints = List<DrawPoint>.from(basePoints);
  final nextStart = isHorizontal
      ? DrawPoint(x: start.x, y: target.y)
      : DrawPoint(x: target.x, y: start.y);
  final nextEnd = isHorizontal
      ? DrawPoint(x: end.x, y: target.y)
      : DrawPoint(x: target.x, y: end.y);
  updatedPoints[segmentIndex - 1] = nextStart;
  updatedPoints[segmentIndex] = nextEnd;

  final nextFixedSegments = List<ElbowFixedSegment>.from(baseFixedSegments);
  final existingIndex = nextFixedSegments.indexWhere(
    (segment) => segment.index == segmentIndex,
  );
  if (existingIndex >= 0) {
    final updatedSegment = nextFixedSegments[existingIndex].copyWith(
      start: nextStart,
      end: nextEnd,
    );
    nextFixedSegments[existingIndex] = updatedSegment;
  } else {
    nextFixedSegments.add(
      ElbowFixedSegment(index: segmentIndex, start: nextStart, end: nextEnd),
    );
  }
  final previousIndex = nextFixedSegments.indexWhere(
    (segment) => segment.index == segmentIndex - 1,
  );
  if (previousIndex >= 0) {
    final previous = nextFixedSegments[previousIndex];
    nextFixedSegments[previousIndex] = previous.copyWith(end: nextStart);
  }
  final nextIndex = nextFixedSegments.indexWhere(
    (segment) => segment.index == segmentIndex + 1,
  );
  if (nextIndex >= 0) {
    final next = nextFixedSegments[nextIndex];
    nextFixedSegments[nextIndex] = next.copyWith(start: nextEnd);
  }

  final fixedSegmentsResult = nextFixedSegments.isEmpty
      ? null
      : List<ElbowFixedSegment>.unmodifiable(nextFixedSegments);
  final pointsChanged = !pointListEquals(basePoints, updatedPoints);
  final segmentsChanged = !fixedSegmentStructureEqualsWithTolerance(
    baseFixedSegments,
    fixedSegmentsResult,
  );

  return _ArrowPointComputation(
    points: List<DrawPoint>.unmodifiable(updatedPoints),
    didInsert: false,
    shouldDelete: false,
    activeIndex: context.pointIndex,
    hasChanges: pointsChanged || segmentsChanged,
    startBinding: startBinding,
    endBinding: endBinding,
    fixedSegments: fixedSegmentsResult,
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
);

int? _resolveDraggedPointIndex({
  required ArrowPointKind pointKind,
  required int pointIndex,
  required int pointCount,
}) {
  final resolvedIndex = switch (pointKind) {
    ArrowPointKind.loopStart => 0,
    ArrowPointKind.loopEnd => pointCount - 1,
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
      ArrowPointKind.turning =>
        context.pointIndex == 0 ||
            context.pointIndex == context.initialPoints.length - 1,
      ArrowPointKind.addable => false,
    };

ArrowBindingResult? _resolveEndpointBindingCandidate({
  required DrawState state,
  required ArrowPointEditContext context,
  required DrawPoint worldTarget,
  required ArrowBinding? existingBinding,
  required bool hasArrowhead,
  required bool shouldLookupBindings,
  required double snapDistance,
  required bool allowNewBinding,
  DrawPoint? referencePoint,
}) {
  final preferredArrowheadStyle = hasArrowhead
      ? ArrowheadStyle.standard
      : ArrowheadStyle.none;
  final candidateCacheThresholdFactor = context.isLineElement
      ? _linePointBindingCandidateCacheThresholdFactor
      : _defaultBindingCandidateCacheThresholdFactor;
  final candidateReferenceThresholdFactor = context.isLineElement
      ? _linePointBindingCandidateReferenceCacheThresholdFactor
      : _defaultBindingCandidateReferenceCacheThresholdFactor;
  return ArrowBindingSnapper.resolveEndpointBindingCandidate(
    state: state,
    worldPoint: worldTarget,
    arrowType: context.arrowType,
    arrowheadStyle: preferredArrowheadStyle,
    shouldLookupBindings: shouldLookupBindings,
    snapDistance: snapDistance,
    allowNewBinding: allowNewBinding,
    hasBindableTargets: context.hasBindableTargets,
    preferredBinding: existingBinding,
    referencePoint: referencePoint,
    cache: context._bindingTargetCache,
    candidateCacheThresholdFactor: candidateCacheThresholdFactor,
    candidateCacheReferenceThresholdFactor: candidateReferenceThresholdFactor,
    excludedElementId: context.elementId,
  );
}

DrawPoint _resolvePointPosition({
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
  final resolvedIndex = switch (kind) {
    ArrowPointKind.loopStart => 0,
    ArrowPointKind.loopEnd => points.length - 1,
    _ => index,
  };
  return points[resolvedIndex.clamp(0, points.length - 1)];
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

_BoundarySegmentDragResult _applyBoundarySegmentDrag({
  required List<DrawPoint> basePoints,
  required List<ElbowFixedSegment> baseFixedSegments,
  required int segmentIndex,
  required DrawPoint target,
  required bool isHorizontal,
}) {
  final isStart = segmentIndex == 1;
  final isEnd = segmentIndex == basePoints.length - 1;
  final axis = isHorizontal ? target.y : target.x;

  late final List<DrawPoint> updatedPoints;
  late final int movedSegmentIndex;
  var insertedAtStart = false;
  var insertedAtEnd = false;

  if (isStart && isEnd) {
    insertedAtStart = true;
    insertedAtEnd = true;
    final startPoint = basePoints.first;
    final endPoint = basePoints.last;
    final startStub = isHorizontal
        ? DrawPoint(x: startPoint.x, y: axis)
        : DrawPoint(x: axis, y: startPoint.y);
    final endStub = isHorizontal
        ? DrawPoint(x: endPoint.x, y: axis)
        : DrawPoint(x: axis, y: endPoint.y);
    updatedPoints = <DrawPoint>[startPoint, startStub, endStub, endPoint];
    movedSegmentIndex = 2;
  } else if (isStart) {
    insertedAtStart = true;
    final startPoint = basePoints.first;
    final nextPoint = basePoints[1];
    final stub = isHorizontal
        ? DrawPoint(x: startPoint.x, y: axis)
        : DrawPoint(x: axis, y: startPoint.y);
    final moved = isHorizontal
        ? DrawPoint(x: nextPoint.x, y: axis)
        : DrawPoint(x: axis, y: nextPoint.y);
    updatedPoints = <DrawPoint>[
      startPoint,
      stub,
      moved,
      ...basePoints.sublist(2),
    ];
    movedSegmentIndex = 2;
  } else {
    insertedAtEnd = true;
    final endPoint = basePoints.last;
    final prevPoint = basePoints[basePoints.length - 2];
    final moved = isHorizontal
        ? DrawPoint(x: prevPoint.x, y: axis)
        : DrawPoint(x: axis, y: prevPoint.y);
    final stub = isHorizontal
        ? DrawPoint(x: endPoint.x, y: axis)
        : DrawPoint(x: axis, y: endPoint.y);
    updatedPoints = <DrawPoint>[
      ...basePoints.sublist(0, basePoints.length - 2),
      moved,
      stub,
      endPoint,
    ];
    movedSegmentIndex = segmentIndex;
  }

  final updatedFixedSegments = _buildBoundaryFixedSegments(
    baseFixedSegments: baseFixedSegments,
    updatedPoints: updatedPoints,
    originalPointCount: basePoints.length,
    movedSegmentIndex: movedSegmentIndex,
    insertedAtStart: insertedAtStart,
    insertedAtEnd: insertedAtEnd,
  );

  return _BoundarySegmentDragResult(
    points: updatedPoints,
    fixedSegments: updatedFixedSegments,
  );
}

List<ElbowFixedSegment> _buildBoundaryFixedSegments({
  required List<ElbowFixedSegment> baseFixedSegments,
  required List<DrawPoint> updatedPoints,
  required int originalPointCount,
  required int movedSegmentIndex,
  required bool insertedAtStart,
  required bool insertedAtEnd,
}) {
  final updated = <ElbowFixedSegment>[];
  if (!(insertedAtStart && insertedAtEnd)) {
    for (final segment in baseFixedSegments) {
      final mappedIndex = _mapBoundaryFixedIndex(
        originalIndex: segment.index,
        originalPointCount: originalPointCount,
        insertedAtStart: insertedAtStart,
        insertedAtEnd: insertedAtEnd,
      );
      if (mappedIndex == null) {
        continue;
      }
      final rebuilt = _fixedSegmentForIndex(updatedPoints, mappedIndex);
      if (rebuilt != null) {
        updated.add(rebuilt);
      }
    }
  }

  final moved = _fixedSegmentForIndex(updatedPoints, movedSegmentIndex);
  if (moved != null) {
    updated
      ..removeWhere((segment) => segment.index == moved.index)
      ..add(moved);
  }

  updated.sort((a, b) => a.index.compareTo(b.index));
  return updated;
}

int? _mapBoundaryFixedIndex({
  required int originalIndex,
  required int originalPointCount,
  required bool insertedAtStart,
  required bool insertedAtEnd,
}) {
  if (insertedAtStart && insertedAtEnd) {
    return null;
  }
  if (insertedAtStart) {
    if (originalIndex <= 1) {
      return null;
    }
    return originalIndex + 1;
  }
  if (insertedAtEnd) {
    final boundaryIndex = originalPointCount - 1;
    if (originalIndex == boundaryIndex) {
      return null;
    }
    return originalIndex;
  }
  return originalIndex;
}

ElbowFixedSegment? _fixedSegmentForIndex(List<DrawPoint> points, int index) {
  if (index <= 1 || index >= points.length - 1) {
    return null;
  }
  final start = points[index - 1];
  final end = points[index];
  final length = (start.x - end.x).abs() + (start.y - end.y).abs();
  if (length <= 1) {
    return null;
  }
  return ElbowFixedSegment(index: index, start: start, end: end);
}
