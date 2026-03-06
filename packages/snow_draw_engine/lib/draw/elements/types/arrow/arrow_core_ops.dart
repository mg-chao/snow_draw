import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

/// Singleton runtime boundary for `snow_draw_arrow_core`.
///
/// This keeps engine-facing code decoupled from direct static calls and aligns
/// host integrations around a single arrow-core runtime instance.
final class ArrowCoreRuntime {
  ArrowCoreRuntime._({core.ArrowEngine? engine})
    : _engine = engine ?? core.createArrowEngine();

  static final instance = ArrowCoreRuntime._();

  final core.ArrowEngine _engine;

  core.EngineResult computeEndpointDrag({
    required core.ArrowState arrow,
    required Map<int, core.Point> draggedPoints,
    required core.Point pointer,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    Map<String, dynamic>? options,
  }) => _engine.computeEndpointDrag(<String, dynamic>{
    'arrow': arrow,
    'draggedPoints': draggedPoints,
    'pointer': pointer,
    'bindables': bindables,
    'context': context,
    ..._composeEndpointBindingOptionsPayload(options),
  });

  core.EngineResult finalizeEndpointDrag({
    required core.ArrowState arrow,
    required Map<int, core.Point> draggedPoints,
    required core.Point pointer,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    Map<String, dynamic>? options,
  }) => _engine.finalizeEndpointDrag(<String, dynamic>{
    'arrow': arrow,
    'draggedPoints': draggedPoints,
    'pointer': pointer,
    'bindables': bindables,
    'context': context,
    ..._composeEndpointBindingOptionsPayload(options),
  });

  core.EngineResult recomputeAfterBindableChange({
    required core.ArrowState arrow,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    List<String>? changedBindableIds,
    Map<String, dynamic>? options,
  }) => _engine.recomputeAfterBindableChange(<String, dynamic>{
    'arrow': arrow,
    'bindables': bindables,
    'context': context,
    ...?(changedBindableIds == null
        ? null
        : <String, dynamic>{'changedBindableIds': changedBindableIds}),
    ...?(options == null ? null : <String, dynamic>{'options': options}),
  });

  core.RecomputeBindingsForChangedBindablesResult
  recomputeBindingsForChangedBindables({
    required List<core.ArrowState> arrows,
    required List<core.BindableState> bindables,
    required List<core.BindableRelationState> relations,
    required List<String> changedBindableIds,
    required core.EngineContext context,
    Map<String, dynamic>? options,
  }) => _engine.recomputeBindingsForChangedBindables(<String, dynamic>{
    'arrows': arrows,
    'bindables': bindables,
    'relations': relations,
    'changedBindableIds': changedBindableIds,
    'context': context,
    ...?(options == null ? null : <String, dynamic>{'options': options}),
  });

  core.ArrowPatch recomputeElbow({
    required core.ArrowState arrow,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
  }) => _engine.recomputeElbow(<String, dynamic>{
    'arrow': arrow,
    'bindables': bindables,
    'context': context,
  });

