import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

/// Typed wrapper around `snow_draw_arrow_core` endpoint-drag computation.
core.EngineResult computeCoreEndpointDrag({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => core.computeEndpointDrag(<String, dynamic>{
  'arrow': arrow,
  'draggedPoints': draggedPoints,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

/// Typed wrapper around endpoint-drag finalization.
core.EngineResult finalizeCoreEndpointDrag({
  required core.ArrowState arrow,
  required Map<int, core.Point> draggedPoints,
  required core.Point pointer,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  Map<String, dynamic>? options,
}) => core.finalizeEndpointDrag(<String, dynamic>{
  'arrow': arrow,
  'draggedPoints': draggedPoints,
  'pointer': pointer,
  'bindables': bindables,
  'context': context,
  ...?(options == null ? null : <String, dynamic>{'options': options}),
});

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
}) => core.recomputeElbowPatch(<String, dynamic>{
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
