import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_like_data.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../models/selection_overlay_state.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
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
    final selectionData = SelectionDataComputer.compute(state);
    final startBounds = requireSelectionBounds(
      selectionData: selectionData,
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'RotateOperation.createContext',
    );

    final selectedElements = snapshotSelectedElements(state);
    final selectedIdsAtStart = {...state.domain.selection.selectedIds};
    final elementSnapshots = buildRotateSnapshots(selectedElements);
    final startAngle =
        typedParams.startRotationAngle ??
        AngleCalculator.rawAngle(
          currentPosition: position,
          center: startBounds.center,
        );
    final rotationSnapAngle = typedParams.rotationSnapAngle ?? 0.0;

    final isMulti = selectedIdsAtStart.length > 1;
    final double baseRotation;
    if (isMulti) {
      // Multi-select uses the persistent overlay rotation stored in
      // selection state (kept across edit operations until selection count
      // changes).
      baseRotation =
          state.application.selectionOverlay.multiSelectOverlay?.rotation ??
          0.0;
    } else {
      final selectedId = selectedIdsAtStart.isEmpty
          ? null
          : selectedIdsAtStart.first;
      ElementState? selectedElement;
      if (selectedId != null) {
        for (final element in selectedElements) {
          if (element.id == selectedId) {
            selectedElement = element;
            break;
          }
        }
      }
      baseRotation = selectedElement?.rotation ?? 0.0;
    }

    return RotateEditContext(
      startPosition: position,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: state.domain.selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
      startAngle: startAngle,
      baseRotation: baseRotation,
      rotationSnapAngle: rotationSnapAngle,
      elementSnapshots: elementSnapshots,
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
    final currentTransform = typedTransform.lastRawAngle == null
        ? typedTransform.copyWith(lastRawAngle: typedContext.startAngle)
        : typedTransform;

    final center = typedContext.startBounds.center;
    final rawAngle = AngleCalculator.rawAngle(
      currentPosition: currentPosition,
      center: center,
    );

    final lastRawAngle = currentTransform.lastRawAngle;
    final rawAccumulatedAngle = currentTransform.rawAccumulatedAngle;

    final nextRawAccumulated = lastRawAngle == null
        ? 0.0
        : rawAccumulatedAngle +
              AngleCalculator.normalizeDelta(rawAngle - lastRawAngle);

    final appliedDelta =
        (!modifiers.discreteAngle || typedContext.rotationSnapAngle <= 0)
        ? nextRawAccumulated
        : AngleCalculator.applyDiscreteSnap(
            delta: nextRawAccumulated,
            baseAngle: typedContext.baseRotation,
            snapInterval: typedContext.rotationSnapAngle,
          );

    final nextTransform = currentTransform.copyWith(
      rawAccumulatedAngle: nextRawAccumulated,
      appliedAngle: appliedDelta,
      lastRawAngle: rawAngle,
    );
    if (nextTransform == typedTransform) {
      return EditUpdateResult<EditTransform>(transform: typedTransform);
    }

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
    if (!EditValidation.isValidContext(typedContext) ||
        !EditValidation.isValidBounds(typedContext.startBounds)) {
      return null;
    }
    if (typedTransform.isIdentity) {
      return null;
    }

    final pivot = typedContext.startBounds.center;
    final updatedById = EditApply.applyRotateToElements(
      snapshots: typedContext.elementSnapshots,
      selectedIds: typedContext.selectedIdsAtStart,
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
          typedContext.selectedIdsAtStart.contains(id) &&
          _isElbowArrow(element),
    );
  }

  @override
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  }) =>
      MultiSelectLifecycle.onRotateFinished(
        current,
        newRotation: result.multiSelectRotation!,
        bounds: context.startBounds,
      );

  bool _isElbowArrow(ElementState element) {
    final data = element.data;
    return data is ArrowLikeData && data.arrowType == ArrowType.elbow;
  }
}