  core.EngineResult computeFocusDrag({
    required core.ArrowState arrow,
    required core.ArrowEndpointEdge draggedEdge,
    required core.Point pointer,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    bool switchToInsideBinding = false,
    double? gridSize,
  }) => _engine.computeFocusDrag(<String, dynamic>{
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

  core.EngineResult finalizeFocusDrag({
    required String arrowId,
    required core.FixedPointBinding? startBinding,
    required core.FixedPointBinding? endBinding,
    required List<core.BindableRelationState> bindables,
  }) => _engine.finalizeFocusDrag(<String, dynamic>{
    'arrow': <String, dynamic>{
      'id': arrowId,
      'startBinding': startBinding,
      'endBinding': endBinding,
    },
    'bindables': bindables,
  });

  List<core.FocusPointDescriptor> resolveVisibleFocusPoints({
    required core.ArrowState arrow,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    bool ignoreOverlap = false,
  }) => _engine.resolveVisibleFocusPoints(<String, dynamic>{
    'arrow': arrow,
    'bindables': bindables,
    'context': context,
    'options': <String, dynamic>{'ignoreOverlap': ignoreOverlap},
  });

  core.ArrowEndpointEdge? resolveFocusPointHit({
    required core.ArrowState arrow,
    required core.Point pointer,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    bool ignoreOverlap = false,
  }) => _engine.resolveFocusPointHit(<String, dynamic>{
    'arrow': arrow,
    'pointer': pointer,
    'bindables': bindables,
    'context': context,
    'options': <String, dynamic>{'ignoreOverlap': ignoreOverlap},
  });

  core.FocusPointHit resolveFocusPointHitWithOffset({
    required core.ArrowState arrow,
    required core.Point pointer,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
    bool ignoreOverlap = false,
  }) => _engine.resolveFocusPointHitWithOffset(<String, dynamic>{
    'arrow': arrow,
    'pointer': pointer,
    'bindables': bindables,
    'context': context,
    'options': <String, dynamic>{'ignoreOverlap': ignoreOverlap},
  });

  core.FixedPointBinding? repairBindingOnRestore({
    required core.FixedPointBinding? binding,
    required List<core.BindableState> bindables,
    core.ArrowState? arrow,
    core.ArrowEndpointEdge? edge,
    List<core.BindableState>? existingBindables,
  }) => _engine.repairBindingOnRestore(<String, dynamic>{
    'binding': binding,
    'bindables': bindables,
    ...?(arrow == null ? null : <String, dynamic>{'arrow': arrow}),
    ...?(edge == null ? null : <String, dynamic>{'edge': edge}),
    ...?(existingBindables == null
        ? null
        : <String, dynamic>{'existingBindables': existingBindables}),
  });

  core.ArrowPatch? repairInvalidUnboundElbowArrowOnRestore({
    required core.ArrowState arrow,
    required List<core.BindableState> bindables,
    required core.EngineContext context,
  }) => _engine.repairInvalidUnboundElbowArrowOnRestore(<String, dynamic>{
    'arrow': arrow,
    'bindables': bindables,
    'context': context,
  });

  core.ArrowPatch? repairSelfBoundExtremeElbowArrowOnRestore({
    required core.ArrowState arrow,
    required core.BindableState bindable,
    double? maxCoordinate,
  }) => _engine.repairSelfBoundExtremeElbowArrowOnRestore(<String, dynamic>{
    'arrow': arrow,
    'bindable': bindable,
    ...?(maxCoordinate == null
        ? null
        : <String, dynamic>{'maxCoordinate': maxCoordinate}),
  });

  core.ValidationReport validateArrowInvariant(core.ArrowState arrow) =>
      _engine.validateArrowInvariant(arrow);
}

ArrowCoreRuntime get _runtime => ArrowCoreRuntime.instance;

Map<String, dynamic> _composeEndpointBindingOptionsPayload(
  Map<String, dynamic>? options,
) {
  final normalizedOptions = _normalizeEndpointBindingOptions(options);
  return <String, dynamic>{'options': normalizedOptions};
}

Map<String, dynamic> _normalizeEndpointBindingOptions(
  Map<String, dynamic>? options,
) {
  final normalized = <String, dynamic>{...?options};
  normalized.putIfAbsent('complexBindings', () => true);
  return normalized;
}

/// Typed wrapper around `snow_draw_arrow_core` endpoint-drag computation.
core.EngineResult computeCoreEndpointDrag({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => _runtime.computeEndpointDrag(
  arrow: arrow,
  draggedPoints: draggedPoints,
  pointer: pointer,
  bindables: bindables,
  context: context,
  options: options,
);

/// Typed wrapper around endpoint-drag finalization.
core.EngineResult finalizeCoreEndpointDrag({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => _runtime.finalizeEndpointDrag(
  arrow: arrow,
  draggedPoints: draggedPoints,
  pointer: pointer,
  bindables: bindables,
  context: context,
  options: options,
);

/// Typed wrapper around `snow_draw_arrow_core` binding preview computation.
core.EngineResult computeCoreSimpleBindingPatch({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  Map<String, dynamic>? options,
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
  Map<String, dynamic>? options,
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

/// Typed wrapper around snap-outline midpoint projection.
core.Point? resolveCoreSnapOutlineMidPoint({
  required core.Point point,
  required core.BindableState bindable,
  double zoom = 1,
}) => core.getSnapOutlineMidPoint(point, bindable, zoom);

/// Typed wrapper around diagonal fixed-point projection.
core.Point? projectCoreFixedPointOntoDiagonal({
  required core.ArrowState arrow,
  required core.Point point,
  required core.BindableState bindable,
  required core.ArrowEndpointEdge edge,
  required List<core.BindableState> bindables,
  required double zoom,
}) => core.projectFixedPointOntoDiagonal(
  arrow,
  point,
  bindable,
  edge,
  bindables,
  zoom,
);

/// Typed wrapper around fixed-point normalization for non-elbow bindings.
core.Point calculateCoreFixedPointForBinding({
  required core.BindableState bindable,
  required core.Point point,
}) => core.calculateFixedPointForBinding(bindable: bindable, point: point);

/// Typed wrapper around fixed-point normalization for elbow bindings.
core.Point calculateCoreFixedPointForElbowBinding({
  required core.ArrowState arrow,
  required core.BindableState bindable,
  required core.ArrowEndpointEdge edge,
}) => core.calculateFixedPointForElbowArrowBinding(
  arrow: arrow,
  bindable: bindable,
  edge: edge,
);

/// Typed wrapper around outline snapping for elbow endpoints.
core.Point bindCorePointToSnapOutline({
  required core.ArrowState arrow,
  required core.BindableState bindable,
  required core.ArrowEndpointEdge edge,
  List<core.Point>? customIntersector,
}) => core.bindPointToSnapToElementOutline(
  arrow: arrow,
  bindable: bindable,
  edge: edge,
  customIntersector: customIntersector,
);

/// Typed wrapper around elbow heading resolution.
String resolveCoreHeadingForElbowSnap({
  required core.Point point,
  required core.Point otherPoint,
  core.BindableState? bindable,
  core.Bounds? aabb,
  core.Point? originPoint,
  double? zoom,
}) => core.getHeadingForElbowArrowSnap(
  point: point,
  otherPoint: otherPoint,
  bindable: bindable,
  aabb: aabb,
  originPoint: originPoint,
  zoom: zoom,
);

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

/// Typed wrapper around resolving global fixed points for an arrow.
List<core.Point?> resolveCoreGlobalFixedPoints({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
}) => core.getGlobalFixedPoints(arrow, bindables);

/// Typed wrapper around resolving local fixed points for an arrow.
List<core.Point?> resolveCoreArrowLocalFixedPoints({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
}) => core.getArrowLocalFixedPoints(arrow, bindables);

/// Typed wrapper around bindable-change recomputation.
core.EngineResult recomputeCoreBindingsAfterBindableChange({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  List<String>? changedBindableIds,
  Map<String, dynamic>? options,
}) => _runtime.recomputeAfterBindableChange(
  arrow: arrow,
  bindables: bindables,
  context: context,
  changedBindableIds: changedBindableIds,
  options: options,
);

/// Typed wrapper around bulk bindable-change recomputation.
core.RecomputeBindingsForChangedBindablesResult
recomputeCoreBindingsForChangedBindables({
  required List<core.ArrowState> arrows,
  required List<core.BindableState> bindables,
  required List<core.BindableRelationState> relations,
  required List<String> changedBindableIds,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => _runtime.recomputeBindingsForChangedBindables(
  arrows: arrows,
  bindables: bindables,
  relations: relations,
  changedBindableIds: changedBindableIds,
  context: context,
  options: options,
);

/// Typed wrapper around elbow recomputation.
core.ArrowPatch recomputeCoreElbowPatch({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
}) => _runtime.recomputeElbow(
  arrow: arrow,
  bindables: bindables,
  context: context,
);

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

/// Typed wrapper around relation patch reconciliation for an arrow snapshot.
List<core.BindablePatch> reconcileCoreBindablePatchesForArrow({
  required core.ArrowBindingState arrow,
  required List<core.BindableRelationState> bindables,
}) => core.reconcileBindablePatchesForArrow(arrow: arrow, bindables: bindables);

/// Typed wrapper around relation patch resolution for endpoint mutations.
core.ResolvedBindableRelationPatches resolveCoreEndpointBindingMutation({
  required core.ArrowBindingState arrow,
  required List<core.BindableRelationState> bindables,
  required core.EndpointBindingMutationResult mutation,
}) => core.resolveEndpointBindingMutation(
  arrow: arrow,
  bindables: bindables,
  mutation: mutation,
);

/// Typed wrapper around focus-point visibility resolution.
List<core.FocusPointDescriptor> listCoreVisibleFocusPoints({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool ignoreOverlap = false,
}) => _runtime.resolveVisibleFocusPoints(
  arrow: arrow,
  bindables: bindables,
  context: context,
  ignoreOverlap: ignoreOverlap,
);

/// Typed wrapper around focus-point hit testing.
core.ArrowEndpointEdge? pickCoreFocusPoint({
  required core.ArrowState arrow,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool ignoreOverlap = false,
}) => _runtime.resolveFocusPointHit(
  arrow: arrow,
  pointer: pointer,
  bindables: bindables,
  context: context,
  ignoreOverlap: ignoreOverlap,
);

/// Typed wrapper around focus-point hit testing with pointer offset.
core.FocusPointHit pickCoreFocusPointWithOffset({
  required core.ArrowState arrow,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool ignoreOverlap = false,
}) => _runtime.resolveFocusPointHitWithOffset(
  arrow: arrow,
  pointer: pointer,
  bindables: bindables,
  context: context,
  ignoreOverlap: ignoreOverlap,
);

/// Typed wrapper around focus-point drag.
core.EngineResult computeCoreFocusPointDrag({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge draggedEdge,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  bool switchToInsideBinding = false,
  double? gridSize,
}) => _runtime.computeFocusDrag(
  arrow: arrow,
  draggedEdge: draggedEdge,
  pointer: pointer,
  bindables: bindables,
  context: context,
  switchToInsideBinding: switchToInsideBinding,
  gridSize: gridSize,
);

/// Typed wrapper around focus-point drag finalization.
core.EngineResult finalizeCoreFocusPointDrag({
  required String arrowId,
  required core.FixedPointBinding? startBinding,
  required core.FixedPointBinding? endBinding,
  required List<core.BindableRelationState> bindables,
}) => _runtime.finalizeFocusDrag(
  arrowId: arrowId,
  startBinding: startBinding,
  endBinding: endBinding,
  bindables: bindables,
);

/// Typed wrapper around endpoint binding refresh.
core.EngineResult refreshCoreEndpointBinding({
  required core.ArrowState arrow,
  required core.ArrowEndpointEdge edge,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
}) => core.refreshEndpointBinding(<String, dynamic>{
  'arrow': arrow,
  'edge': edge,
  'bindables': bindables,
  'context': context,
});

/// Typed wrapper around endpoint-binding pruning.
core.EngineResult pruneCoreArrowBindings({
  required core.ArrowState arrow,
  required List<String> retainedBindableIds,
  Map<String, dynamic>? options,
}) => core.pruneArrowBindings(<String, dynamic>{
  'arrow': arrow,
  'retainedBindableIds': retainedBindableIds,
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

/// Typed wrapper around relation patch resolution from binding transitions.
core.ResolvedBindableRelationPatches resolveCoreBindableRelationPatches({
  required core.ArrowBindingState arrow,
  required List<core.BindableRelationState> bindables,
  core.ArrowPatch? arrowPatch,
  List<core.BindablePatch>? bindablePatches,
}) => core.resolveBindableRelationPatches(
  core.ResolveBindableRelationPatchesInput(
    arrow: arrow,
    bindables: bindables,
    arrowPatch: arrowPatch,
    bindablePatches: bindablePatches,
  ),
);

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

/// Typed wrapper around restore-time binding repair.
core.FixedPointBinding? repairCoreBindingOnRestore({
  required core.FixedPointBinding? binding,
  required List<core.BindableState> bindables,
  core.ArrowState? arrow,
  core.ArrowEndpointEdge? edge,
  List<core.BindableState>? existingBindables,
}) => _runtime.repairBindingOnRestore(
  binding: binding,
  bindables: bindables,
  arrow: arrow,
  edge: edge,
  existingBindables: existingBindables,
);

/// Typed wrapper around invalid unbound elbow restore repair.
core.ArrowPatch? repairCoreInvalidUnboundElbowArrowOnRestore({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
}) => _runtime.repairInvalidUnboundElbowArrowOnRestore(
  arrow: arrow,
  bindables: bindables,
  context: context,
);

/// Typed wrapper around extreme self-bound elbow restore repair.
core.ArrowPatch? repairCoreSelfBoundExtremeElbowArrowOnRestore({
  required core.ArrowState arrow,
  required core.BindableState bindable,
  double? maxCoordinate,
}) => _runtime.repairSelfBoundExtremeElbowArrowOnRestore(
  arrow: arrow,
  bindable: bindable,
  maxCoordinate: maxCoordinate,
);

/// Typed wrapper around arrow invariant validation.
core.ValidationReport validateCoreArrowInvariant(core.ArrowState arrow) =>
    _runtime.validateArrowInvariant(arrow);

/// Typed wrapper around directional link-arrow creation.
core.DirectionalLinkArrow createCoreDirectionalLinkArrow({
  required core.DirectionalLinkBounds start,
  required core.DirectionalLinkBounds end,
  required core.DirectionalLinkDirection direction,
  double padding = 6,
}) => core.createDirectionalLinkArrow(start, end, direction, padding: padding);

/// Typed wrapper around endpoint overlap offsetting for short arrows.
List<core.Point> offsetCoreArrowEndpointsForBindingOverlap({
  required List<core.Point> points,
  double delta = 0.5,
}) => core.offsetArrowEndpointsForBindingOverlap(points, delta: delta);

/// Typed wrapper around resize-handle directional resolution.
core.ResizeArrowDirection getCoreResizeArrowDirection({
  required core.ResizeHandleDirection transformHandleType,
  required List<core.Point> points,
}) => core.getResizeArrowDirection(transformHandleType, points);
