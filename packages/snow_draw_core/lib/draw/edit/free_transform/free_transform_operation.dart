import 'dart:math' as math;

import '../../config/draw_config.dart';
import '../../elements/types/text/text_bounds.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/selection_overlay_state.dart';
import '../../models/selection_state.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../core/edit_compute_pipeline.dart';
import '../core/edit_computed_result.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../core/edit_validation.dart';
import '../core/standard_finish_mixin.dart';
import 'free_transform_context.dart';

class FreeTransformOperation extends EditOperation with StandardFinishMixin {
  const FreeTransformOperation();

  @override
  EditOperationId get id => EditOperationIds.freeTransform;

  @override
  FreeTransformEditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final typedParams = requireParams<FreeTransformOperationParams>(
      params,
      operationName: 'FreeTransformOperation.createContext',
    );
    final selectionData = SelectionDataComputer.compute(state);
    final startBounds = requireSelectionBounds(
      selectionData: selectionData,
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'FreeTransformOperation.createContext',
    );
    final selection = state.domain.selection;
    final snapshots = buildSnapshots(
      snapshotSelectedElements(state),
      (element) => ElementFullSnapshot(
        center: element.center,
        bounds: element.rect,
        rotation: element.rotation,
      ),
    );

    return FreeTransformEditContext(
      startPosition: position,
      startBounds: startBounds,
      selectedIdsAtStart: {...selection.selectedIds},
      selectionVersion: selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
      currentMode: typedParams.initialMode,
      elementSnapshots: snapshots,
      selectionRotation: selectionData.overlayRotation ?? 0.0,
    );
  }

  @override
  CompositeTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) => const CompositeTransform([]);

  @override
  EditUpdateResult<EditTransform> update({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
    required DrawConfig config,
  }) {
    final typedContext = requireContext<FreeTransformEditContext>(
      context,
      operationName: 'FreeTransformOperation.update',
    );
    final typedTransform = requireTransform<CompositeTransform>(
      transform,
      operationName: 'FreeTransformOperation.update',
    );
    final modeTransform = switch (typedContext.currentMode) {
      FreeTransformMode.move => _computeMoveTransform(
        typedContext,
        currentPosition,
      ),
      FreeTransformMode.resize => _computeResizeTransform(
        context: typedContext,
        currentPosition: currentPosition,
      ),
      FreeTransformMode.rotate => _computeRotateTransform(
        context: typedContext,
        currentPosition: currentPosition,
        modifiers: modifiers,
      ),
    };

    final updatedTransform = CompositeTransform([modeTransform]).optimize();
    if (updatedTransform == typedTransform) {
      return EditUpdateResult(transform: typedTransform);
    }

    return EditUpdateResult(transform: updatedTransform);
  }

  @override
  EditComputedResult? computeResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<FreeTransformEditContext>(
      context,
      operationName: 'FreeTransformOperation.computeResult',
    );
    final typedTransform = requireTransform<CompositeTransform>(
      transform,
      operationName: 'FreeTransformOperation.computeResult',
    );
    if (EditValidation.shouldSkipCompute(
      context: typedContext,
      transform: typedTransform,
      requireValidBounds: false,
    )) {
      return null;
    }

    final pivot = typedContext.startBounds.center;
    final rotationDelta = _rotationDelta(typedTransform);
    final currentById = state.domain.document.elementMap;

    final updatedById = <String, ElementState>{};
    for (final entry in typedContext.elementSnapshots.entries) {
      final snapshot = entry.value;
      final current = currentById[entry.key];
      if (current == null) {
        continue;
      }

      final transformedBounds = typedTransform.applyToRect(
        snapshot.bounds,
        pivot: pivot,
      );
      final newRotation = snapshot.rotation + rotationDelta;

      var updated = current.copyWith(
        rect: transformedBounds,
        rotation: newRotation,
      );
      final data = updated.data;
      if (data is TextData) {
        final clampedRect = clampTextRectToLayout(
          rect: updated.rect,
          startRect: snapshot.bounds,
          anchor: pivot,
          data: data,
          keepCenter: true,
        );
        if (clampedRect != updated.rect) {
          updated = updated.copyWith(rect: clampedRect);
        }
      }
      updatedById[entry.key] = updated;
    }

    final newSelectionBounds = typedTransform.applyToRect(
      typedContext.startBounds,
      pivot: pivot,
    );

    return EditComputePipeline.finalize(
      state: state,
      updatedById: updatedById,
      multiSelectBounds: newSelectionBounds,
      multiSelectRotation: typedContext.selectionRotation + rotationDelta,
    );
  }

  @override
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  }) => current.copyWith(
    multiSelectOverlay: MultiSelectOverlayState(
      bounds: result.multiSelectBounds!,
      rotation: result.multiSelectRotation!,
    ),
  );

  MoveTransform _computeMoveTransform(
    FreeTransformEditContext context,
    DrawPoint currentPosition,
  ) {
    final delta = currentPosition - context.startPosition;
    return MoveTransform(dx: delta.x, dy: delta.y);
  }

  ResizeTransform _computeResizeTransform({
    required FreeTransformEditContext context,
    required DrawPoint currentPosition,
  }) {
    final center = context.startBounds.center;
    final startDist = context.startPosition.distance(center);
    final currentDist = currentPosition.distance(center);

    if (startDist == 0) {
      return ResizeTransform.incomplete(currentPosition: currentPosition);
    }

    final scale = currentDist / startDist;

    final newBounds = _scaleBounds(context.startBounds, center, scale);
    return ResizeTransform.complete(
      currentPosition: currentPosition,
      newSelectionBounds: newBounds,
      scaleX: scale,
      scaleY: scale,
      anchor: center,
    );
  }

  RotateTransform _computeRotateTransform({
    required FreeTransformEditContext context,
    required DrawPoint currentPosition,
    required EditModifiers modifiers,
  }) {
    final center = context.startBounds.center;
    final startAngle = math.atan2(
      context.startPosition.y - center.y,
      context.startPosition.x - center.x,
    );
    final currentAngle = math.atan2(
      currentPosition.y - center.y,
      currentPosition.x - center.x,
    );
    var delta = currentAngle - startAngle;

    if (modifiers.discreteAngle) {
      const snapAngle = 15 * math.pi / 180;
      delta = (delta / snapAngle).round() * snapAngle;
    }

    return RotateTransform(
      rawAccumulatedAngle: delta,
      appliedAngle: delta,
      lastRawAngle: currentAngle,
    );
  }

  double _rotationDelta(CompositeTransform transform) {
    for (final item in transform.transforms) {
      if (item is RotateTransform) {
        return item.appliedAngle;
      }
    }
    return 0;
  }

  DrawRect _scaleBounds(DrawRect bounds, DrawPoint center, double scale) {
    final halfWidth = bounds.width * scale / 2;
    final halfHeight = bounds.height * scale / 2;
    return DrawRect(
      minX: center.x - halfWidth,
      minY: center.y - halfHeight,
      maxX: center.x + halfWidth,
      maxY: center.y + halfHeight,
    );
  }
}
