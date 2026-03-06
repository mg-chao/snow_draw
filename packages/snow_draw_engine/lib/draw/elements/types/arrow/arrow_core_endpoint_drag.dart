import 'package:meta/meta.dart';

import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_binding.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bindable_query.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_core_session.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_fixed_segment.dart';

/// Result of applying a core endpoint drag/finalize computation.
@immutable
final class ArrowCoreEndpointDragResult {
  /// Creates an immutable endpoint drag result projected to engine types.
  const ArrowCoreEndpointDragResult({
    required this.arrow,
    required this.worldPoints,
    required this.localPoints,
    required this.startBinding,
    required this.endBinding,
    required this.fixedSegments,
    required this.orderedElementIds,
    required this.suggestedBindableId,
  });

  /// Updated core arrow after applying the endpoint drag engine result.
  final core.ArrowState arrow;

  /// Updated arrow points in world coordinates.
  final List<DrawPoint> worldPoints;

  /// Updated arrow points in element-local coordinates.
  final List<DrawPoint> localPoints;

  /// Updated start endpoint binding.
  final ArrowBinding? startBinding;

  /// Updated end endpoint binding.
  final ArrowBinding? endBinding;

  /// Updated elbow fixed segments in element-local coordinates.
  final List<ElbowFixedSegment>? fixedSegments;

  /// Updated element ordering when core emitted reorder events.
  final List<String>? orderedElementIds;

  /// Suggested bindable id reported by arrow-core, if any.
  final String? suggestedBindableId;
}

/// Runs endpoint drag preview through the integrated arrow core module.
ArrowCoreEndpointDragResult? computeArrowCoreEndpointDragResult({
  required DrawState state,
  required ElementState element,
  required ArrowLikeData data,
  required List<DrawPoint> localPoints,
  required int draggedIndex,
  required DrawPoint worldPointer,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required String excludedElementId,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required double bindingDistance,
  required core.EngineContext coreEngineContext,
  List<ElbowFixedSegment>? fixedSegments,
  List<String>? orderedElementIds,
  Map<String, dynamic>? options,
}) => _runArrowCoreEndpointDragResult(
  state: state,
  element: element,
  data: data,
  localPoints: localPoints,
  draggedIndex: draggedIndex,
  worldPointer: worldPointer,
  startBinding: startBinding,
  endBinding: endBinding,
  excludedElementId: excludedElementId,
  shouldLookupBindings: shouldLookupBindings,
  allowNewBinding: allowNewBinding,
  bindingDistance: bindingDistance,
  coreEngineContext: coreEngineContext,
  fixedSegments: fixedSegments,
  orderedElementIds: orderedElementIds,
  options: options,
  finalize: false,
);

/// Runs endpoint drag finalization through the integrated arrow core module.
ArrowCoreEndpointDragResult? finalizeArrowCoreEndpointDragResult({
  required DrawState state,
  required ElementState element,
  required ArrowLikeData data,
  required List<DrawPoint> localPoints,
  required int draggedIndex,
  required DrawPoint worldPointer,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required String excludedElementId,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required double bindingDistance,
  required core.EngineContext coreEngineContext,
  List<ElbowFixedSegment>? fixedSegments,
  List<String>? orderedElementIds,
  Map<String, dynamic>? options,
}) => _runArrowCoreEndpointDragResult(
  state: state,
  element: element,
  data: data,
  localPoints: localPoints,
  draggedIndex: draggedIndex,
  worldPointer: worldPointer,
  startBinding: startBinding,
  endBinding: endBinding,
  excludedElementId: excludedElementId,
  shouldLookupBindings: shouldLookupBindings,
  allowNewBinding: allowNewBinding,
  bindingDistance: bindingDistance,
  coreEngineContext: coreEngineContext,
  fixedSegments: fixedSegments,
  orderedElementIds: orderedElementIds,
  options: options,
  finalize: true,
);

