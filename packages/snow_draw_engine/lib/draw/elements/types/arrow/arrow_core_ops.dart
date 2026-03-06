import 'package:meta/meta.dart';

import '../../../types/draw_point.dart';
import 'arrow_core.dart' as core;

const _unsetEndpointBindingOption = Object();

/// Typed options forwarded into the migrated arrow-core endpoint helpers.
///
/// This keeps current engine call sites Dart-first while the core adapter still
/// translates to the string-keyed payloads expected by the migrated logic.
@immutable
final class ArrowCoreEndpointBindingOptions {
  const ArrowCoreEndpointBindingOptions({
    this.complexBindings,
    this.newArrow = false,
    this.initialBinding = false,
    this.finalize = false,
    this.preserveOppositeInsideBinding = false,
    this.oppositeOrbitFocusPoint,
    this.angleLocked = false,
    this.altKey = false,
  });

  final bool? complexBindings;
  final bool newArrow;
  final bool initialBinding;
  final bool finalize;
  final bool preserveOppositeInsideBinding;
  final DrawPoint? oppositeOrbitFocusPoint;
  final bool angleLocked;
  final bool altKey;

  bool get isEmpty =>
      complexBindings == null &&
      !newArrow &&
      !initialBinding &&
      !finalize &&
      !preserveOppositeInsideBinding &&
      oppositeOrbitFocusPoint == null &&
      !angleLocked &&
      !altKey;

  ArrowCoreEndpointBindingOptions copyWith({
    Object? complexBindings = _unsetEndpointBindingOption,
    bool? newArrow,
    bool? initialBinding,
    bool? finalize,
    bool? preserveOppositeInsideBinding,
    Object? oppositeOrbitFocusPoint = _unsetEndpointBindingOption,
    bool? angleLocked,
    bool? altKey,
  }) => ArrowCoreEndpointBindingOptions(
    complexBindings: identical(complexBindings, _unsetEndpointBindingOption)
        ? this.complexBindings
        : complexBindings as bool?,
    newArrow: newArrow ?? this.newArrow,
    initialBinding: initialBinding ?? this.initialBinding,
    finalize: finalize ?? this.finalize,
    preserveOppositeInsideBinding:
        preserveOppositeInsideBinding ?? this.preserveOppositeInsideBinding,
    oppositeOrbitFocusPoint:
        identical(oppositeOrbitFocusPoint, _unsetEndpointBindingOption)
        ? this.oppositeOrbitFocusPoint
        : oppositeOrbitFocusPoint as DrawPoint?,
    angleLocked: angleLocked ?? this.angleLocked,
    altKey: altKey ?? this.altKey,
  );

  Map<String, dynamic> toPayload() => <String, dynamic>{
    if (complexBindings != null) 'complexBindings': complexBindings,
    if (newArrow) 'newArrow': true,
    if (initialBinding) 'initialBinding': true,
    if (finalize) 'finalize': true,
    if (preserveOppositeInsideBinding) 'preserveOppositeInsideBinding': true,
    if (oppositeOrbitFocusPoint != null)
      'oppositeOrbitFocusPoint': <double>[
        oppositeOrbitFocusPoint!.x,
        oppositeOrbitFocusPoint!.y,
      ],
    if (angleLocked) 'angleLocked': true,
    if (altKey) 'altKey': true,
  };
}

Map<String, dynamic> _composeEndpointBindingOptionsPayload(
  ArrowCoreEndpointBindingOptions options,
) {
  if (options.isEmpty) {
    return const <String, dynamic>{};
  }
  return <String, dynamic>{'options': options.toPayload()};
}

/// Typed wrapper around integrated arrow core endpoint-drag computation.
core.EngineResult computeCoreEndpointDrag({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  ArrowCoreEndpointBindingOptions options =
      const ArrowCoreEndpointBindingOptions(),
}) => core.computeEndpointDrag(<String, dynamic>{
  'arrow': arrow,
  'draggedPoints': draggedPoints,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  ..._composeEndpointBindingOptionsPayload(options),
});

/// Typed wrapper around endpoint-drag finalization.
core.EngineResult finalizeCoreEndpointDrag({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  ArrowCoreEndpointBindingOptions options =
      const ArrowCoreEndpointBindingOptions(),
}) => core.finalizeEndpointDrag(<String, dynamic>{
  'arrow': arrow,
  'draggedPoints': draggedPoints,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  ..._composeEndpointBindingOptionsPayload(options),
});

