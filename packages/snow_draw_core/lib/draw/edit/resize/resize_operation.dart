import '../../config/draw_config.dart';
import '../../core/coordinates/overlay_space.dart';
import '../../core/geometry/resize_geometry.dart';
import '../../elements/types/arrow/arrow_binding_resolver.dart';
import '../../elements/types/serial_number/serial_number_data.dart';
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
import '../../types/resize_mode.dart';
import '../../types/snap_guides.dart';
import '../../utils/handle_calculator.dart';
import '../../utils/snapping_mode.dart';
import '../../utils/transforms/edit_transform_context.dart';
import '../apply/edit_apply.dart';
import '../core/edit_computed_result.dart';
import '../core/edit_modifiers.dart';
import '../core/edit_operation.dart';
import '../core/edit_operation_helpers.dart';
import '../core/edit_operation_params.dart';
import '../core/edit_result.dart';
import '../core/edit_validation.dart';
import '../preview/edit_preview.dart';
import 'bounds/bounds_calculation.dart';
import 'bounds/resize_geometry.dart';

class ResizeOperation extends EditOperation {
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
    final elementSnapshots = buildResizeSnapshots(
      snapshotSelectedElements(state),
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
    final forceSerialNumberAspectRatio = _shouldLockSerialNumberAspectRatio(
      state: state,
      selectedIds: selectedIdsAtStart,
    );
    final maintainAspectRatio =
        modifiers.maintainAspectRatio || forceSerialNumberAspectRatio;

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
    } else if (shouldObjectSnap) {
      // Calculate snap distance in world space (accounting for zoom level)
      final zoom = state.application.view.camera.zoom;
      final effectiveZoom = zoom == 0 ? 1.0 : zoom;
      final snapDistance = snapConfig.distance / effectiveZoom;
      final referenceElements = _resolveReferenceElements(
        state,
        typedContext.selectedIdsAtStart,
      );
      final result = objectSnapService.snapResize(
        targetRect: newBounds,
        referenceElements: referenceElements,
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
  DrawState finish({
    required DrawState state,
    required EditContext context,
    required EditTransform transform,
  }) {
    final typedContext = requireContext<ResizeEditContext>(
      context,
      operationName: 'ResizeOperation.finish',
    );
    final typedTransform = requireTransform<ResizeTransform>(
      transform,
      operationName: 'ResizeOperation.finish',
    );
    if (!typedTransform.isComplete) {
      return state.copyWith(application: state.application.toIdle());
    }
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

    // Update multi-select overlay state after committing a resize.
    final newOverlay = typedContext.isMultiSelect
        ? MultiSelectLifecycle.onResizeFinished(
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
    final typedContext = requireContext<ResizeEditContext>(
      context,
      operationName: 'ResizeOperation.buildPreview',
    );
    final typedTransform = requireTransform<ResizeTransform>(
      transform,
      operationName: 'ResizeOperation.buildPreview',
    );
    if (!typedTransform.isComplete) {
      return EditPreview.none;
    }
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
    required ResizeEditContext context,
    required ResizeTransform transform,
  }) {
    if (!EditValidation.isValidContext(context) ||
        (!EditValidation.isValidBounds(context.startBounds) &&
            !context.isSingleSelect)) {
      return null;
    }
    if (!transform.isComplete) {
      return null;
    }

    final startBounds = context.startBounds;
    final newSelectionBounds = transform.newSelectionBounds!;
    final scaleX = transform.scaleX!;
    final scaleY = transform.scaleY!;
    final anchor = transform.anchor!;

    if (_isIdentityTransform(scaleX, scaleY, startBounds, newSelectionBounds)) {
      return null;
    }

    final updatedById = EditApply.applyResizeToElements(
      snapshots: context.elementSnapshots,
      selectedIds: context.selectedIdsAtStart,
      context: context,
      newSelectionBounds: newSelectionBounds,
      scaleX: scaleX,
      scaleY: scaleY,
      anchor: anchor,
      currentElementsById: state.domain.document.elementMap,
    );
    if (updatedById.isEmpty) {
      return null;
    }

    final elementsById = {...state.domain.document.elementMap, ...updatedById};
    final bindingUpdates = ArrowBindingResolver.resolveBoundArrows(
      elementsById: elementsById,
      changedElementIds: updatedById.keys.toSet(),
      document: state.domain.document,
    );
    if (bindingUpdates.isNotEmpty) {
      updatedById.addAll(bindingUpdates);
    }

    return EditComputedResult(
      updatedElements: updatedById,
      multiSelectBounds: context.isMultiSelect ? newSelectionBounds : null,
    );
  }

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

  List<ElementState> _resolveReferenceElements(
    DrawState state,
    Set<String> selectedIds,
  ) => state.domain.document.elements
      .where(
        (element) => element.opacity > 0 && !selectedIds.contains(element.id),
      )
      .toList();

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