ArrowCoreEndpointDragResult? _runArrowCoreEndpointDragResult({
  required DrawState state,
  required ElementState element,
  required ArrowLikeData data,
  required List<DrawPoint> localPoints,
  required int draggedIndex,
  required DrawPoint worldPointer,
  required ArrowBinding? startBinding,
  required ArrowBinding? endBinding,
  required String excludedElementId,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required double bindingDistance,
  required core.EngineContext coreEngineContext,
  required bool finalize,
  List<ElbowFixedSegment>? fixedSegments,
  List<String>? orderedElementIds,
  Map<String, dynamic>? options,
}) {
  assert(bindingDistance >= 0, 'bindingDistance must be non-negative');
  if (localPoints.length < 2 ||
      draggedIndex < 0 ||
      draggedIndex >= localPoints.length) {
    return null;
  }

  final fixedSegmentsForCore = data.arrowType == ArrowType.elbow
      ? (fixedSegments ?? const <ElbowFixedSegment>[])
      : null;
  final arrow = toCoreArrowState(
    element: element,
    data: data,
    localPointsOverride: localPoints,
    fixedSegmentsOverride: fixedSegmentsForCore,
    startBindingOverride: startBinding,
    endBindingOverride: endBinding,
    maxCoordinate: coreEngineContext.maxCoordinate,
  );
  final activeBinding = draggedIndex == 0 ? startBinding : endBinding;
  final oppositeBinding = draggedIndex == 0 ? endBinding : startBinding;
  final bindables = _resolveCoreEndpointBindables(
    state: state,
    excludedElementId: excludedElementId,
    shouldLookupBindings: shouldLookupBindings,
    allowNewBinding: allowNewBinding,
    activeBinding: activeBinding,
    oppositeBinding: oppositeBinding,
    orderedElementIds: orderedElementIds,
  );
  final dragContext = shouldLookupBindings && allowNewBinding
      ? coreEngineContext
      : buildCoreEngineContext(
          zoom: coreEngineContext.zoom,
          isBindingEnabled: false,
          bindMode: coreEngineContext.bindMode,
          maxCoordinate: coreEngineContext.maxCoordinate,
        );
  final session = ArrowCoreSession.fromDocument(
    state.domain.document,
    orderedElementIds: orderedElementIds,
    context: dragContext,
  );
  final mergedOptions = <String, dynamic>{...?options};
  final computed = _runEndpointDragViaStrategy(
    arrow: arrow,
    bindables: bindables,
    dragContext: dragContext,
    draggedIndex: draggedIndex,
    allowNewBinding: allowNewBinding,
    worldPointer: worldPointer,
    orderedElementIds: orderedElementIds,
    mergedOptions: mergedOptions,
    finalize: finalize,
    session: session,
  );
  if (computed == null) {
    return null;
  }
  final nextArrow = computed.arrow;
  final worldPoints = coreArrowWorldPoints(nextArrow);
  if (worldPoints.length < 2) {
    return null;
  }

  return ArrowCoreEndpointDragResult(
    arrow: nextArrow,
    worldPoints: List<DrawPoint>.unmodifiable(worldPoints),
    localPoints: List<DrawPoint>.unmodifiable(
      worldToLocalPoints(element, worldPoints),
    ),
    startBinding: fromCoreBinding(nextArrow.startBinding),
    endBinding: fromCoreBinding(nextArrow.endBinding),
    fixedSegments: data.arrowType == ArrowType.elbow
        ? toLocalFixedSegmentsFromCoreArrow(nextArrow, element)
        : fixedSegments,
    orderedElementIds: computed.orderedElementIds,
    suggestedBindableId: computed.suggestedBindableId,
  );
}

typedef _ComputedEndpointDrag = ({
  core.ArrowState arrow,
  List<String>? orderedElementIds,
  String? suggestedBindableId,
});

