import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../apply/edit_apply.dart';
import '../core/edit_computed_result.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../core/edit_validation.dart';
import '../preview/edit_preview.dart';
import 'angle_calculator.dart';

class RotateOperation extends EditOperation {
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
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<RotateEditContext>(
      context,
      operationName: 'RotateOperation.finish',
    );
    final typedTransform = requireTransform<RotateTransform>(
      transform,
      operationName: 'RotateOperation.finish',
    );
    final result = _compute(
      state: state,
      context: typedContext,
      transform: typedTransform,
    );
    if (result == null) {
      return state.copyWith(application: state.application.toIdle());
    }

    final newElements = EditApply.replaceElementsById(
      elements: state.domain.document.elements,
      replacementsById: result.updatedElements,
    );

    // Update multi-select overlay rotation while keeping bounds stable.
    final overlay = typedContext.isMultiSelect
        ? MultiSelectLifecycle.onRotateFinished(
            state.application.selectionOverlay,
            newRotation: result.multiSelectRotation!,
            bounds: typedContext.startBounds,
          )
        : state.application.selectionOverlay;

    final nextDomain = state.domain.copyWith(
      document: state.domain.document.copyWith(elements: newElements),
    );
    final nextApplication = state.application.copyWith(
      interaction: const IdleState(),
      selectionOverlay: overlay,
    );

    return state.copyWith(domain: nextDomain, application: nextApplication);
  }

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<RotateEditContext>(
      context,
      operationName: 'RotateOperation.buildPreview',
    );
    final typedTransform = requireTransform<RotateTransform>(
      transform,
      operationName: 'RotateOperation.buildPreview',
    );
    final result = _compute(
      state: state,
      context: typedContext,
      transform: typedTransform,
    );
    if (result == null) {
      return EditPreview.none;
    }

    return buildEditPreview(
      state: state,
      context: typedContext,
      previewElementsById: result.updatedElements,
      multiSelectRotation: result.multiSelectRotation,
    );
  }

  EditComputedResult? _compute({
    required DrawState state,
    required RotateEditContext context,
    required RotateTransform transform,
  }) {
    if (!EditValidation.isValidContext(context) ||
        !EditValidation.isValidBounds(context.startBounds)) {
      return null;
    }
    if (transform.isIdentity) {
      return null;
    }

    final pivot = context.startBounds.center;
    final updatedById = EditApply.applyRotateToElements(
      snapshots: context.elementSnapshots,
      selectedIds: context.selectedIdsAtStart,
      pivot: pivot,
      deltaAngle: transform.appliedAngle,
      currentElementsById: state.domain.document.elementMap,
    );
    if (updatedById.isEmpty) {
      return null;
    }

    final elementsById = {
      ...state.domain.document.elementMap,
      ...updatedById,
    };
    final bindingUpdates = ArrowBindingResolver.resolveBoundArrows(
      elementsById: elementsById,
      changedElementIds: updatedById.keys.toSet(),
    );
    if (bindingUpdates.isNotEmpty) {
      updatedById.addAll(bindingUpdates);
    }

    return EditComputedResult(
      updatedElements: updatedById,
      multiSelectRotation: context.baseRotation + transform.appliedAngle,
    );
  }
}
