import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../models/selection_overlay_state.dart';
import '../../types/draw_point.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_geometry.dart';
import '../../types/element_style.dart';
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
import 'angle_calculator.dart';

class RotateOperation extends EditOperation with StandardFinishMixin {
  const RotateOperation();

  @override
  EditOperationId get id => EditOperationIds.rotate;

  @override
  HistoryMetadata createHistoryMetadata({
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<RotateEditContext>(
      context,
      operationName: 'RotateOperation.createHistoryMetadata',
    );
    requireTransform<RotateTransform>(
      transform,
      operationName: 'RotateOperation.createHistoryMetadata',
    );
    return HistoryMetadata.forRotate(typedContext.selectedIdsAtStart);
  }

  @override
  RotateEditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final typedParams = requireParams<RotateOperationParams>(
      params,
      operationName: 'RotateOperation.createContext',
    );
    final data = gatherStandardContextData(
      state: state,
      operationName: 'RotateOperation.createContext',
      toSnapshot: (e) =>
          ElementRotateSnapshot(center: e.rect.center, rotation: e.rotation),
      initialSelectionBounds: typedParams.initialSelectionBounds,
    );
    final startAngle =
        typedParams.startRotationAngle ??
        rawAngle(currentPosition: position, center: data.startBounds.center);
    final selectedId = data.selectedIds.isEmpty ? null : data.selectedIds.first;
    final baseRotation = data.selectedIds.length > 1
        ? state.application.selectionOverlay.multiSelectOverlay?.rotation ?? 0.0
        : data.elementSnapshots[selectedId]?.rotation ?? 0.0;

    return RotateEditContext(
      startPosition: position,
      startBounds: data.startBounds,
      selectedIdsAtStart: data.selectedIds,
      selectionVersion: data.selectionVersion,
      elementsVersion: data.elementsVersion,
      startAngle: startAngle,
      baseRotation: baseRotation,
      rotationSnapAngle: typedParams.rotationSnapAngle,
      elementSnapshots: data.elementSnapshots,
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
    final typedContext = requireContext<RotateEditContext>(
      context,
      operationName: 'RotateOperation.update',
    );
    final typedTransform = requireTransform<RotateTransform>(
      transform,
      operationName: 'RotateOperation.update',
    );
    final rawAngleValue = rawAngle(
      currentPosition: currentPosition,
      center: typedContext.startCenter,
    );
    final previousRawAngle =
        typedTransform.lastRawAngle ?? typedContext.startAngle;
    final nextRawAccumulated =
        typedTransform.rawAccumulatedAngle +
        normalizeDelta(rawAngleValue - previousRawAngle);
    final snapInterval = typedContext.rotationSnapAngle;
    final appliedDelta = modifiers.discreteAngle && snapInterval > 0
        ? applyDiscreteSnap(
            delta: nextRawAccumulated,
            baseAngle: typedContext.baseRotation,
            snapInterval: snapInterval,
          )
        : nextRawAccumulated;

    final nextTransform = typedTransform.copyWith(
      rawAccumulatedAngle: nextRawAccumulated,
      appliedAngle: appliedDelta,
      lastRawAngle: rawAngleValue,
    );
    return EditUpdateResult<EditTransform>(transform: nextTransform);
  }

  @override
  RotateTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) {
    final typedContext = requireContext<RotateEditContext>(
      context,
      operationName: 'RotateOperation.initialTransform',
    );
    return RotateTransform.zero.copyWith(lastRawAngle: typedContext.startAngle);
  }

  @override
  EditComputedResult? computeResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<RotateEditContext>(
      context,
      operationName: 'RotateOperation.computeResult',
    );
    final typedTransform = requireTransform<RotateTransform>(
      transform,
      operationName: 'RotateOperation.computeResult',
    );
    if (EditValidation.shouldSkipCompute(
      context: typedContext,
      transform: typedTransform,
    )) {
      return null;
    }

    final rotatableSelectedIds = _resolveRotatableSelectionIds(
      state: state,
      selectedIds: typedContext.selectedIdsAtStart,
    );
    if (rotatableSelectedIds.isEmpty) {
      return null;
    }

    final pivot = typedContext.startBounds.center;
    final updatedById = EditApply.applyRotateToElements(
      snapshots: typedContext.elementSnapshots,
      selectedIds: rotatableSelectedIds,
      pivot: pivot,
      deltaAngle: typedTransform.appliedAngle,
      currentElementsById: state.domain.document.elementMap,
    );

    return EditComputePipeline.finalize(
      state: state,
      updatedById: updatedById,
      multiSelectRotation:
          typedContext.baseRotation + typedTransform.appliedAngle,
      skipBindingUpdate: (id, element) =>
          rotatableSelectedIds.contains(id) && _isElbowArrow(element),
    );
  }

  @override
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  }) => MultiSelectLifecycle.onRotateFinished(
    current,
    newRotation: result.multiSelectRotation!,
    bounds: context.startBounds,
  );

  bool _isElbowArrow(ElementState element) {
    final data = element.data;
    return data is ArrowLikeData && data.arrowType == ArrowType.elbow;
  }

  Set<String> _resolveRotatableSelectionIds({
    required DrawState state,
    required Set<String> selectedIds,
  }) {
    final result = <String>{};
    for (final id in selectedIds) {
      final element = state.domain.document.elementMap[id];
      if (element == null || _isElbowArrow(element)) {
        continue;
      }
      result.add(id);
    }
    return result;
  }
}
