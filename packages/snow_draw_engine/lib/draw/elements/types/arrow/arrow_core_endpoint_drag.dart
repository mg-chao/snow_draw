import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/draw_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import 'arrow_binding.dart';
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

/// Runs endpoint drag preview through `snow_draw_arrow_core`.
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

/// Runs endpoint drag finalization through `snow_draw_arrow_core`.
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
  assert(bindingDistance >= 0);
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
  final dragContext = shouldLookupBindings
      ? coreEngineContext
      : _coreContextWithBindingDisabled(coreEngineContext);
  final session = ArrowCoreSession.fromDocument(
    state.domain.document,
    orderedElementIds: orderedElementIds,
    context: coreEngineContext,
  );
  final mergedOptions = <String, dynamic>{...?options};
  final computed = data.arrowType == ArrowType.elbow
      ? _runEndpointDragViaEngineResult(
          arrow: arrow,
          bindables: bindables,
          dragContext: dragContext,
          draggedIndex: draggedIndex,
          worldPointer: worldPointer,
          orderedElementIds: orderedElementIds,
          mergedOptions: mergedOptions,
          finalize: finalize,
          session: session,
        )
      : _runEndpointDragViaStrategy(
          arrow: arrow,
          bindables: bindables,
          dragContext: dragContext,
          draggedIndex: draggedIndex,
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

_ComputedEndpointDrag? _runEndpointDragViaEngineResult({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext dragContext,
  required int draggedIndex,
  required DrawPoint worldPointer,
  required List<String>? orderedElementIds,
  required Map<String, dynamic> mergedOptions,
  required bool finalize,
  required ArrowCoreSession session,
}) {
  final dragPoint = <double>[
    worldPointer.x - arrow.x,
    worldPointer.y - arrow.y,
  ];
  final engineResult = finalize
      ? finalizeCoreEndpointDrag(
          arrow: arrow,
          draggedPoints: <int, core.Point>{draggedIndex: dragPoint},
          pointer: toCorePoint(worldPointer),
          bindables: bindables,
          context: dragContext,
          options: mergedOptions,
        )
      : computeCoreEndpointDrag(
          arrow: arrow,
          draggedPoints: <int, core.Point>{draggedIndex: dragPoint},
          pointer: toCorePoint(worldPointer),
          bindables: bindables,
          context: dragContext,
          options: mergedOptions,
        );

  final applied = session.applyEngineResultWithOrderFallback(
    arrow: arrow,
    result: engineResult,
    point: toCorePoint(worldPointer),
    orderedElementIds: orderedElementIds,
  );

  return (
    arrow: applied.arrow,
    orderedElementIds: applied.orderedElementIds,
    suggestedBindableId: engineResult.suggestedBinding?.bindableId,
  );
}

_ComputedEndpointDrag? _runEndpointDragViaStrategy({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext dragContext,
  required int draggedIndex,
  required DrawPoint worldPointer,
  required List<String>? orderedElementIds,
  required Map<String, dynamic> mergedOptions,
  required bool finalize,
  required ArrowCoreSession session,
}) {
  if (arrow.points.isEmpty) {
    return null;
  }

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

  final endpointIndex = arrow.points.length - 1;
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

  var nextArrow = arrow.copyWith(
    points: _applyDraggedPointsToArrowPoints(arrow.points, draggedPoints),
  );
  final bindablesById = <String, core.BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };

  nextArrow = _applyStrategyMutation(
    arrow: nextArrow,
    edge: core.arrowEndpointStart,
    strategy: startStrategy,
  );
  nextArrow = _applyStrategyMutation(
    arrow: nextArrow,
    edge: core.arrowEndpointEnd,
    strategy: endStrategy,
  );

  nextArrow = _applyStrategyBoundPoint(
    arrow: nextArrow,
    endpoint: core.arrowEndpointStart,
    strategy: startStrategy,
    bindablesById: bindablesById,
  );
  nextArrow = _applyStrategyBoundPoint(
    arrow: nextArrow,
    endpoint: core.arrowEndpointEnd,
    strategy: endStrategy,
    bindablesById: bindablesById,
  );

  nextArrow = _normalizeArrowState(nextArrow, dragContext.maxCoordinate);

  final suggestedBindableId =
      _strategyBindableId(draggedIndex == 0 ? startStrategy : endStrategy) ??
      _strategyBindableId(startStrategy) ??
      _strategyBindableId(endStrategy);

  List<String>? nextOrderedElementIds;
  if (dragContext.isBindingEnabled &&
      suggestedBindableId != null &&
      suggestedBindableId.isNotEmpty) {
    nextOrderedElementIds = session.reorderArrowAboveHoveredBindable(
      arrowId: arrow.id,
      hoveredBindableId: suggestedBindableId,
      point: toCorePoint(worldPointer),
      orderedElementIds: orderedElementIds,
    );
  }

  return (
    arrow: nextArrow,
    orderedElementIds: nextOrderedElementIds,
    suggestedBindableId: suggestedBindableId,
  );
}

