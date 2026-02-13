import 'dart:ui';

import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/arrow/elbow/elbow_editing.dart';
import '../../elements/types/arrow/elbow/elbow_fixed_segment.dart';
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
    final points = resolved
        .map((point) => DrawPoint(x: point.dx, y: point.dy))
        .toList(growable: false);
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
      initialFixedSegments: List<ElbowFixedSegment>.unmodifiable(fixedSegments),
      arrowType: data.arrowType,
      pointKind: typedParams.pointKind,
      pointIndex: typedParams.pointIndex,
      dragOffset: dragOffset,
      releaseFixedSegment: shouldReleaseSegment,
      deletePointOnStart: shouldDeletePoint,
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
    final elementData = element?.data;
    if (element == null || elementData is! ArrowLikeData) {
      return ArrowPointTransform(
        currentPosition: startPosition,
        points: typedContext.initialPoints,
      );
    }
    final data = elementData;
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
        element: element,
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
    if (typedContext.releaseFixedSegment) {
      return EditUpdateResult<EditTransform>(transform: typedTransform);
    }
    if (typedContext.deletePointOnStart) {
      return EditUpdateResult<EditTransform>(transform: typedTransform);
    }

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
    final data = element?.data is ArrowLikeData
        ? element!.data as ArrowLikeData
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
    final bindingTargets = element == null || bindingDistance <= 0
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
      startArrowhead: data?.startArrowhead ?? ArrowheadStyle.none,
      endArrowhead: data?.endArrowhead ?? ArrowheadStyle.none,
      bindingTargets: bindingTargets,
      bindingDistance: bindingDistance,
      allowNewBinding: allowNewBinding,
    );

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

    final element = state.domain.document.getElementById(
      typedContext.elementId,
    );
    if (element == null || element.data is! ArrowLikeData) {
      return null;
    }

    final updatedElement = _buildUpdatedElement(
      element: element,
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

  // Transform local-space points to world space, then back to local space
  // with the new rect center. This preserves world-space positions while
  // keeping the same rotation angle.
  final result = data.arrowType == ArrowType.elbow && arrowData != null
      ? () {
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
            strokeWidth: data.strokeWidth,
          );
          final transformedFixedSegments = transformFixedSegments(
            segments: updated.fixedSegments,
            oldRect: context.elementRect,
            newRect: rectAndPoints.rect,
            rotation: context.rotation,
          );
          return (rectAndPoints, transformedFixedSegments, updated);
        }()
      : (
          computeArrowRectAndPoints(
            localPoints: localPoints,
            oldRect: context.elementRect,
            rotation: context.rotation,
            arrowType: data.arrowType,
            strokeWidth: data.strokeWidth,
          ),
          null,
          null,
        );

  final rectAndPoints = result.$1;
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: rectAndPoints.localPoints,
    rect: rectAndPoints.rect,
  );

  final updatedData =
      data.arrowType == ArrowType.elbow &&
          arrowData != null &&
          result.$3 != null
      ? dataWithBindings.copyWith(
          points: normalized,
          fixedSegments: result.$2,
          startIsSpecial: result.$3!.startIsSpecial,
          endIsSpecial: result.$3!.endIsSpecial,
        )
      : dataWithBindings.copyWith(points: normalized);

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
    required this.releaseFixedSegment,
    required this.deletePointOnStart,
    required BindingTargetCache bindingTargetCache,
  }) : _bindingTargetCache = bindingTargetCache;

  final String elementId;
  final DrawRect elementRect;
  final double rotation;
  final List<DrawPoint> initialPoints;
  final List<ElbowFixedSegment> initialFixedSegments;
  final ArrowType arrowType;
  final ArrowPointKind pointKind;
  final int pointIndex;
  final DrawPoint dragOffset;
  final bool releaseFixedSegment;
  final bool deletePointOnStart;
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

