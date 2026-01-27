import 'dart:math' as math;

import '../../config/draw_config.dart';
import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../elements/types/text/text_bounds.dart';
import '../../elements/types/text/text_data.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/interaction_state.dart';
import '../../models/selection_state.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
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
import 'free_transform_context.dart';

class FreeTransformOperation extends EditOperation {
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

    final selectedIds = {...state.domain.selection.selectedIds};
    final snapshots = <String, ElementFullSnapshot>{};
    for (final element in snapshotSelectedElements(state)) {
      snapshots[element.id] = ElementFullSnapshot(
        id: element.id,
        center: element.center,
        bounds: element.rect,
        rotation: element.rotation,
      );
    }

    return FreeTransformEditContext(
      startPosition: position,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIds,
      selectionVersion: state.domain.selection.selectionVersion,
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
        modifiers: modifiers,
      ),
      FreeTransformMode.rotate => _computeRotateTransform(
        context: typedContext,
        currentPosition: currentPosition,
        modifiers: modifiers,
      ),
    };

    final updatedTransform = _replaceByType(
      typedTransform,
      modeTransform,
    ).optimize();
    if (updatedTransform == typedTransform) {
      return EditUpdateResult(transform: typedTransform);
    }

    return EditUpdateResult(transform: updatedTransform);
  }

  @override
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<FreeTransformEditContext>(
      context,
      operationName: 'FreeTransformOperation.finish',
    );
    final typedTransform = requireTransform<CompositeTransform>(
      transform,
      operationName: 'FreeTransformOperation.finish',
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

    final newOverlay = typedContext.isMultiSelect
        ? state.application.selectionOverlay.copyWith(
            multiSelectOverlay: MultiSelectOverlayState(
              bounds: result.multiSelectBounds ?? typedContext.startBounds,
              rotation:
                  result.multiSelectRotation ?? typedContext.selectionRotation,
            ),
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

  EditComputedResult? _compute({
    required DrawState state,
    required FreeTransformEditContext context,
    required CompositeTransform transform,
  }) {
    if (transform.isIdentity) {
      return null;
    }
    if (!EditValidation.isValidContext(context)) {
      return null;
    }

    final pivot = context.startBounds.center;
    final rotationDelta = _rotationDelta(transform);
    final currentById = state.domain.document.elementMap;

    final updatedById = <String, ElementState>{};
    for (final entry in context.elementSnapshots.entries) {
      final snapshot = entry.value;
      final current = currentById[entry.key];
      if (current == null) {
        continue;
      }

      final newCenter = transform.applyToPoint(snapshot.center, pivot: pivot);
      final newBounds = transform.applyToRect(snapshot.bounds, pivot: pivot);
      final newRotation = snapshot.rotation + rotationDelta;

      var updated = current.copyWith(
        rect: _rectFromCenter(newCenter, newBounds.width, newBounds.height),
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

    final newSelectionBounds = transform.applyToRect(
      context.startBounds,
      pivot: pivot,
    );

    return EditComputedResult(
      updatedElements: updatedById,
      multiSelectBounds: newSelectionBounds,
      multiSelectRotation: context.selectionRotation + rotationDelta,
    );
  }

  @override
  EditPreview buildPreview({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<FreeTransformEditContext>(
      context,
      operationName: 'FreeTransformOperation.buildPreview',
    );
    final typedTransform = requireTransform<CompositeTransform>(
      transform,
      operationName: 'FreeTransformOperation.buildPreview',
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
      multiSelectRotation: result.multiSelectRotation,
    );
  }

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
    required EditModifiers modifiers,
  }) {
    final center = context.startBounds.center;
    final startVector = context.startPosition - center;
    final currentVector = currentPosition - center;
    final startDist = math.sqrt(
      startVector.x * startVector.x + startVector.y * startVector.y,
    );
    final currentDist = math.sqrt(
      currentVector.x * currentVector.x + currentVector.y * currentVector.y,
    );

    if (startDist == 0) {
      return ResizeTransform.incomplete(currentPosition: currentPosition);
    }

    final scale = currentDist / startDist;

    final newBounds = _scaleBounds(context.startBounds, center, scale, scale);
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

  CompositeTransform _replaceByType(
    CompositeTransform current,
    EditTransform next,
  ) {
    final updated = <EditTransform>[];
    var replaced = false;
    for (final transform in current.transforms) {
      if (transform.runtimeType == next.runtimeType) {
        if (!replaced) {
          updated.add(next);
          replaced = true;
        }
        continue;
      }
      updated.add(transform);
    }
    if (!replaced) {
      updated.add(next);
    }
    return CompositeTransform(updated);
  }

  double _rotationDelta(EditTransform transform) => switch (transform) {
    RotateTransform(:final appliedAngle) => appliedAngle,
    CompositeTransform(:final transforms) => transforms.fold(
      0,
      (sum, t) => sum + _rotationDelta(t),
    ),
    _ => 0.0,
  };

  DrawRect _scaleBounds(
    DrawRect bounds,
    DrawPoint center,
    double scaleX,
    double scaleY,
  ) {
    final halfWidth = bounds.width * scaleX / 2;
    final halfHeight = bounds.height * scaleY / 2;
    return DrawRect(
      minX: center.x - halfWidth,
      minY: center.y - halfHeight,
      maxX: center.x + halfWidth,
      maxY: center.y + halfHeight,
    );
  }

  DrawRect _rectFromCenter(DrawPoint center, double width, double height) {
    final halfWidth = width / 2;
    final halfHeight = height / 2;
    return DrawRect(
      minX: center.x - halfWidth,
      minY: center.y - halfHeight,
      maxX: center.x + halfWidth,
      maxY: center.y + halfHeight,
    );
  }
}