core.EndpointBindingStrategy? _withStrategyFocusPoint(
  core.EndpointBindingStrategy? strategy,
  core.Point focusPoint,
) {
  if (strategy == null ||
      strategy.mode == null ||
      strategy.element == null ||
      strategy.focusPoint == null) {
    return strategy;
  }

  return core.EndpointBindingStrategy(
    mode: strategy.mode,
    bindableId: strategy.bindableId,
    element: strategy.element,
    focusPoint: focusPoint,
  );
}

List<core.Point> _applyDraggedPointsToArrowPoints(
  List<core.Point> points,
  Map<int, core.Point> draggedPoints,
) {
  final nextPoints = points
      .map((point) => <double>[point[0], point[1]])
      .toList(growable: true);
  draggedPoints.forEach((index, point) {
    if (index < 0 || index >= nextPoints.length) {
      return;
    }
    nextPoints[index] = <double>[point[0], point[1]];
  });
  return List<core.Point>.unmodifiable(nextPoints);
}

core.ArrowState _applyStrategyMutation({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
  required core.EndpointBindingStrategy? strategy,
}) {
  if (strategy == null) {
    return arrow;
  }

  if (strategy.mode == null) {
    final mutation = unbindCoreArrowEndpoint(arrow: arrow, edge: edge);
    return core.applyArrowPatch(arrow, mutation.arrowPatch);
  }

  final bindable = strategy.element;
  final focusPoint = strategy.focusPoint;
  if (bindable == null || focusPoint == null) {
    return arrow;
  }

  final mutation = bindCoreArrowEndpoint(
    arrow: arrow,
    edge: edge,
    bindable: bindable,
    mode: strategy.mode,
    focusPoint: focusPoint,
  );
  return core.applyArrowPatch(arrow, mutation.arrowPatch);
}

core.ArrowState _applyStrategyBoundPoint({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge endpoint,
  required core.EndpointBindingStrategy? strategy,
  required Map<String, core.BindableState> bindablesById,
}) {
  if (strategy == null || strategy.focusPoint == null) {
    return arrow;
  }

  final isStart = endpoint == core.arrowEndpointStart;
  final binding = isStart ? arrow.startBinding : arrow.endBinding;
  if (binding == null) {
    return arrow;
  }

  final bindable = bindablesById[binding.elementId];
  if (bindable == null) {
    return arrow;
  }

  final localPoint = updateCoreBoundPoint(
    arrow: arrow,
    edge: isStart
        ? core.arrowEndpointPositionStart
        : core.arrowEndpointPositionEnd,
    binding: binding,
    bindable: bindable,
    bindablesById: bindablesById,
  );
  if (localPoint == null) {
    return arrow;
  }

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

String? _strategyBindableId(core.EndpointBindingStrategy? strategy) {
  if (strategy == null || strategy.mode == null) {
    return null;
  }
  final bindableId = strategy.bindableId;
  if (bindableId != null && bindableId.isNotEmpty) {
    return bindableId;
  }
  return strategy.element?.id;
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

core.EngineContext _coreContextWithBindingDisabled(
  core.EngineContext context,
) => buildCoreEngineContext(
  zoom: context.zoom,
  isBindingEnabled: false,
  bindMode: context.bindMode,
  maxCoordinate: context.maxCoordinate,
);
