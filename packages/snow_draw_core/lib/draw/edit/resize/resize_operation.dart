import '../../config/draw_config.dart';
import '../../core/coordinates/overlay_space.dart';
import '../../core/geometry/resize_geometry.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
import '../../history/history_metadata.dart';
import '../../models/draw_state.dart';
import '../../models/element_state.dart';
import '../../models/multi_select_lifecycle.dart';
import '../../models/selection_overlay_state.dart';
import '../../services/grid_snap_service.dart';
import '../../services/object_snap_service.dart';
import '../../services/selection_data_computer.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/edit_context.dart';
import '../../types/edit_operation_id.dart';
import '../../types/edit_transform.dart';
import '../../types/element_geometry.dart';
import '../../types/resize_mode.dart';
import '../../types/snap_guides.dart';
import '../../utils/camera_zoom.dart';
import '../../utils/handle_calculator.dart';
import '../../utils/snapping_mode.dart';
import '../../utils/transforms/edit_transform_context.dart';
import '../../utils/transforms/resize_anchor_point.dart';
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
import 'bounds/bounds_calculation.dart';

class ResizeOperation extends EditOperation with StandardFinishMixin {
  const ResizeOperation();

  @override
  EditOperationId get id => EditOperationIds.resize;

  @override
  HistoryMetadata createHistoryMetadata({
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ResizeEditContext>(
      context,
      operationName: 'ResizeOperation.createHistoryMetadata',
    );
    requireTransform<ResizeTransform>(
      transform,
      operationName: 'ResizeOperation.createHistoryMetadata',
    );
    return HistoryMetadata.forResize(typedContext.selectedIdsAtStart);
  }

  @override
  ResizeEditContext createContext({
    required DrawState state,
    required DrawPoint position,
    required EditOperationParams params,
  }) {
    final typedParams = requireParams<ResizeOperationParams>(
      params,
      operationName: 'ResizeOperation.createContext',
    );
    final selectionData = SelectionDataComputer.compute(state);
    final data = gatherStandardContextData(
      state: state,
      operationName: 'ResizeOperation.createContext',
      toSnapshot: (e) =>
          ElementResizeSnapshot(rect: e.rect, rotation: e.rotation),
      initialSelectionBounds: typedParams.initialSelectionBounds,
      selectionData: selectionData,
    );
    final startBounds = data.startBounds;
    final rotation = selectionData.overlayRotation ?? 0.0;
    final rotationCenter = selectionData.overlayCenter ?? startBounds.center;
    final handleOffset = _resolveHandleOffset(
      params: typedParams,
      pointerPosition: position,
      startBounds: startBounds,
      rotation: rotation,
      rotationCenter: rotationCenter,
    );
    final selectedIdsAtStart = data.selectedIds;
    final referenceElements = resolveReferenceElements(
      state,
      selectedIdsAtStart,
    );
    final referenceElementAabbs = ObjectSnapService.buildReferenceAabbs(
      referenceElements,
    );
    final forceSerialNumberAspectRatio = _shouldLockSerialNumberAspectRatio(
      state: state,
      selectedIds: selectedIdsAtStart,
    );

    return ResizeEditContext(
      startPosition: position,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: data.selectionVersion,
      elementsVersion: data.elementsVersion,
      resizeMode: typedParams.resizeMode,
      handleOffset: handleOffset,
      rotation: rotation,
      selectionPadding: typedParams.selectionPadding ?? 0.0,
      elementSnapshots: data.elementSnapshots,
      referenceElements: List<ElementState>.unmodifiable(referenceElements),
      referenceElementAabbs: referenceElementAabbs,
      forceSerialNumberAspectRatio: forceSerialNumberAspectRatio,
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
    final typedContext = requireContext<ResizeEditContext>(
      context,
      operationName: 'ResizeOperation.update',
    );
    requireTransform<ResizeTransform>(
      transform,
      operationName: 'ResizeOperation.update',
    );
    final startBounds = typedContext.startBounds;
    if (_shouldReturnIncompleteTransform(typedContext)) {
      return _incompleteUpdate(currentPosition);
    }

    final transformContext = EditTransformContext(
      startBounds: startBounds,
      rotation: typedContext.rotation,
      center: startBounds.center,
    );
    final maintainAspectRatio =
        modifiers.maintainAspectRatio ||
        typedContext.forceSerialNumberAspectRatio;

    final boundsResult = calculateResizeBounds(
      ResizeBoundsParams(
        transformContext: transformContext,
        mode: typedContext.resizeMode,
        currentPointerWorld: currentPosition,
        handleOffsetLocal: typedContext.handleOffset,
        selectionPadding: typedContext.selectionPadding,
        maintainAspectRatio: maintainAspectRatio,
        resizeFromCenter: modifiers.fromCenter,
      ),
    );

    final newBounds = boundsResult.bounds;
    final anchors = _resolveAnchors(typedContext.resizeMode);
    final snappedResult = _resolveSnappedBounds(
      state: state,
      context: typedContext,
      modifiers: modifiers,
      config: config,
      maintainAspectRatio: maintainAspectRatio,
      bounds: newBounds,
      anchorsX: anchors.x,
      anchorsY: anchors.y,
    );

    final scales = ResizeGeometry.calculateScale(
      original: startBounds,
      scaled: snappedResult.bounds,
      flipX: boundsResult.flipX,
      flipY: boundsResult.flipY,
    );
    final scaleX = scales.scaleX;
    final scaleY = scales.scaleY;

    final anchor = modifiers.fromCenter
        ? startBounds.center
        : oppositeBoundPointLocal(startBounds, typedContext.resizeMode);

    final nextTransform = ResizeTransform.complete(
      currentPosition: currentPosition,
      newSelectionBounds: snappedResult.bounds,
      scaleX: scaleX,
      scaleY: scaleY,
      anchor: anchor,
    );

    return EditUpdateResult<EditTransform>(
      transform: nextTransform,
      snapGuides: snappedResult.guides,
    );
  }

  @override
  ResizeTransform initialTransform({
    required DrawState state,
    required EditContext context,
    required DrawPoint startPosition,
  }) => ResizeTransform.incomplete(currentPosition: startPosition);

  @override
  EditComputedResult? computeResult({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ResizeEditContext>(
      context,
      operationName: 'ResizeOperation.computeResult',
    );
    final typedTransform = requireTransform<ResizeTransform>(
      transform,
      operationName: 'ResizeOperation.computeResult',
    );
    if (EditValidation.shouldSkipCompute(
      context: typedContext,
      transform: typedTransform,
      requireValidBounds: !typedContext.isSingleSelect,
    )) {
      return null;
    }

    final newSelectionBounds = typedTransform.newSelectionBounds!;
    final scaleX = typedTransform.scaleX!;
    final scaleY = typedTransform.scaleY!;
    final anchor = typedTransform.anchor!;

    final updatedById = EditApply.applyResizeToElements(
      snapshots: typedContext.elementSnapshots,
      selectedIds: typedContext.selectedIdsAtStart,
      context: typedContext,
      newSelectionBounds: newSelectionBounds,
      scaleX: scaleX,
      scaleY: scaleY,
      anchor: anchor,
      currentElementsById: state.domain.document.elementMap,
    );

    return EditComputePipeline.finalize(
      state: state,
      updatedById: updatedById,
      multiSelectBounds: typedContext.isMultiSelect ? newSelectionBounds : null,
    );
  }

  @override
  SelectionOverlayState updateOverlay({
    required SelectionOverlayState current,
    required EditComputedResult result,
    required EditContext context,
  }) => MultiSelectLifecycle.onResizeFinished(
    current,
    newBounds: result.multiSelectBounds!,
  );

  EditUpdateResult<EditTransform> _incompleteUpdate(
    DrawPoint currentPosition,
  ) => EditUpdateResult(
    transform: ResizeTransform.incomplete(currentPosition: currentPosition),
  );

  bool _shouldReturnIncompleteTransform(ResizeEditContext context) =>
      context.selectedIdsAtStart.isEmpty ||
      (context.isMultiSelect &&
          (context.startBounds.width == 0 || context.startBounds.height == 0));

  ({List<SnapAxisAnchor> x, List<SnapAxisAnchor> y}) _resolveAnchors(
    ResizeMode mode,
  ) => switch (mode) {
    ResizeMode.topLeft => (
      x: const [SnapAxisAnchor.start],
      y: const [SnapAxisAnchor.start],
    ),
    ResizeMode.top => (x: const [], y: const [SnapAxisAnchor.start]),
    ResizeMode.topRight => (
      x: const [SnapAxisAnchor.end],
      y: const [SnapAxisAnchor.start],
    ),
    ResizeMode.right => (x: const [SnapAxisAnchor.end], y: const []),
    ResizeMode.bottomRight => (
      x: const [SnapAxisAnchor.end],
      y: const [SnapAxisAnchor.end],
    ),
    ResizeMode.bottom => (x: const [], y: const [SnapAxisAnchor.end]),
    ResizeMode.bottomLeft => (
      x: const [SnapAxisAnchor.start],
      y: const [SnapAxisAnchor.end],
    ),
    ResizeMode.left => (x: const [SnapAxisAnchor.start], y: const []),
  };

  DrawPoint _resolveHandleOffset({
    required ResizeOperationParams params,
    required DrawPoint pointerPosition,
    required DrawRect startBounds,
    required double rotation,
    required DrawPoint rotationCenter,
  }) {
    final explicitOffset = params.handleOffset;
    if (explicitOffset != null) {
      return explicitOffset;
    }

    final overlaySpace = OverlaySpace(
      rotation: rotation,
      origin: rotationCenter,
    );
    final localPointerPosition = overlaySpace.fromWorld(pointerPosition);
    final handlePosition = HandleCalculator.getResizeHandlePosition(
      bounds: startBounds,
      mode: params.resizeMode,
      padding: params.selectionPadding ?? 0.0,
    );
    return DrawPoint(
      x: handlePosition.x - localPointerPosition.x,
      y: handlePosition.y - localPointerPosition.y,
    );
  }

  bool _shouldLockSerialNumberAspectRatio({
    required DrawState state,
    required Set<String> selectedIds,
  }) =>
      selectedIds.isNotEmpty &&
      selectedIds.every((id) {
        final element = state.domain.document.elementMap[id];
        return element != null && element.data is SerialNumberData;
      });

  ({DrawRect bounds, List<SnapGuide> guides}) _resolveSnappedBounds({
    required DrawState state,
    required ResizeEditContext context,
    required EditModifiers modifiers,
    required DrawConfig config,
    required bool maintainAspectRatio,
    required DrawRect bounds,
    required List<SnapAxisAnchor> anchorsX,
    required List<SnapAxisAnchor> anchorsY,
  }) {
    final canSnap = !context.hasRotation && !modifiers.fromCenter;
    if (!canSnap) {
      return _unsnapped(bounds);
    }

    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: modifiers.snapOverride,
    );
    final snapConfig = config.snap;
    final snapMinX = anchorsX.contains(SnapAxisAnchor.start);
    final snapMaxX = anchorsX.contains(SnapAxisAnchor.end);
    final snapMinY = anchorsY.contains(SnapAxisAnchor.start);
    final snapMaxY = anchorsY.contains(SnapAxisAnchor.end);

    if (snappingMode == SnappingMode.grid && !maintainAspectRatio) {
      return (
        bounds: gridSnapService.snapRect(
          rect: bounds,
          gridSize: config.grid.size,
          snapMinX: snapMinX,
          snapMaxX: snapMaxX,
          snapMinY: snapMinY,
          snapMaxY: snapMaxY,
        ),
        guides: const <SnapGuide>[],
      );
    }

    final shouldObjectSnap =
        snappingMode == SnappingMode.object &&
        snapConfig.enablePointSnaps &&
        context.referenceElements.isNotEmpty;
    if (!shouldObjectSnap) {
      return _unsnapped(bounds);
    }

    final snapDistance = resolveZoomAdjustedDistance(
      distance: snapConfig.distance,
      zoom: state.application.view.camera.zoom,
    );
    final result = objectSnapService.snapResize(
      targetRect: bounds,
      referenceElements: context.referenceElements,
      referenceAabbs: context.referenceElementAabbs,
      snapDistance: snapDistance,
      targetAnchorsX: anchorsX,
      targetAnchorsY: anchorsY,
    );

    final snappedBounds = result.hasSnap
        ? DrawRect(
            minX: bounds.minX + (snapMinX ? result.dx : 0),
            minY: bounds.minY + (snapMinY ? result.dy : 0),
            maxX: bounds.maxX + (snapMaxX ? result.dx : 0),
            maxY: bounds.maxY + (snapMaxY ? result.dy : 0),
          )
        : bounds;
    return (
      bounds: snappedBounds,
      guides: snapConfig.showGuides ? result.guides : const <SnapGuide>[],
    );
  }

  ({DrawRect bounds, List<SnapGuide> guides}) _unsnapped(DrawRect bounds) =>
      (bounds: bounds, guides: const <SnapGuide>[]);
}
