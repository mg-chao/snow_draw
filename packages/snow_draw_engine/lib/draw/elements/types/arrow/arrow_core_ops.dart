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
    ...?(options == null ? null : <String, dynamic>{'options': options}),
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
    ...?(options == null ? null : <String, dynamic>{'options': options}),
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
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

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