_ComputedEndpointDrag? _runEndpointDragViaStrategy({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext dragContext,
  required int draggedIndex,
  required bool allowNewBinding,
  required DrawPoint worldPointer,
  required List<String>? orderedElementIds,
  required Map<String, dynamic> mergedOptions,
  required bool finalize,
  required ArrowCoreSession session,
}) {
  if (arrow.points.isEmpty) {
    return null;
  }

  final endpointIndex = arrow.points.length - 1;
  final bindablesById = <String, core.BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };
  final draggedPoints = <int, core.Point>{
    draggedIndex: <double>[worldPointer.x - arrow.x, worldPointer.y - arrow.y],
  };
  if (finalize) {
    mergedOptions['finalize'] = true;
  }

  final strategies = resolveCoreEndpointBindingStrategy(
    arrow: arrow,
    draggedPoints: draggedPoints,
    pointer: toCorePoint(worldPointer),
    bindables: bindables,
    context: dragContext,
    options: mergedOptions,
  );
  var startStrategy = strategies.start;
  var endStrategy = strategies.end;

  final isNewArrow = mergedOptions['newArrow'] == true;
  if (isNewArrow &&
      draggedPoints.length == 1 &&
      !arrow.elbowed &&
      draggedIndex >= 0 &&
      draggedIndex <= endpointIndex) {
    final draggedGlobalPoint = toCorePoint(worldPointer);
    if (draggedIndex == 0) {
      startStrategy = _withStrategyFocusPoint(
        startStrategy,
        draggedGlobalPoint,
      );
    } else if (draggedIndex == endpointIndex) {
      endStrategy = _withStrategyFocusPoint(endStrategy, draggedGlobalPoint);
    }
  }

  // Excalidraw parity:
  // endpoint dragging applies strategy-driven binding updates via the
  // simple-binding patch path (strategy + updateBoundPoint), while finalization
  // is still expressed through the shared `options.finalize` flag.
  final result = finalize
      ? finalizeCoreEndpointDrag(
          arrow: arrow,
          draggedPoints: draggedPoints,
          pointer: toCorePoint(worldPointer),
          bindables: bindables,
          context: dragContext,
          options: mergedOptions,
        )
      : computeCoreEndpointDrag(
          arrow: arrow,
          draggedPoints: draggedPoints,
          pointer: toCorePoint(worldPointer),
          bindables: bindables,
          context: dragContext,
          options: mergedOptions,
        );
  final suggestedBindableId = _resolveSuggestedBindableId(result: result);

  final applied = session.applyEngineResultWithOrderFallback(
    arrow: arrow,
    result: result,
    hoveredBindableId: suggestedBindableId,
    point: toCorePoint(worldPointer),
    orderedElementIds: orderedElementIds,
  );
  var nextArrow = applied.arrow;
  if (!allowNewBinding) {
    final endpointIndex = nextArrow.points.length - 1;
    if (draggedIndex == 0) {
      nextArrow = nextArrow.copyWith(
        startBinding: null,
        setStartBinding: true,
        endBinding: arrow.endBinding,
        setEndBinding: true,
      );
    } else if (draggedIndex == endpointIndex) {
      nextArrow = nextArrow.copyWith(
        startBinding: arrow.startBinding,
        setStartBinding: true,
        endBinding: null,
        setEndBinding: true,
      );
    }
  }
  final draggedStrategy = draggedIndex == 0 ? startStrategy : endStrategy;
  nextArrow = _applyLegacyNewArrowDraggedFocusPointOverride(
    arrow: nextArrow,
    draggedIndex: draggedIndex,
    draggedGlobalPoint: toCorePoint(worldPointer),
    draggedStrategy: draggedStrategy,
    bindablesById: bindablesById,
    maxCoordinate: dragContext.maxCoordinate,
    isNewArrow: isNewArrow,
  );
  final nextOrderedElementIds = applied.orderedElementIds;

  return (
    arrow: nextArrow,
    orderedElementIds: nextOrderedElementIds,
    suggestedBindableId: suggestedBindableId,
  );
}