/// Typed wrapper around integrated arrow core binding preview computation.
core.EngineResult computeCoreSimpleBindingPatch({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  ArrowCoreEndpointBindingOptions options =
      const ArrowCoreEndpointBindingOptions(),
}) => core.computeSimpleBindingPatch(<String, dynamic>{
  'arrow': arrow,
  'draggedPoints': draggedPoints,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  ..._composeEndpointBindingOptionsPayload(options),
});

/// Typed wrapper around endpoint-binding strategy resolution.
core.EndpointBindingStrategies resolveCoreEndpointBindingStrategy({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  ArrowCoreEndpointBindingOptions options =
      const ArrowCoreEndpointBindingOptions(),
}) => core.getEndpointBindingStrategy(<String, dynamic>{
  'arrow': arrow,
  'draggedPoints': draggedPoints,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  ..._composeEndpointBindingOptionsPayload(options),
});

/// Typed wrapper around core binding-gap calculation.
double resolveCoreBindingGap({
  required core.BindableState bindable,
  required bool elbowed,
}) => core.getBindingGap(bindable, elbowed);

/// Typed wrapper around core max-binding-distance resolution.
double resolveCoreMaxBindingDistance({required double zoom}) =>
    core.maxBindingDistance(zoom);

/// Typed wrapper around fixed-point normalization for non-elbow bindings.
core.Point calculateCoreFixedPointForBinding({
  required core.BindableState bindable,
  required core.Point point,
}) => core.calculateFixedPointForBinding(bindable: bindable, point: point);

/// Typed wrapper around bound-point projection updates.
core.Point? updateCoreBoundPoint({
  required core.ArrowState arrow,
  required core.ArrowEndpointSelector edge,
  required core.FixedPointBinding? binding,
  required core.BindableState bindable,
  required core.BindableLookupInput bindablesById,
  bool dragging = false,
}) => core.updateBoundPoint(
  arrow: arrow,
  edge: edge,
  binding: binding,
  bindable: bindable,
  bindablesById: bindablesById,
  dragging: dragging,
);

/// Typed wrapper around resolving a single global fixed point.
core.Point resolveCoreGlobalFixedPoint({
  required core.FixedPointBinding binding,
  required core.BindableState bindable,
}) => core.getGlobalFixedPoint(binding, bindable);

