import 'dart:math' as math;

import '../../config/draw_config.dart';
import '../../core/geometry/move_geometry.dart';
import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../services/grid_snap_service.dart';
import '../../services/object_snap_service.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/snap_guides.dart';
import '../../utils/selection_calculator.dart';
import '../../utils/snapping_mode.dart';
import '../apply/edit_apply.dart';
import '../core/edit_computed_result.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../core/edit_validation.dart';
import '../preview/edit_preview.dart';

class MoveOperation extends EditOperation {
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
    final startBounds = requireSelectionBounds(
      selectionData: SelectionDataComputer.compute(state),
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'MoveOperation.createContext',
    );

    final selectedIdsAtStart = {...state.domain.selection.selectedIds};
    final elementSnapshots = buildMoveSnapshots(
      snapshotSelectedElements(state),
    );

    return MoveEditContext(
      startPosition: position,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: state.domain.selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
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
    final shouldGridSnap =
        hasMovement && snappingMode == SnappingMode.grid;
    final shouldObjectSnap =
        hasMovement &&
        snappingMode == SnappingMode.object &&
        (snapConfig.enablePointSnaps || snapConfig.enableGapSnaps);

    if (shouldGridSnap) {
      final baseSnapBounds = _resolveSnapBounds(state, typedContext);
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
      final baseSnapBounds = _resolveSnapBounds(state, typedContext);
      final targetRect = baseSnapBounds.translate(
        DrawPoint(x: displacement.dx, y: displacement.dy),
      );
      final referenceElements = _resolveReferenceElements(
        state,
        typedContext.selectedIdsAtStart,
      );
      final targetElements = _resolveTargetElements(
        state,
        typedContext.selectedIdsAtStart,
      );
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
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<MoveEditContext>(
      context,
      operationName: 'MoveOperation.finish',
    );
    final typedTransform = requireTransform<MoveTransform>(
      transform,
      operationName: 'MoveOperation.finish',
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

    // Update multi-select overlay state after committing a move.
    final newOverlay = typedContext.isMultiSelect
        ? MultiSelectLifecycle.onMoveFinished(
            state.application.selectionOverlay,
            newBounds: result.multiSelectBounds!,
          )
        : state.application.selectionOverlay;

    final nextDomain = state.domain.copyWith(
      document: state.domain.document.copyWith(elements: newElements),
    );
    final nextApplication = state.application.copyWith(
      interaction: const IdleState(),
      selectionOverlay: newOverlay,
    );

    return state.copyWith(domain: nextDomain, application: nextApplication);
  }

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<MoveEditContext>(
      context,
      operationName: 'MoveOperation.buildPreview',
    );
    final typedTransform = requireTransform<MoveTransform>(
      transform,
      operationName: 'MoveOperation.buildPreview',
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
      multiSelectBounds: result.multiSelectBounds,
    );
  }

  EditComputedResult? _compute({
    required DrawState state,
    required MoveEditContext context,
    required MoveTransform transform,
  }) {
    if (!EditValidation.isValidContext(context) ||
        !EditValidation.isValidBounds(context.startBounds)) {
      return null;
    }
    if (transform.isIdentity) {
      return null;
    }

    final updatedById = EditApply.applyMoveToElements(
      snapshots: context.elementSnapshots,
      selectedIds: context.selectedIdsAtStart,
      dx: transform.dx,
      dy: transform.dy,
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

    final translatedBounds = context.startBounds.translate(
      DrawPoint(x: transform.dx, y: transform.dy),
    );

    return EditComputedResult(
      updatedElements: updatedById,
      multiSelectBounds: context.isMultiSelect ? translatedBounds : null,
    );
  }

  List<ElementState> _resolveReferenceElements(
    DrawState state,
    Set<String> selectedIds,
  ) =>
      state.domain.document.elements
          .where(
            (element) =>
                element.opacity > 0 && !selectedIds.contains(element.id),
          )
          .toList();

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

  DrawRect _resolveSnapBounds(DrawState state, MoveEditContext context) {
    final selectedIds = context.selectedIdsAtStart;
    if (selectedIds.isEmpty) {
      return context.startBounds;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    var hasElement = false;

    for (final id in selectedIds) {
      final element = state.domain.document.getElementById(id);
      if (element == null) {
        continue;
      }
      final aabb = SelectionCalculator.computeElementWorldAabb(element);
      minX = math.min(minX, aabb.minX);
      minY = math.min(minY, aabb.minY);
      maxX = math.max(maxX, aabb.maxX);
      maxY = math.max(maxY, aabb.maxY);
      hasElement = true;
    }

    if (!hasElement) {
      return context.startBounds;
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }
}