core.ArrowState _applyLegacyNewArrowDraggedFocusPointOverride({
  required core.ArrowState arrow,
  required int draggedIndex,
  required core.Point draggedGlobalPoint,
  required core.EndpointBindingStrategy? draggedStrategy,
  required Map<String, core.BindableState> bindablesById,
  required double maxCoordinate,
  required bool isNewArrow,
}) {
  if (!isNewArrow || arrow.elbowed || arrow.points.isEmpty) {
    return arrow;
  }
  if (draggedIndex != 0 && draggedIndex != arrow.points.length - 1) {
    return arrow;
  }
  if (draggedStrategy == null ||
      draggedStrategy.mode == null ||
      draggedStrategy.element == null) {
    return arrow;
  }

  final isStart = draggedIndex == 0;
  final binding = isStart ? arrow.startBinding : arrow.endBinding;
  if (binding == null) {
    return arrow;
  }

  final bindable = bindablesById[binding.elementId] ?? draggedStrategy.element!;
  final fixedPoint = calculateCoreFixedPointForBinding(
    bindable: bindable,
    point: draggedGlobalPoint,
  );
  final nextBinding = binding.copyWith(fixedPoint: fixedPoint);

  var nextArrow = isStart
      ? arrow.copyWith(startBinding: nextBinding, setStartBinding: true)
      : arrow.copyWith(endBinding: nextBinding, setEndBinding: true);

  final localPoint = updateCoreBoundPoint(
    arrow: nextArrow,
    edge: isStart
        ? core.arrowEndpointPositionStart
        : core.arrowEndpointPositionEnd,
    binding: nextBinding,
    bindable: bindable,
    bindablesById: bindablesById,
    dragging: true,
  );
  if (localPoint != null) {
    nextArrow = _replaceArrowEndpointLocalPoint(
      arrow: nextArrow,
      isStart: isStart,
      localPoint: localPoint,
    );
  }
  return _normalizeArrowState(nextArrow, maxCoordinate);
}

core.ArrowState _replaceArrowEndpointLocalPoint({
  required core.ArrowState arrow,
  required bool isStart,
  required core.Point localPoint,
}) {
  final nextPoints = arrow.points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: true);
  final pointIndex = isStart ? 0 : nextPoints.length - 1;
  if (pointIndex < 0 || pointIndex >= nextPoints.length) {
    return arrow;
  }
  nextPoints[pointIndex] = <double>[localPoint[0], localPoint[1]];
  return arrow.copyWith(points: List<core.Point>.unmodifiable(nextPoints));
}

core.EndpointBindingStrategy? _withStrategyFocusPoint(
  core.EndpointBindingStrategy? strategy,
  core.Point focusPoint,
) {
  if (strategy == null || strategy.mode == null || strategy.element == null) {
    return strategy;
  }

  return core.EndpointBindingStrategy(
    mode: strategy.mode,
    bindableId: strategy.bindableId,
    element: strategy.element,
    focusPoint: focusPoint,
  );
}

core.ArrowState _normalizeArrowState(
  core.ArrowState arrow,
  double maxCoordinate,
) {
  final globalPoints = arrow.points
      .map((point) => <double>[arrow.x + point[0], arrow.y + point[1]])
      .toList(growable: false);
  final normalized = core.normalizeArrowFromGlobalPoints(
    globalPoints,
    maxCoordinate,
  );
  return arrow.copyWith(
    x: normalized.x,
    y: normalized.y,
    width: normalized.width,
    height: normalized.height,
    points: normalized.points,
  );
}

String? _resolveSuggestedBindableId({required core.EngineResult result}) {
  final suggestedBinding = result.suggestedBinding;
  final suggestedBindableId = suggestedBinding?.bindableId;
  if (suggestedBindableId != null && suggestedBindableId.isNotEmpty) {
    return suggestedBindableId;
  }
  final suggestedElementId = suggestedBinding?.element.id;
  if (suggestedElementId != null && suggestedElementId.isNotEmpty) {
    return suggestedElementId;
  }
  return null;
}

List<core.BindableState> _resolveCoreEndpointBindables({
  required DrawState state,
  required String excludedElementId,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required ArrowBinding? activeBinding,
  required ArrowBinding? oppositeBinding,
  required List<String>? orderedElementIds,
}) {
  if (!shouldLookupBindings) {
    return const <core.BindableState>[];
  }

  final resolved = resolveCoreBindableCandidatesForEndpointStrategy(
    document: state.domain.document,
    activeBinding: activeBinding,
    oppositeBinding: oppositeBinding,
    excludedElementId: excludedElementId,
    allowNewBinding: allowNewBinding,
    orderedElementIds: orderedElementIds,
  );
  if (resolved.isEmpty) {
    return const <core.BindableState>[];
  }
  return resolved.bindables;
}