/// Typed wrapper around bindable-change recomputation.
core.EngineResult recomputeCoreBindingsAfterBindableChange({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  List<String>? changedBindableIds,
  Map<String, dynamic>? options,
}) => core.recomputeAfterBindableChange(<String, dynamic>{
  'arrow': arrow,
  'bindables': bindables,
  'context': context,
  ...?(changedBindableIds == null
      ? null
      : <String, dynamic>{'changedBindableIds': changedBindableIds}),
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

/// Typed wrapper around bulk bindable-change recomputation.
core.RecomputeBindingsForChangedBindablesResult
recomputeCoreBindingsForChangedBindables({
  required List<core.ArrowState> arrows,
  required List<core.BindableState> bindables,
  required List<core.BindableRelationState> relations,
  required List<String> changedBindableIds,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => core.recomputeBindingsForChangedBindables(<String, dynamic>{
  'arrows': arrows,
  'bindables': bindables,
  'relations': relations,
  'changedBindableIds': changedBindableIds,
  'context': context,
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

/// Typed wrapper around elbow recomputation.
core.ArrowPatch recomputeCoreElbowPatch({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
}) => core.recomputeElbow(<String, dynamic>{
  'arrow': arrow,
  'bindables': bindables,
  'context': context,
});

/// Typed wrapper around elbow update/re-normalization.
core.ArrowPatch updateCoreElbowArrowPatch({
  required core.ArrowState arrow,
  required Map<String, dynamic> updates,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => core.updateElbowArrowPatch(<String, dynamic>{
  'arrow': arrow,
  'updates': updates,
  'bindables': bindables,
  'context': context,
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

/// Typed wrapper around fixed-segment drag.
core.MoveFixedSegmentToPointResult moveCoreFixedSegmentToPoint({
  required core.ArrowState arrow,
  required int segmentIndex,
  required core.Point pointer,
}) => core.moveFixedSegmentToPoint(<String, dynamic>{
  'arrow': arrow,
  'segmentIndex': segmentIndex,
  'pointer': pointer,
});

/// Typed wrapper around fixed-segment release.
core.ArrowPatch releaseCoreFixedSegment({
  required core.ArrowState arrow,
  required int segmentIndex,
}) => core.releaseFixedSegment(arrow: arrow, segmentIndex: segmentIndex);

/// Typed wrapper around resize-time elbow binding normalization.
Map<String, dynamic> computeCoreElbowResizePatch({
  required core.FixedPointBinding? startBinding,
  required core.FixedPointBinding? endBinding,
  required List<core.FixedSegment>? fixedSegments,
  required List<core.Point> points,
  required bool flipX,
  required bool flipY,
}) => core.computeElbowResizePatch(<String, dynamic>{
  'arrow': <String, dynamic>{
    'startBinding': startBinding,
    'endBinding': endBinding,
    'fixedSegments': fixedSegments,
  },
  'points': points,
  'flipX': flipX,
  'flipY': flipY,
});

/// Typed wrapper around duplication lifecycle sync.
core.LifecycleSyncResult syncCoreBindingsAfterDuplication({
  required List<core.ArrowState> arrows,
  required List<core.BindableRelationState> bindables,
  required Map<String, String> bindableIdMap,
  required Map<String, String> arrowIdMap,
  required List<core.BindableState> geometryBindables,
  required core.EngineContext context,
}) => core.syncBindingsAfterDuplication(<String, dynamic>{
  'arrows': arrows,
  'bindables': bindables,
  'bindableIdMap': bindableIdMap,
  'arrowIdMap': arrowIdMap,
  'geometryBindables': geometryBindables,
  'context': context,
});

/// Typed wrapper around deletion lifecycle sync.
core.LifecycleSyncResult syncCoreBindingsAfterDeletion({
  required List<core.ArrowState> arrows,
  required List<core.BindableRelationState> bindables,
  required List<core.BindableState> geometryBindables,
  required List<String> deletedArrowIds,
  required List<String> deletedBindableIds,
  required core.EngineContext context,
}) => core.syncBindingsAfterDeletion(<String, dynamic>{
  'arrows': arrows,
  'bindables': bindables,
  'geometryBindables': geometryBindables,
  'deletedArrowIds': deletedArrowIds,
  'deletedBindableIds': deletedBindableIds,
  'context': context,
});

/// Typed wrapper around transformed-bindable pruning lifecycle sync.
core.LifecycleSyncResult syncCoreBindingsAfterBindablePrune({
  required List<core.ArrowState> arrows,
  required List<core.BindableRelationState> bindables,
  required List<core.BindableState> geometryBindables,
  required List<String> retainedBindableIds,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => core.syncBindingsAfterBindablePrune(<String, dynamic>{
  'arrows': arrows,
  'bindables': bindables,
  'geometryBindables': geometryBindables,
  'retainedBindableIds': retainedBindableIds,
  'context': context,
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

/// Typed wrapper around explicit endpoint binding mutation.
core.EndpointBindingMutationResult bindCoreArrowEndpoint({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
  required core.BindableState bindable,
  core.BindMode? mode,
  core.Point? focusPoint,
}) => core.bindArrowEndpoint(
  arrow: arrow,
  edge: edge,
  bindable: bindable,
  mode: mode,
  focusPoint: focusPoint,
);

/// Typed wrapper around explicit endpoint unbinding mutation.
core.EndpointBindingMutationResult unbindCoreArrowEndpoint({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
}) => core.unbindArrowEndpoint(arrow: arrow, edge: edge);

/// Typed wrapper around relation-aware endpoint binding mutation.
core.EndpointBindingMutationWithRelationsResult
bindCoreArrowEndpointWithRelations({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
  required core.BindableState bindable,
  required List<core.BindableRelationState> relations,
  core.BindMode? mode,
  core.Point? focusPoint,
}) => core.bindArrowEndpointWithRelations(
  arrow: arrow,
  edge: edge,
  bindable: bindable,
  relations: relations,
  mode: mode,
  focusPoint: focusPoint,
);

/// Typed wrapper around relation-aware endpoint unbinding mutation.
core.EndpointBindingMutationWithRelationsResult
unbindCoreArrowEndpointWithRelations({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
  required List<core.BindableRelationState> relations,
}) => core.unbindArrowEndpointWithRelations(
  arrow: arrow,
  edge: edge,
  relations: relations,
);

/// Typed wrapper around relation patch derivation from binding transitions.
List<core.BindableRelationPatch>
deriveCoreBindableRelationPatchesForBindingChange({
  required core.DeriveBindableRelationPatchesForBindingChangeInput input,
}) => core.deriveBindableRelationPatchesForBindingChange(input);

/// Typed wrapper around focus-point visibility resolution.
List<core.FocusPointDescriptor> listCoreVisibleFocusPoints({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool ignoreOverlap = false,
}) => core.resolveVisibleFocusPoints(<String, dynamic>{
  'arrow': arrow,
  'bindables': bindables,
  'context': context,
  'options': <String, dynamic>{'ignoreOverlap': ignoreOverlap},
});

/// Typed wrapper around focus-point hit testing.
core.ArrowEndpointEdge? pickCoreFocusPoint({
  required core.ArrowState arrow,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool ignoreOverlap = false,
}) => core.resolveFocusPointHit(<String, dynamic>{
  'arrow': arrow,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  'options': <String, dynamic>{'ignoreOverlap': ignoreOverlap},
});

/// Typed wrapper around focus-point hit testing with pointer offset.
core.FocusPointHit pickCoreFocusPointWithOffset({
  required core.ArrowState arrow,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool ignoreOverlap = false,
}) => core.resolveFocusPointHitWithOffset(<String, dynamic>{
  'arrow': arrow,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  'options': <String, dynamic>{'ignoreOverlap': ignoreOverlap},
});

/// Typed wrapper around focus-point drag.
core.EngineResult computeCoreFocusPointDrag({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge draggedEdge,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool switchToInsideBinding = false,
  double? gridSize,
}) => core.computeFocusDrag(<String, dynamic>{
  'arrow': arrow,
  'draggedEdge': draggedEdge,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  'options': <String, dynamic>{
    'switchToInsideBinding': switchToInsideBinding,
    ...?(gridSize == null ? null : <String, dynamic>{'gridSize': gridSize}),
  },
});

/// Typed wrapper around focus-point drag finalization.
core.EngineResult finalizeCoreFocusPointDrag({
  required String arrowId,
  required core.FixedPointBinding? startBinding,
  required core.FixedPointBinding? endBinding,
  required List<core.BindableRelationState> bindables,
}) => core.finalizeFocusDrag(<String, dynamic>{
  'arrow': <String, dynamic>{
    'id': arrowId,
    'startBinding': startBinding,
    'endBinding': endBinding,
  },
  'bindables': bindables,
});

/// Typed wrapper around engine-result application/reduction.
core.ApplyEngineResultValue applyCoreEngineResult({
  required core.ArrowState arrow,
  required List<core.BindableRelationState> bindables,
  required core.EngineResult result,
  List<String>? orderedElementIds,
  Map<String, List<String>>? anchorElementIdsByBindableId,
}) => core.applyEngineResult(
  core.ApplyEngineResultInput(
    arrow: arrow,
    bindables: bindables,
    result: result,
    orderedElementIds: orderedElementIds,
    anchorElementIdsByBindableId: anchorElementIdsByBindableId,
  ),
);

/// Typed wrapper around hover-target based arrow reordering.
core.ReorderArrowAboveHoveredBindableResult
reorderCoreArrowAboveHoveredBindable({
  required List<String> orderedElementIds,
  required String arrowId,
  String? hoveredBindableId,
  core.Point? point,
  List<core.BindableState>? bindables,
  double? tolerance,
  Map<String, List<String>>? anchorElementIdsByBindableId,
}) => core.reorderArrowAboveHoveredBindable(
  core.ReorderArrowAboveHoveredBindableInput(
    orderedElementIds: orderedElementIds,
    arrowId: arrowId,
    hoveredBindableId: hoveredBindableId,
    point: point,
    bindables: bindables,
    tolerance: tolerance,
    anchorElementIdsByBindableId: anchorElementIdsByBindableId,
  ),
);

/// Returns reordered ids only when hovered-bindable reordering moved arrow.
List<String>? reorderedElementIdsFromCoreHoveredReorder(
  core.ReorderArrowAboveHoveredBindableResult result,
) => result.moved ? List<String>.unmodifiable(result.orderedElementIds) : null;

/// Returns `true` when applying an engine result changed document order.
bool didCoreEngineResultReorder(core.ApplyEngineResultValue value) =>
    value.orderChanged ?? false;

/// Returns reordered ids only when the engine explicitly moved elements.
List<String>? reorderedElementIdsFromCoreResult(
  core.ApplyEngineResultValue value,
) => didCoreEngineResultReorder(value) ? value.orderedElementIds : null;