_ArrowPointComputation _compute({
  required ArrowPointEditContext context,
  required DrawPoint currentPosition,
  required bool didInsert,
  required DrawConfig config,
  required double zoom,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required ArrowheadStyle startArrowhead,
  required ArrowheadStyle endArrowhead,
  required List<ElementState> bindingTargets,
  required double bindingDistance,
  required bool allowNewBinding,
}) {
  final basePoints = List<DrawPoint>.from(context.initialPoints);
  final baseFixedSegments = context.initialFixedSegments;
  final effectiveZoom = zoom == 0 ? 1.0 : zoom;
  final handleTolerance =
      config.selection.interaction.handleTolerance / effectiveZoom;
  final addThreshold = handleTolerance;
  final deleteThreshold = handleTolerance;
  final loopThreshold = handleTolerance * 1.5;

  var target = currentPosition.translate(context.dragOffset);
  var updatedPoints = basePoints;
  var nextDidInsert = didInsert;
  var nextStartBinding = startBinding;
  var nextEndBinding = endBinding;
  int? activeIndex;

  if (context.pointKind == ArrowPointKind.addable) {
    if (context.arrowType == ArrowType.elbow) {
      if (context.pointIndex < 0 ||
          context.pointIndex >= basePoints.length - 1) {
        return _ArrowPointComputation(
          points: basePoints,
          didInsert: false,
          shouldDelete: false,
          activeIndex: null,
          hasChanges: false,
          startBinding: nextStartBinding,
          endBinding: nextEndBinding,
          fixedSegments: baseFixedSegments.isEmpty ? null : baseFixedSegments,
        );
      }
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
          startBinding: nextStartBinding,
          endBinding: nextEndBinding,
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
          ElbowFixedSegment(
            index: segmentIndex,
            start: nextStart,
            end: nextEnd,
          ),
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
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
        fixedSegments: fixedSegmentsResult,
      );
    }

    if (context.pointIndex < 0 || context.pointIndex >= basePoints.length - 1) {
      return _ArrowPointComputation(
        points: basePoints,
        didInsert: false,
        shouldDelete: false,
        activeIndex: null,
        hasChanges: false,
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
        fixedSegments: baseFixedSegments.isEmpty ? null : baseFixedSegments,
      );
    }
    if (!nextDidInsert) {
      final distanceSq = currentPosition.distanceSquared(context.startPosition);
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
          fixedSegments: baseFixedSegments.isEmpty ? null : baseFixedSegments,
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
        startBinding: nextStartBinding,
        endBinding: nextEndBinding,
        fixedSegments: baseFixedSegments.isEmpty ? null : baseFixedSegments,
      );
    }
    final isEndpoint = index == 0 || index == basePoints.length - 1;
    if (isEndpoint) {
      final existingBinding = index == 0 ? nextStartBinding : nextEndBinding;
      final referencePoint = basePoints.length > 1
          ? _toWorldPosition(
              context.elementRect,
              context.rotation,
              basePoints[index == 0 ? 1 : basePoints.length - 2],
            )
          : null;
      final worldTarget = _toWorldPosition(
        context.elementRect,
        context.rotation,
        target,
      );
      final hasArrowhead = index == 0
          ? startArrowhead != ArrowheadStyle.none
          : endArrowhead != ArrowheadStyle.none;
      final candidate = context.arrowType == ArrowType.elbow
          ? ArrowBindingUtils.resolveElbowBindingCandidate(
              worldPoint: worldTarget,
              targets: bindingTargets,
              snapDistance: bindingDistance,
              preferredBinding: existingBinding,
              allowNewBinding: allowNewBinding,
              hasArrowhead: hasArrowhead,
            )
          : ArrowBindingUtils.resolveBindingCandidate(
              worldPoint: worldTarget,
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
    updatedPoints = List<DrawPoint>.from(basePoints);
    updatedPoints[index] = target;
    activeIndex = index;
  }

  final resolvedActiveIndex = activeIndex;
  if (context.pointKind != ArrowPointKind.addable &&
      (resolvedActiveIndex == 0 ||
          resolvedActiveIndex == updatedPoints.length - 1)) {
    final start = updatedPoints.first;
    final end = updatedPoints.last;
    if (start.distanceSquared(end) <= loopThreshold * loopThreshold) {
      if (resolvedActiveIndex == 0) {
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
    fixedSegments: baseFixedSegments.isEmpty ? null : baseFixedSegments,
  );
}

List<ElementState> _resolveBindingTargets(
  DrawState state,
  String excludeId,
  DrawPoint position,
  double distance,
) {
  final document = state.domain.document;
  final targets = <ElementState>[];
  final candidates = document.queryElementsAtPointTopDown(position, distance);
  for (final element in candidates) {
    if (element.opacity <= 0 ||
        element.id == excludeId ||
        !ArrowBindingUtils.isBindableTarget(element)) {
      continue;
    }
    targets.add(element);
  }
  return targets;
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
  if (index < 1 || index >= points.length) {
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
