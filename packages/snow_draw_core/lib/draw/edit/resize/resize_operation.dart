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
import '../../utils/handle_calculator.dart';
import '../../utils/snapping_mode.dart';
import '../../utils/transforms/edit_transform_context.dart';
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
import 'bounds/resize_geometry.dart';

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
    final startBounds = requireSelectionBounds(
      selectionData: selectionData,
      initialSelectionBounds: typedParams.initialSelectionBounds,
      operationName: 'ResizeOperation.createContext',
    );

    final rotation = selectionData.overlayRotation ?? 0.0;
    final rotationCenter = selectionData.overlayCenter ?? startBounds.center;

    final DrawPoint handleOffset;
    if (typedParams.handleOffset != null) {
      handleOffset = typedParams.handleOffset!;
    } else {
      final overlaySpace = OverlaySpace(
        rotation: rotation,
        origin: rotationCenter,
      );
      final localPointerPosition = overlaySpace.fromWorld(position);

      final handlePosition = HandleCalculator.getResizeHandlePosition(
        bounds: startBounds,
        mode: typedParams.resizeMode,
        padding: typedParams.selectionPadding ?? 0.0,
      );

      handleOffset = DrawPoint(
        x: handlePosition.x - localPointerPosition.x,
        y: handlePosition.y - localPointerPosition.y,
      );
    }

    final selectedIdsAtStart = {...state.domain.selection.selectedIds};
    final referenceElements = resolveReferenceElements(
      state,
      selectedIdsAtStart,
    );
    final forceSerialNumberAspectRatio = _shouldLockSerialNumberAspectRatio(
      state: state,
      selectedIds: selectedIdsAtStart,
    );
    final elementSnapshots = buildSnapshots(
      snapshotSelectedElements(state),
      (e) => ElementResizeSnapshot(rect: e.rect, rotation: e.rotation),
    );

    return ResizeEditContext(
      startPosition: position,
      startBounds: startBounds,
      selectedIdsAtStart: selectedIdsAtStart,
      selectionVersion: state.domain.selection.selectionVersion,
      elementsVersion: state.domain.document.elementsVersion,
      resizeMode: typedParams.resizeMode,
      handleOffset: handleOffset,
      rotation: rotation,
      selectionPadding: typedParams.selectionPadding ?? 0.0,
      elementSnapshots: elementSnapshots,
      referenceElements: List<ElementState>.unmodifiable(referenceElements),
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
    final selectedIdsAtStart = typedContext.selectedIdsAtStart;
    if (selectedIdsAtStart.isEmpty) {
      return EditUpdateResult(
        transform: ResizeTransform.incomplete(currentPosition: currentPosition),
      );
    }

    final startBounds = typedContext.startBounds;
    if ((startBounds.width == 0 || startBounds.height == 0) &&
        typedContext.isMultiSelect) {
      return EditUpdateResult(
        transform: ResizeTransform.incomplete(currentPosition: currentPosition),
      );
    }

    final transformContext = EditTransformContext(
      startBounds: startBounds,
      rotation: typedContext.rotation,
      center: startBounds.center,
      isMultiSelect: selectedIdsAtStart.length > 1,
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
    if (boundsResult == null) {
      return EditUpdateResult(
        transform: ResizeTransform.incomplete(currentPosition: currentPosition),
      );
    }

    var newBounds = boundsResult.bounds;
    var snapGuides = const <SnapGuide>[];
    final gridConfig = config.grid;
    final snapConfig = config.snap;
    // Determine which edges of the selection bounds should snap based on resize
    // mode.
    // For example, resizing from the right edge means the right edge should
    // snap.
    final anchorsX = _resolveAnchorsX(typedContext.resizeMode);
    final anchorsY = _resolveAnchorsY(typedContext.resizeMode);
    final hasAnchors = anchorsX.isNotEmpty || anchorsY.isNotEmpty;
    // Snapping is disabled for rotated selections, center-based resize, or when
    // no edges are being moved (shouldn't happen in practice).
    final canSnap =
        !typedContext.hasRotation && !modifiers.fromCenter && hasAnchors;
    final snappingMode = resolveEffectiveSnappingModeForConfig(
      config: config,
      ctrlPressed: modifiers.snapOverride,
    );
    // Grid snapping is disabled when maintaining aspect ratio to avoid
    // conflicts
    // between the aspect ratio constraint and grid alignment.
    final shouldGridSnap =
        canSnap && snappingMode == SnappingMode.grid && !maintainAspectRatio;
    final shouldObjectSnap =
        canSnap &&
        snappingMode == SnappingMode.object &&
        snapConfig.enablePointSnaps;

    // Apply snapping to the calculated bounds
    if (shouldGridSnap) {
      newBounds = gridSnapService.snapRect(
        rect: newBounds,
        gridSize: gridConfig.size,
        snapMinX: anchorsX.contains(SnapAxisAnchor.start),
        snapMaxX: anchorsX.contains(SnapAxisAnchor.end),
        snapMinY: anchorsY.contains(SnapAxisAnchor.start),
        snapMaxY: anchorsY.contains(SnapAxisAnchor.end),
      );
    } else if (shouldObjectSnap && typedContext.referenceElements.isNotEmpty) {
      // Calculate snap distance in world space (accounting for zoom level)
      final zoom = state.application.view.camera.zoom;
      final effectiveZoom = zoom == 0 ? 1.0 : zoom;
      final snapDistance = snapConfig.distance / effectiveZoom;
      final result = objectSnapService.snapResize(
        targetRect: newBounds,
        referenceElements: typedContext.referenceElements,
        snapDistance: snapDistance,
        targetAnchorsX: anchorsX,
        targetAnchorsY: anchorsY,
      );
      if (result.hasSnap) {
        // Apply snap offset only to the edges that are being moved during
        // resize
        final moveMinX = anchorsX.contains(SnapAxisAnchor.start);
        final moveMaxX = anchorsX.contains(SnapAxisAnchor.end);
        final moveMinY = anchorsY.contains(SnapAxisAnchor.start);
        final moveMaxY = anchorsY.contains(SnapAxisAnchor.end);
        newBounds = DrawRect(
          minX: newBounds.minX + (moveMinX ? result.dx : 0),
          minY: newBounds.minY + (moveMinY ? result.dy : 0),
          maxX: newBounds.maxX + (moveMaxX ? result.dx : 0),
          maxY: newBounds.maxY + (moveMaxY ? result.dy : 0),
        );
      }
      if (snapConfig.showGuides) {
        snapGuides = result.guides;
      }
    }

    final scales = ResizeGeometry.calculateScale(
      original: startBounds,
      scaled: newBounds,
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
      newSelectionBounds: newBounds,
      scaleX: scaleX,
      scaleY: scaleY,
      anchor: anchor,
    );

    return EditUpdateResult<EditTransform>(
      transform: nextTransform,
      snapGuides: snapGuides,
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
    if (!typedTransform.isComplete) {
      return null;
    }
    if (EditValidation.shouldSkipCompute(
      context: typedContext,
      transform: typedTransform,
      requireValidBounds: !typedContext.isSingleSelect,
    )) {
      return null;
    }

    final startBounds = typedContext.startBounds;
    final newSelectionBounds = typedTransform.newSelectionBounds!;
    final scaleX = typedTransform.scaleX!;
    final scaleY = typedTransform.scaleY!;
    final anchor = typedTransform.anchor!;

    if (_isIdentityTransform(scaleX, scaleY, startBounds, newSelectionBounds)) {
      return null;
    }

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

  List<SnapAxisAnchor> _resolveAnchorsX(ResizeMode mode) {
    final moveMinX =
        mode == ResizeMode.left ||
        mode == ResizeMode.topLeft ||
        mode == ResizeMode.bottomLeft;
    final moveMaxX =
        mode == ResizeMode.right ||
        mode == ResizeMode.topRight ||
        mode == ResizeMode.bottomRight;
    return [
      if (moveMinX) SnapAxisAnchor.start,
      if (moveMaxX) SnapAxisAnchor.end,
    ];
  }

  List<SnapAxisAnchor> _resolveAnchorsY(ResizeMode mode) {
    final moveMinY =
        mode == ResizeMode.top ||
        mode == ResizeMode.topLeft ||
        mode == ResizeMode.topRight;
    final moveMaxY =
        mode == ResizeMode.bottom ||
        mode == ResizeMode.bottomLeft ||
        mode == ResizeMode.bottomRight;
    return [
      if (moveMinY) SnapAxisAnchor.start,
      if (moveMaxY) SnapAxisAnchor.end,
    ];
  }

  bool _isIdentityTransform(
    double scaleX,
    double scaleY,
    DrawRect startBounds,
    DrawRect newBounds,
  ) => scaleX == 1.0 && scaleY == 1.0 && newBounds == startBounds;

  bool _shouldLockSerialNumberAspectRatio({
    required DrawState state,
    required Set<String> selectedIds,
  }) {
    if (selectedIds.isEmpty) {
      return false;
    }
    final elementsById = state.domain.document.elementMap;
    for (final id in selectedIds) {
      final element = elementsById[id];
      if (element == null || element.data is! SerialNumberData) {
        return false;
      }
    }
    return true;
  }
}
