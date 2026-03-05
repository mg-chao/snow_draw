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
  );
  final dragContext = shouldLookupBindings
      ? coreEngineContext
      : _coreContextWithBindingDisabled(coreEngineContext);
  final dragPoint = <double>[
    worldPointer.x - arrow.x,
    worldPointer.y - arrow.y,
  ];
  final mergedOptions = <String, dynamic>{'complexBindings': true, ...?options};
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
  final session = ArrowCoreSession.fromDocument(
    state.domain.document,
    orderedElementIds: orderedElementIds,
    context: coreEngineContext,
  );
  final applied = session.applyEngineResultWithOrderFallback(
    arrow: arrow,
    result: engineResult,
    point: toCorePoint(worldPointer),
    orderedElementIds: orderedElementIds,
  );
  final nextArrow = applied.arrow;
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
    orderedElementIds: applied.orderedElementIds,
    suggestedBindableId: engineResult.suggestedBinding?.bindableId,
  );
}

List<core.BindableState> _resolveCoreEndpointBindables({
  required DrawState state,
  required String excludedElementId,
  required bool shouldLookupBindings,
  required bool allowNewBinding,
  required ArrowBinding? activeBinding,
  required ArrowBinding? oppositeBinding,
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
