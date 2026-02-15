import 'dart:math' as math;

import '../../config/draw_config.dart';
import '../../core/geometry/move_geometry.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../models/selection_overlay_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/object_snap_service.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_geometry.dart';
import '../../types/snap_guides.dart';
import '../../utils/selection_calculator.dart';
import '../../utils/snapping_mode.dart';
import '../apply/edit_apply.dart';
import '../core/edit_compute_pipeline.dart';
import '../core/edit_computed_result.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../core/edit_validation.dart';
import '../core/standard_finish_mixin.dart';

class MoveOperation extends EditOperation with StandardFinishMixin {
  const MoveOperation();

  @override
  EditOperationId get id => EditOperationIds.move;

  @override
  HistoryMetadata createHistoryMetadata({
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<MoveEditContext>(
      context,
      operationName: 'MoveOperation.createHistoryMetadata',
    );
    requireTransform<MoveTransform>(
      transform,
      operationName: 'MoveOperation.createHistoryMetadata',
    );
    return HistoryMetadata.forMove(typedContext.selectedIdsAtStart);
  }

  @override
  MoveEditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final typedParams = requireParams<MoveOperationParams>(
      params,
      operationName: 'MoveOperation.createContext',
    );
    final data = gatherStandardContextData(
      state: state,
      operationName: 'MoveOperation.createContext',
      toSnapshot: (e) => ElementMoveSnapshot(center: e.rect.center),
      initialSelectionBounds: typedParams.initialSelectionBounds,
    );
    final selectedIdsAtStart = data.selectedIds;
    final targetElements = _resolveTargetElements(state, selectedIdsAtStart);
    final referenceElements = resolveReferenceElements(
      state,
      selectedIdsAtStart,
    );
    final snapBounds = _resolveSnapBounds(
      selectedElements: targetElements,
      fallback: data.startBounds,
    );

    return MoveEditContext(
      startPosition: position,
      startBounds: data.startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: data.selectionVersion,
      elementsVersion: data.elementsVersion,
      elementSnapshots: data.elementSnapshots,
      snapBoundsAtStart: snapBounds,
      referenceElements: List<ElementState>.unmodifiable(referenceElements),
      targetElements: List<ElementState>.unmodifiable(targetElements),
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
    final typedContext = requireContext<MoveEditContext>(
      context,
      operationName: 'MoveOperation.update',
    );
    requireTransform<MoveTransform>(
      transform,
      operationName: 'MoveOperation.update',
    );
    final displacement = MoveGeometry.calculateDisplacement(
      typedContext.startPosition,
      currentPosition,
    );

    var snapGuides = const <SnapGuide>[];
    var snappedDx = displacement.dx;
    var snappedDy = displacement.dy;
    final gridConfig = config.grid;
    final snapConfig = config.snap;
    final hasMovement = displacement.dx != 0 || displacement.dy != 0;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: modifiers.snapOverride,
    );
    final shouldGridSnap = hasMovement && snappingMode == SnappingMode.grid;
    final shouldObjectSnap =
        hasMovement &&
        snappingMode == SnappingMode.object &&
        (snapConfig.enablePointSnaps || snapConfig.enableGapSnaps);

    final baseSnapBounds = typedContext.snapBounds;

    if (shouldGridSnap) {
      final targetRect = baseSnapBounds.translate(
        DrawPoint(x: displacement.dx, y: displacement.dy),
      );
      final snappedRect = gridSnapService.snapRect(
        rect: targetRect,
        gridSize: gridConfig.size,
        snapMinX: true,
        snapMinY: true,
      );
      snappedDx += snappedRect.minX - targetRect.minX;
      snappedDy += snappedRect.minY - targetRect.minY;
    } else if (shouldObjectSnap) {
      final zoom = state.application.view.camera.zoom;
      final effectiveZoom = zoom == 0 ? 1.0 : zoom;
      final snapDistance = snapConfig.distance / effectiveZoom;
      final targetRect = baseSnapBounds.translate(
        DrawPoint(x: displacement.dx, y: displacement.dy),
      );
      final referenceElements = typedContext.referenceElements;
      if (referenceElements.isNotEmpty) {
        final targetElements = typedContext.targetElements;
        final result = objectSnapService.snapMove(
          targetRect: targetRect,
          referenceElements: referenceElements,
          snapDistance: snapDistance,
          targetElements: targetElements.isEmpty ? null : targetElements,
          targetOffset: DrawPoint(x: displacement.dx, y: displacement.dy),
          enablePointSnaps: snapConfig.enablePointSnaps,
          enableGapSnaps: snapConfig.enableGapSnaps,
        );
        snappedDx += result.dx;
        snappedDy += result.dy;
        if (snapConfig.showGuides) {
          snapGuides = result.guides;
        }
      }
    }

    final nextTransform = MoveTransform(dx: snappedDx, dy: snappedDy);
    return EditUpdateResult<EditTransform>(
      transform: nextTransform,
      snapGuides: snapGuides,
    );
  }

  @override
  MoveTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) => MoveTransform.zero;

  @override
  EditComputedResult? computeResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<MoveEditContext>(
      context,
      operationName: 'MoveOperation.computeResult',
    );
    final typedTransform = requireTransform<MoveTransform>(
      transform,
      operationName: 'MoveOperation.computeResult',
    );
    if (EditValidation.shouldSkipCompute(
      context: typedContext,
      transform: typedTransform,
    )) {
      return null;
    }

    final updatedById = EditApply.applyMoveToElements(
      snapshots: typedContext.elementSnapshots,
      selectedIds: typedContext.selectedIdsAtStart,
      dx: typedTransform.dx,
      dy: typedTransform.dy,
      currentElementsById: state.domain.document.elementMap,
    );

    final translatedBounds = typedContext.startBounds.translate(
      DrawPoint(x: typedTransform.dx, y: typedTransform.dy),
    );

    return EditComputePipeline.finalize(
      state: state,
      updatedById: updatedById,
      multiSelectBounds: typedContext.isMultiSelect ? translatedBounds : null,
    );
  }

  @override
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  }) => MultiSelectLifecycle.onMoveFinished(
    current,
    newBounds: result.multiSelectBounds!,
  );

  List<ElementState> _resolveTargetElements(
    DrawState state,
    Set<String> selectedIds,
  ) {
    if (selectedIds.isEmpty) {
      return const [];
    }
    final document = state.domain.document;
    return [
      for (final id in selectedIds)
        if (document.getElementById(id) case final ElementState element)
          element,
    ];
  }

  DrawRect _resolveSnapBounds({
    required List<ElementState> selectedElements,
    required DrawRect fallback,
  }) {
    if (selectedElements.isEmpty) {
      return fallback;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final element in selectedElements) {
      final aabb = SelectionCalculator.computeElementWorldAabb(element);
      minX = math.min(minX, aabb.minX);
      minY = math.min(minY, aabb.minY);
      maxX = math.max(maxX, aabb.maxX);
      maxY = math.max(maxY, aabb.maxY);
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
