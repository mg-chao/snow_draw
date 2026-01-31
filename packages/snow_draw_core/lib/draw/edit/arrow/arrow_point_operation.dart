import 'dart:ui';

import 'package:meta/meta.dart';

import '../../config/draw_config.dart';
import '../../core/coordinates/element_space.dart';
import '../../elements/types/arrow/arrow_binding.dart';
import '../../elements/types/arrow/arrow_data.dart';
import '../../elements/types/arrow/arrow_geometry.dart';
import '../../elements/types/arrow/arrow_layout.dart';
import '../../elements/types/arrow/arrow_points.dart';
import '../../elements/types/arrow/elbow/elbow_editing.dart';
import '../../elements/types/arrow/elbow/elbow_fixed_segment.dart';
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
    final points = _resolveWorldPoints(element, data);
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
    final data = element?.data is ArrowData ? element!.data as ArrowData : null;
    var points = typedContext.initialPoints;
    var fixedSegments = data?.fixedSegments;
    var hasChanges = false;
    if (typedContext.releaseFixedSegment &&
        element != null &&
        data != null &&
        data.arrowType == ArrowType.elbow) {
      final segmentIndex = typedContext.pointIndex + 1;
      final updatedFixed = (data.fixedSegments ?? const [])
          .where((segment) => segment.index != segmentIndex)
          .toList(growable: false);
      final updated = computeElbowEdit(
        element: element,
        data: data,
        elementsById: state.domain.document.elementMap,
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
      startBinding: data?.startBinding,
      endBinding: data?.endBinding,
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
    final data = element?.data is ArrowData ? element!.data as ArrowData : null;
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

    final points = List<DrawPoint>.from(typedTransform.points);
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
    final dataWithBindings = data.copyWith(
      startBinding: typedTransform.startBinding,
      endBinding: typedTransform.endBinding,
    );
    // Transform local-space points to world space, then back to local space
    // with the new rect center. This preserves world-space positions while
    // keeping the same rotation angle.
    final result = data.arrowType == ArrowType.elbow
        ? () {
            final fixedSegments =
                typedTransform.fixedSegments ?? data.fixedSegments;
            final updated = computeElbowEdit(
              element: element,
              data: dataWithBindings,
              elementsById: state.domain.document.elementMap,
              localPointsOverride: points,
              fixedSegmentsOverride: fixedSegments,
              startBindingOverride: typedTransform.startBinding,
              endBindingOverride: typedTransform.endBinding,
            );
            final rectAndPoints = computeArrowRectAndPoints(
              localPoints: updated.localPoints,
              oldRect: typedContext.elementRect,
              rotation: typedContext.rotation,
              arrowType: data.arrowType,
              strokeWidth: data.strokeWidth,
            );
            final transformedFixedSegments = transformFixedSegments(
              segments: updated.fixedSegments,
              oldRect: typedContext.elementRect,
              newRect: rectAndPoints.rect,
              rotation: typedContext.rotation,
            );
            return (rectAndPoints, transformedFixedSegments, updated);
          }()
        : (
            computeArrowRectAndPoints(
              localPoints: points,
              oldRect: typedContext.elementRect,
              rotation: typedContext.rotation,
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

    final updatedData = data.arrowType == ArrowType.elbow && result.$3 != null
        ? dataWithBindings.copyWith(
            points: normalized,
            fixedSegments: result.$2,
            startIsSpecial: result.$3!.startIsSpecial,
            endIsSpecial: result.$3!.endIsSpecial,
          )
        : dataWithBindings.copyWith(points: normalized);
    final updatedElement = element.copyWith(
      rect: rectAndPoints.rect,
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
    final dataWithBindings = data.copyWith(
      startBinding: typedTransform.startBinding,
      endBinding: typedTransform.endBinding,
    );

    // Transform local-space points to world space, then back to local space
    // with the new rect center. This preserves world-space positions while
    // keeping the same rotation angle.
    final result = data.arrowType == ArrowType.elbow
        ? () {
            final fixedSegments =
                typedTransform.fixedSegments ?? data.fixedSegments;
            final updated = computeElbowEdit(
              element: element,
              data: dataWithBindings,
              elementsById: state.domain.document.elementMap,
              localPointsOverride: typedTransform.points,
              fixedSegmentsOverride: fixedSegments,
              startBindingOverride: typedTransform.startBinding,
              endBindingOverride: typedTransform.endBinding,
            );
            final rectAndPoints = computeArrowRectAndPoints(
              localPoints: updated.localPoints,
              oldRect: typedContext.elementRect,
              rotation: typedContext.rotation,
              arrowType: data.arrowType,
              strokeWidth: data.strokeWidth,
            );
            final transformedFixedSegments = transformFixedSegments(
              segments: updated.fixedSegments,
              oldRect: typedContext.elementRect,
              newRect: rectAndPoints.rect,
              rotation: typedContext.rotation,
            );
            return (rectAndPoints, transformedFixedSegments, updated);
          }()
        : (
            computeArrowRectAndPoints(
              localPoints: typedTransform.points,
              oldRect: typedContext.elementRect,
              rotation: typedContext.rotation,
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

    final updatedData = data.arrowType == ArrowType.elbow && result.$3 != null
        ? dataWithBindings.copyWith(
            points: normalized,
            fixedSegments: result.$2,
            startIsSpecial: result.$3!.startIsSpecial,
            endIsSpecial: result.$3!.endIsSpecial,
          )
        : dataWithBindings.copyWith(points: normalized);
    final updatedElement = element.copyWith(
      rect: rectAndPoints.rect,
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
    required this.initialFixedSegments,
    required this.arrowType,
    required this.pointKind,
    required this.pointIndex,
    required this.dragOffset,
    required this.releaseFixedSegment,
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
      final isBoundarySegment =
          segmentIndex == 1 || segmentIndex == basePoints.length - 1;
      final existingIndex = nextFixedSegments.indexWhere(
        (segment) => segment.index == segmentIndex,
      );
      if (isBoundarySegment) {
        if (existingIndex >= 0) {
          nextFixedSegments.removeAt(existingIndex);
        }
      } else {
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
      }

      final fixedSegmentsResult = nextFixedSegments.isEmpty
          ? null
          : List<ElbowFixedSegment>.unmodifiable(nextFixedSegments);
      final pointsChanged = !_pointsEqual(basePoints, updatedPoints);
      final segmentsChanged = !_fixedSegmentsEqual(
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
    fixedSegments: baseFixedSegments.isEmpty ? null : baseFixedSegments,
  );
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

bool _isHorizontal(DrawPoint a, DrawPoint b) =>
    (a.y - b.y).abs() <= (a.x - b.x).abs();

bool _fixedSegmentsEqual(
  List<ElbowFixedSegment>? a,
  List<ElbowFixedSegment>? b,
) {
  if (identical(a, b)) {
    return true;
  }
  if (a == null || b == null) {
    return a == null && b == null;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i].index != b[i].index) {
      return false;
    }
    final aHorizontal = _isHorizontal(a[i].start, a[i].end);
    final bHorizontal = _isHorizontal(b[i].start, b[i].end);
    if (aHorizontal != bHorizontal) {
      return false;
    }
    final aAxis = aHorizontal
        ? (a[i].start.y + a[i].end.y) / 2
        : (a[i].start.x + a[i].end.x) / 2;
    final bAxis = bHorizontal
        ? (b[i].start.y + b[i].end.y) / 2
        : (b[i].start.x + b[i].end.x) / 2;
    if ((aAxis - bAxis).abs() > 1) {
      return false;
    }
  }
  return true;
}
