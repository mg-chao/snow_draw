import 'adapters.dart';
import 'arrow_binding_core.dart' as binding_core;
import 'arrow_elbow_core.dart';
import 'arrow_geom.dart';
import 'arrow_hit_test.dart';
import 'arrow_state_core.dart';
import 'arrow_types.dart';

typedef PartialBindingArrowPatch = Map<String, dynamic>;

class ResolveBindableRelationPatchesInput {
  const ResolveBindableRelationPatchesInput({
    required this.arrow,
    required this.bindables,
    this.arrowPatch,
    this.bindablePatches,
  });

  final ArrowBindingState arrow;
  final List<BindableRelationState> bindables;
  final PartialBindingArrowPatch? arrowPatch;
  final List<BindablePatch>? bindablePatches;
}

class ResolvedBindableRelationPatches {
  const ResolvedBindableRelationPatches({
    required this.bindablePatches,
    required this.relationPatches,
  });

  final List<BindablePatch> bindablePatches;
  final List<BindableRelationPatch> relationPatches;
}

class EndpointBindingMutationResult {
  const EndpointBindingMutationResult({
    required this.arrowPatch,
    required this.bindablePatches,
    this.events = const <ArrowEngineEvent>[],
  });

  final ArrowPatch arrowPatch;
  final List<BindablePatch> bindablePatches;
  final List<ArrowEngineEvent> events;
}

class EndpointBindingMutationWithRelationsResult
    extends EndpointBindingMutationResult {
  const EndpointBindingMutationWithRelationsResult({
    required super.arrowPatch,
    required super.bindablePatches,
    required this.relationPatches,
    super.events = const <ArrowEngineEvent>[],
  });

  final List<BindableRelationPatch> relationPatches;
}

bool _fixedPointEqual(Point left, Point right) =>
    left.length >= 2 &&
    right.length >= 2 &&
    left[0] == right[0] &&
    left[1] == right[1];

bool _bindingEqual(FixedPointBinding? left, FixedPointBinding? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return left.elementId == right.elementId &&
      left.mode == right.mode &&
      _fixedPointEqual(left.fixedPoint, right.fixedPoint);
}

Set<String> _collectBoundBindableIds(ArrowBindingState state) {
  final ids = <String>{};
  final startBinding = state.startBinding;
  if (startBinding != null) {
    ids.add(startBinding.elementId);
  }
  final endBinding = state.endBinding;
  if (endBinding != null) {
    ids.add(endBinding.elementId);
  }
  return ids;
}

ArrowEndpointEdge _normalizeEdge(ArrowEndpointSelector edge) =>
    normalizeArrowEndpointEdge(edge);

Map<String, dynamic>? _asStringDynamicMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    final out = <String, dynamic>{};
    value.forEach((key, entryValue) {
      if (key is String) {
        out[key] = entryValue;
      }
    });
    return out;
  }
  return null;
}

ArrowState? _readArrowState(Object? value) =>
    value is ArrowState ? value : null;

List<ArrowState> _readArrowStates(Object? value) {
  if (value is List<ArrowState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<ArrowState>().toList(growable: false);
  }
  return const <ArrowState>[];
}

List<BindableState> _readBindableStates(Object? value) {
  if (value is List<BindableState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableState>().toList(growable: false);
  }
  return const <BindableState>[];
}

List<BindableRelationState> _readBindableRelationStates(Object? value) {
  if (value is List<BindableRelationState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableRelationState>().toList(growable: false);
  }
  return const <BindableRelationState>[];
}

List<String> _readStringList(Object? value) {
  if (value is List<String>) {
    return value;
  }
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return const <String>[];
}

EngineContext _readEngineContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  return normalizeEngineContext(_asStringDynamicMap(value));
}

ArrowEndpointEdge _readEdge(
  Object? value, {
  ArrowEndpointEdge fallback = arrowEndpointStart,
}) {
  if (value == arrowEndpointStart || value == 'start') {
    return arrowEndpointStart;
  }
  if (value == arrowEndpointEnd || value == 'end') {
    return arrowEndpointEnd;
  }
  if (value == 'startBinding') {
    return arrowEndpointStart;
  }
  if (value == 'endBinding') {
    return arrowEndpointEnd;
  }
  return fallback;
}

Map<String, String> _normalizeIdMap(IdMapInput entries) {
  if (entries is Map<String, String>) {
    return entries;
  }

  if (entries is Map) {
    final mapped = <String, String>{};
    entries.forEach((key, value) {
      if (key is String && value is String) {
        mapped[key] = value;
      }
    });
    return mapped;
  }

  if (entries is List<IdMapEntry>) {
    return <String, String>{for (final entry in entries) entry.from: entry.to};
  }

  if (entries is List) {
    final mapped = <String, String>{};
    for (final entry in entries) {
      if (entry is IdMapEntry) {
        mapped[entry.from] = entry.to;
        continue;
      }
      if (entry is Map) {
        final from = entry['from'];
        final to = entry['to'];
        if (from is String && to is String) {
          mapped[from] = to;
        }
      }
    }
    return mapped;
  }

  return <String, String>{};
}

FixedPointBinding? _remapBinding(
  FixedPointBinding? binding,
  Map<String, String> bindableIdMap,
  bool preserveUnmapped,
) {
  if (binding == null) {
    return null;
  }
  final mappedId = bindableIdMap[binding.elementId];
  if (mappedId == null) {
    return preserveUnmapped ? binding : null;
  }
  return binding.copyWith(elementId: mappedId);
}

ArrowBindingState _applyBindingPatchToState(
  ArrowBindingState arrow,
  PartialBindingArrowPatch? patch,
) {
  if (patch == null) {
    return arrow;
  }

  return ArrowBindingState(
    id: arrow.id,
    startBinding: patch.containsKey('startBinding')
        ? patch['startBinding'] as FixedPointBinding?
        : arrow.startBinding,
    endBinding: patch.containsKey('endBinding')
        ? patch['endBinding'] as FixedPointBinding?
        : arrow.endBinding,
  );
}

ArrowBindingState _toArrowBindingState(ArrowState arrow) => ArrowBindingState(
  id: arrow.id,
  startBinding: arrow.startBinding,
  endBinding: arrow.endBinding,
);

ArrowPatch _patchForEdge({
  required ArrowEndpointEdge edge,
  required FixedPointBinding? next,
  required FixedPointBinding? previous,
}) {
  if (_bindingEqual(next, previous)) {
    return <String, dynamic>{};
  }
  if (_normalizeEdge(edge) == arrowEndpointStart) {
    return <String, dynamic>{'startBinding': next};
  }
  return <String, dynamic>{'endBinding': next};
}

FixedPointBinding _resolveManualBinding({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
  required BindableState bindable,
  required BindMode? mode,
  required Point? focusPoint,
}) {
  final normalizedEdge = _normalizeEdge(edge);
  final edgeIndex = normalizedEdge == arrowEndpointStart
      ? 0
      : arrow.points.length - 1;
  final targetPoint = focusPoint ?? getPointAtIndexGlobal(arrow, edgeIndex);

  if (arrow.elbowed) {
    return FixedPointBinding(
      elementId: bindable.id,
      mode: bindModeOrbit,
      fixedPoint: binding_core.calculateFixedPointForElbowBinding(
        arrow: arrow,
        bindable: bindable,
        edge: normalizedEdge,
      ),
    );
  }

  return FixedPointBinding(
    elementId: bindable.id,
    mode: mode ?? bindModeOrbit,
    fixedPoint: binding_core.calculateFixedPointForBinding(
      point: targetPoint,
      bindable: bindable,
    ),
  );
}

EngineResult _emptyEngineResult() => const EngineResult(
  arrowPatch: <String, dynamic>{},
  bindablePatches: <BindablePatch>[],
  suggestedBinding: null,
  events: <ArrowEngineEvent>[],
);

EngineResult _withEngineEnvelope(EndpointBindingMutationResult mutation) =>
    EngineResult(
      arrowPatch: mutation.arrowPatch,
      bindablePatches: mutation.bindablePatches,
      suggestedBinding: null,
      events: const <ArrowEngineEvent>[],
    );

bool _hasArrowPatchChanges(ArrowPatch patch) => patch.isNotEmpty;

ArrowPatch _toArrowPatchFromBindingPatch(ArrowBindingStatePatch patch) {
  final mapped = <String, dynamic>{};
  if (patch.containsKey('startBinding')) {
    mapped['startBinding'] = patch['startBinding'] as FixedPointBinding?;
  }
  if (patch.containsKey('endBinding')) {
    mapped['endBinding'] = patch['endBinding'] as FixedPointBinding?;
  }
  return mapped;
}

bool _arraysEqual(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

EndpointBindingMutationWithRelationsResult _resolveMutationWithRelations({
  required ArrowState arrow,
  required List<BindableRelationState> relations,
  required EndpointBindingMutationResult mutation,
}) {
  final resolved = resolveEndpointBindingMutation(
    arrow: _toArrowBindingState(arrow),
    bindables: relations,
    mutation: mutation,
  );

  return EndpointBindingMutationWithRelationsResult(
    arrowPatch: mutation.arrowPatch,
    bindablePatches: resolved.bindablePatches,
    relationPatches: resolved.relationPatches,
    events: mutation.events,
  );
}

List<BindablePatch> deriveBindablePatchesForBindingChange({
  required String arrowId,
  required ArrowBindingState previous,
  required ArrowBindingState next,
}) {
  final previousIds = _collectBoundBindableIds(previous);
  final nextIds = _collectBoundBindableIds(next);
  final patches = <BindablePatch>[];

  for (final bindableId in previousIds) {
    if (!nextIds.contains(bindableId)) {
      patches.add(BindablePatch(id: bindableId, removeBoundArrowId: arrowId));
    }
  }

  for (final bindableId in nextIds) {
    if (!previousIds.contains(bindableId)) {
      patches.add(BindablePatch(id: bindableId, addBoundArrowId: arrowId));
    }
  }

  return patches;
}

List<BindableRelationPatch> deriveBindableRelationPatchesForBindingChange(
  DeriveBindableRelationPatchesForBindingChangeInput input,
) {
  final patches = deriveBindablePatchesForBindingChange(
    arrowId: input.arrowId,
    previous: input.previous,
    next: input.next,
  );

  if (patches.isEmpty) {
    return <BindableRelationPatch>[];
  }

  return reduceBindablePatchesToRelationPatches(input.bindables, patches);
}

ResolvedBindableRelationPatches resolveBindableRelationPatches(
  ResolveBindableRelationPatchesInput input,
) {
  final nextArrow = _applyBindingPatchToState(input.arrow, input.arrowPatch);
  final bindablePatches =
      input.bindablePatches != null && input.bindablePatches!.isNotEmpty
      ? List<BindablePatch>.from(input.bindablePatches!)
      : reconcileBindablePatchesForArrow(
          arrow: nextArrow,
          bindables: input.bindables,
        );

  if (bindablePatches.isEmpty) {
    return ResolvedBindableRelationPatches(
      bindablePatches: bindablePatches,
      relationPatches: <BindableRelationPatch>[],
    );
  }

  return ResolvedBindableRelationPatches(
    bindablePatches: bindablePatches,
    relationPatches: reduceBindablePatchesToRelationPatches(
      input.bindables,
      bindablePatches,
    ),
  );
}

ResolvedBindableRelationPatches resolveEndpointBindingMutation({
  required ArrowBindingState arrow,
  required List<BindableRelationState> bindables,
  required EndpointBindingMutationResult mutation,
}) => resolveBindableRelationPatches(
  ResolveBindableRelationPatchesInput(
    arrow: arrow,
    bindables: bindables,
    arrowPatch: mutation.arrowPatch,
    bindablePatches: mutation.bindablePatches,
  ),
);

EndpointBindingMutationResult bindArrowEndpoint({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
  required BindableState bindable,
  BindMode? mode,
  Point? focusPoint,
}) {
  final normalizedEdge = _normalizeEdge(edge);
  final nextBinding = _resolveManualBinding(
    arrow: arrow,
    edge: normalizedEdge,
    bindable: bindable,
    mode: mode,
    focusPoint: focusPoint,
  );

  final previous = ArrowBindingState(
    id: arrow.id,
    startBinding: arrow.startBinding,
    endBinding: arrow.endBinding,
  );
  final next = normalizedEdge == arrowEndpointStart
      ? ArrowBindingState(
          id: arrow.id,
          startBinding: nextBinding,
          endBinding: arrow.endBinding,
        )
      : ArrowBindingState(
          id: arrow.id,
          startBinding: arrow.startBinding,
          endBinding: nextBinding,
        );

  return EndpointBindingMutationResult(
    arrowPatch: _patchForEdge(
      edge: normalizedEdge,
      next: nextBinding,
      previous: normalizedEdge == arrowEndpointStart
          ? arrow.startBinding
          : arrow.endBinding,
    ),
    bindablePatches: deriveBindablePatchesForBindingChange(
      arrowId: arrow.id,
      previous: previous,
      next: next,
    ),
  );
}

EndpointBindingMutationResult unbindArrowEndpoint({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
}) {
  final normalizedEdge = _normalizeEdge(edge);
  final previousBinding = normalizedEdge == arrowEndpointStart
      ? arrow.startBinding
      : arrow.endBinding;

  if (previousBinding == null) {
    return const EndpointBindingMutationResult(
      arrowPatch: <String, dynamic>{},
      bindablePatches: <BindablePatch>[],
    );
  }

  final previous = ArrowBindingState(
    id: arrow.id,
    startBinding: arrow.startBinding,
    endBinding: arrow.endBinding,
  );
  final next = normalizedEdge == arrowEndpointStart
      ? ArrowBindingState(
          id: arrow.id,
          startBinding: null,
          endBinding: arrow.endBinding,
        )
      : ArrowBindingState(
          id: arrow.id,
          startBinding: arrow.startBinding,
          endBinding: null,
        );

  return EndpointBindingMutationResult(
    arrowPatch: _patchForEdge(
      edge: normalizedEdge,
      next: null,
      previous: previousBinding,
    ),
    bindablePatches: deriveBindablePatchesForBindingChange(
      arrowId: arrow.id,
      previous: previous,
      next: next,
    ),
  );
}

EndpointBindingMutationWithRelationsResult bindArrowEndpointWithRelations({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
  required BindableState bindable,
  required List<BindableRelationState> relations,
  BindMode? mode,
  Point? focusPoint,
}) => _resolveMutationWithRelations(
  arrow: arrow,
  relations: relations,
  mutation: bindArrowEndpoint(
    arrow: arrow,
    edge: edge,
    bindable: bindable,
    mode: mode,
    focusPoint: focusPoint,
  ),
);

EndpointBindingMutationWithRelationsResult unbindArrowEndpointWithRelations({
  required ArrowState arrow,
  required ArrowEndpointEdge edge,
  required List<BindableRelationState> relations,
}) => _resolveMutationWithRelations(
  arrow: arrow,
  relations: relations,
  mutation: unbindArrowEndpoint(arrow: arrow, edge: edge),
);

EngineResult refreshEndpointBinding(RefreshEndpointBindingInput input) {
  final arrow = _readArrowState(input['arrow']);
  if (arrow == null) {
    return _emptyEngineResult();
  }

  final edge = _readEdge(input['edge']);
  final bindables = _readBindableStates(input['bindables']);
  final context = _readEngineContext(input['context']);
  final existingBinding = edge == arrowEndpointStart
      ? arrow.startBinding
      : arrow.endBinding;

  if (existingBinding == null) {
    return _emptyEngineResult();
  }

  final unboundMutation = unbindArrowEndpoint(arrow: arrow, edge: edge);
  final unboundArrow = applyArrowPatch(arrow, unboundMutation.arrowPatch);

  BindableState? boundBindable;
  for (final bindable in bindables) {
    if (bindable.id == existingBinding.elementId) {
      boundBindable = bindable;
      break;
    }
  }
  if (boundBindable == null) {
    return _withEngineEnvelope(unboundMutation);
  }

  final edgeIndex = edge == arrowEndpointStart ? 0 : arrow.points.length - 1;
  if (edgeIndex < 0 || edgeIndex >= arrow.points.length) {
    return _withEngineEnvelope(unboundMutation);
  }

  final localPoint = arrow.points[edgeIndex];
  final pointer = getPointAtIndexGlobal(arrow, edgeIndex);
  final threshold = binding_core.maxBindingDistance(context.zoom);
  final hit =
      isPointInBindable(pointer, boundBindable) ||
      distanceToBindableOutline(pointer, boundBindable) <= threshold;

  if (!hit) {
    return _withEngineEnvelope(unboundMutation);
  }

  final strategies = binding_core.getEndpointBindingStrategy(<String, dynamic>{
    'arrow': unboundArrow,
    'draggedPoints': <Map<String, dynamic>>[
      <String, dynamic>{'index': edgeIndex, 'point': localPoint},
    ],
    'pointer': pointer,
    'bindables': bindables,
    'context': context,
    'options': const <String, dynamic>{'finalize': true},
  });
  final strategy = edge == arrowEndpointStart
      ? strategies.start
      : strategies.end;
  if (strategy == null ||
      strategy.mode == null ||
      strategy.element == null ||
      strategy.element!.id != boundBindable.id) {
    return _withEngineEnvelope(unboundMutation);
  }

  final reboundMutation = bindArrowEndpoint(
    arrow: unboundArrow,
    edge: edge,
    bindable: boundBindable,
    mode: strategy.mode,
    focusPoint: strategy.focusPoint,
  );

  return EngineResult(
    arrowPatch: <String, dynamic>{
      ...unboundMutation.arrowPatch,
      ...reboundMutation.arrowPatch,
    },
    bindablePatches: <BindablePatch>[
      ...unboundMutation.bindablePatches,
      ...reboundMutation.bindablePatches,
    ],
    suggestedBinding: null,
    events: const <ArrowEngineEvent>[],
  );
}

EngineResult pruneArrowBindings(PruneArrowBindingsInput input) {
  final arrow = _readArrowState(input['arrow']);
  if (arrow == null) {
    return _emptyEngineResult();
  }

  final retained = _readStringList(input['retainedBindableIds']).toSet();
  final options = _asStringDynamicMap(input['options']);
  final shouldPruneStart = options?['pruneStart'] != false;
  final shouldPruneEnd = options?['pruneEnd'] != false;

  var workingArrow = arrow;
  final bindablePatches = <BindablePatch>[];
  final events = <ArrowEngineEvent>[];
  var nextStartBinding = arrow.startBinding;
  var nextEndBinding = arrow.endBinding;

  void maybePruneEdge(ArrowEndpointEdge edge) {
    final normalizedEdge = _normalizeEdge(edge);
    final shouldPrune = normalizedEdge == arrowEndpointStart
        ? shouldPruneStart
        : shouldPruneEnd;
    if (!shouldPrune) {
      return;
    }

    final binding = normalizedEdge == arrowEndpointStart
        ? workingArrow.startBinding
        : workingArrow.endBinding;
    if (binding == null || retained.contains(binding.elementId)) {
      return;
    }

    final mutation = unbindArrowEndpoint(arrow: workingArrow, edge: edge);
    workingArrow = applyArrowPatch(workingArrow, mutation.arrowPatch);
    bindablePatches.addAll(mutation.bindablePatches);
    events.add(BindingBrokenEvent(arrowId: arrow.id, edge: normalizedEdge));

    if (normalizedEdge == arrowEndpointStart) {
      nextStartBinding = null;
      return;
    }
    nextEndBinding = null;
  }

  maybePruneEdge(arrowEndpointStart);
  maybePruneEdge(arrowEndpointEnd);

  final arrowPatch = <String, dynamic>{
    if (!_bindingEqual(nextStartBinding, arrow.startBinding))
      'startBinding': nextStartBinding,
    if (!_bindingEqual(nextEndBinding, arrow.endBinding))
      'endBinding': nextEndBinding,
  };

  return EngineResult(
    arrowPatch: arrowPatch,
    bindablePatches: bindablePatches,
    suggestedBinding: null,
    events: events,
  );
}

List<BindablePatch> reconcileBindablePatchesForArrow({
  required ArrowBindingState arrow,
  required List<BindableRelationState> bindables,
}) {
  final boundBindableIds = _collectBoundBindableIds(arrow);
  final patches = <BindablePatch>[];
  final seenBindableIds = <String>{};

  for (final bindable in bindables) {
    seenBindableIds.add(bindable.id);
    final hasArrow = bindable.boundArrowIds.contains(arrow.id);
    final shouldContainArrow = boundBindableIds.contains(bindable.id);

    if (hasArrow && !shouldContainArrow) {
      patches.add(BindablePatch(id: bindable.id, removeBoundArrowId: arrow.id));
      continue;
    }

    if (!hasArrow && shouldContainArrow) {
      patches.add(BindablePatch(id: bindable.id, addBoundArrowId: arrow.id));
    }
  }

  for (final bindableId in boundBindableIds) {
    if (seenBindableIds.contains(bindableId)) {
      continue;
    }
    patches.add(BindablePatch(id: bindableId, addBoundArrowId: arrow.id));
  }

  return patches;
}

List<ArrowBindingStatePatch> remapArrowBindingsAfterDuplication({
  required List<ArrowBindingState> arrows,
  required IdMapInput bindableIdMap,
  bool preserveUnmapped = false,
}) {
  final bindableIdLookup = _normalizeIdMap(bindableIdMap);
  final patches = <ArrowBindingStatePatch>[];

  for (final arrow in arrows) {
    final startBinding = _remapBinding(
      arrow.startBinding,
      bindableIdLookup,
      preserveUnmapped,
    );
    final endBinding = _remapBinding(
      arrow.endBinding,
      bindableIdLookup,
      preserveUnmapped,
    );

    if (_bindingEqual(startBinding, arrow.startBinding) &&
        _bindingEqual(endBinding, arrow.endBinding)) {
      continue;
    }

    patches.add(<String, dynamic>{
      'id': arrow.id,
      'startBinding': startBinding,
      'endBinding': endBinding,
    });
  }

  return patches;
}

List<BindableRelationPatch> remapBindableRelationsAfterDuplication({
  required List<BindableRelationState> bindables,
  required IdMapInput arrowIdMap,
  bool preserveUnmapped = false,
}) {
  final arrowIdLookup = _normalizeIdMap(arrowIdMap);
  final patches = <BindableRelationPatch>[];

  for (final bindable in bindables) {
    final next = bindable.boundArrowIds
        .map(
          (arrowId) =>
              arrowIdLookup[arrowId] ?? (preserveUnmapped ? arrowId : null),
        )
        .whereType<String>()
        .toList(growable: false);

    if (_arraysEqual(next, bindable.boundArrowIds)) {
      continue;
    }

    patches.add(BindableRelationPatch(id: bindable.id, boundArrowIds: next));
  }

  return patches;
}

List<ArrowBindingStatePatch> repairArrowBindingsAfterBindableDeletion({
  required List<ArrowBindingState> arrows,
  required List<String> deletedBindableIds,
}) {
  if (deletedBindableIds.isEmpty) {
    return <ArrowBindingStatePatch>[];
  }

  final deleted = deletedBindableIds.toSet();
  final patches = <ArrowBindingStatePatch>[];

  for (final arrow in arrows) {
    final nextStart =
        arrow.startBinding != null &&
            deleted.contains(arrow.startBinding!.elementId)
        ? null
        : arrow.startBinding;
    final nextEnd =
        arrow.endBinding != null &&
            deleted.contains(arrow.endBinding!.elementId)
        ? null
        : arrow.endBinding;

    if (_bindingEqual(nextStart, arrow.startBinding) &&
        _bindingEqual(nextEnd, arrow.endBinding)) {
      continue;
    }

    patches.add(<String, dynamic>{
      'id': arrow.id,
      'startBinding': nextStart,
      'endBinding': nextEnd,
    });
  }

  return patches;
}

List<BindableRelationPatch> repairBindableRelationsAfterArrowDeletion({
  required List<BindableRelationState> bindables,
  required List<String> deletedArrowIds,
}) {
  if (deletedArrowIds.isEmpty) {
    return <BindableRelationPatch>[];
  }

  final deleted = deletedArrowIds.toSet();
  final patches = <BindableRelationPatch>[];

  for (final bindable in bindables) {
    final next = bindable.boundArrowIds
        .where((arrowId) => !deleted.contains(arrowId))
        .toList(growable: false);
    if (next.length == bindable.boundArrowIds.length) {
      continue;
    }
    patches.add(BindableRelationPatch(id: bindable.id, boundArrowIds: next));
  }

  return patches;
}

LifecycleSyncResult _applyLifecycleBindingAndRelationPatches({
  required LifecycleSyncBaseInput input,
  required List<ArrowBindingStatePatch> arrowBindingPatches,
  required List<BindableRelationPatch> relationPatches,
  required bool recomputeAllElbows,
}) {
  final inputArrows = _readArrowStates(input['arrows']);
  final inputBindables = _readBindableRelationStates(input['bindables']);
  final geometryBindables = _readBindableStates(input['geometryBindables']);
  final context = input.containsKey('context')
      ? _readEngineContext(input['context'])
      : defaultEngineContext;

  final arrowPatchById = <String, ArrowPatch>{};
  for (final bindingPatch in arrowBindingPatches) {
    final patch = _toArrowPatchFromBindingPatch(bindingPatch);
    if (_hasArrowPatchChanges(patch) && bindingPatch['id'] is String) {
      arrowPatchById[bindingPatch['id'] as String] = patch;
    }
  }

  final arrows = inputArrows
      .map((arrow) {
        final basePatch = arrowPatchById[arrow.id];
        final withBindings = basePatch != null
            ? applyArrowPatch(arrow, basePatch)
            : arrow;
        final shouldRecomputeElbow =
            arrow.elbowed && (recomputeAllElbows || basePatch != null);
        if (!shouldRecomputeElbow) {
          return withBindings;
        }

        final elbowPatch = recomputeAllElbows
            ? updateElbowArrowPatch(<String, dynamic>{
                'arrow': withBindings,
                'updates': <String, dynamic>{
                  'points': <Point>[
                    withBindings.points[0],
                    withBindings.points[withBindings.points.length - 1],
                  ],
                },
                'bindables': geometryBindables,
                'context': context,
                'options': const <String, dynamic>{'isDragging': false},
              })
            : recomputeElbowPatch(<String, dynamic>{
                'arrow': withBindings,
                'bindables': geometryBindables,
                'context': context,
              });
        if (!_hasArrowPatchChanges(elbowPatch)) {
          return withBindings;
        }

        arrowPatchById[arrow.id] = <String, dynamic>{
          ...(basePatch ?? const <String, dynamic>{}),
          ...elbowPatch,
        };
        return applyArrowPatch(withBindings, elbowPatch);
      })
      .toList(growable: false);

  final bindables = applyBindableRelationPatches(
    inputBindables,
    relationPatches,
  );
  final arrowPatches = inputArrows
      .map((arrow) {
        final patch = arrowPatchById[arrow.id];
        if (patch == null) {
          return null;
        }
        return ArrowStatePatchWithId(id: arrow.id, patch: patch);
      })
      .whereType<ArrowStatePatchWithId>()
      .toList(growable: false);

  return LifecycleSyncResult(
    arrows: arrows,
    bindables: bindables,
    arrowPatches: arrowPatches,
    relationPatches: relationPatches,
    events: const <ArrowEngineEvent>[],
  );
}

LifecycleSyncResult syncBindingsAfterBindablePrune(
  SyncBindingsAfterBindablePruneInput input,
) {
  final arrowsInput = _readArrowStates(input['arrows']);
  final bindablesInput = _readBindableRelationStates(input['bindables']);
  final retainedBindableIds = _readStringList(input['retainedBindableIds']);
  final options = _asStringDynamicMap(input['options']);
  final recomputeElbows = options?['recomputeElbows'] == true;
  final context = input.containsKey('context')
      ? _readEngineContext(input['context'])
      : defaultEngineContext;
  final geometryBindables = _readBindableStates(input['geometryBindables']);

  final relationPatchById = <String, BindableRelationPatch>{};
  final arrowPatches = <ArrowStatePatchWithId>[];
  final events = <ArrowEngineEvent>[];

  var bindables = bindablesInput;
  final arrows = arrowsInput
      .map((arrow) {
        final pruneResult = pruneArrowBindings(<String, dynamic>{
          'arrow': arrow,
          'retainedBindableIds': retainedBindableIds,
          'options': <String, dynamic>{
            'pruneStart': options?['pruneStart'],
            'pruneEnd': options?['pruneEnd'],
          },
        });
        events.addAll(pruneResult.events);

        var patch = pruneResult.arrowPatch;
        var nextArrow = _hasArrowPatchChanges(patch)
            ? applyArrowPatch(arrow, patch)
            : arrow;

        if (recomputeElbows && arrow.elbowed && _hasArrowPatchChanges(patch)) {
          final elbowPatch = updateElbowArrowPatch(<String, dynamic>{
            'arrow': nextArrow,
            'updates': <String, dynamic>{
              'points': <Point>[
                nextArrow.points[0],
                nextArrow.points[nextArrow.points.length - 1],
              ],
            },
            'bindables': geometryBindables,
            'context': context,
            'options': const <String, dynamic>{'isDragging': false},
          });

          if (_hasArrowPatchChanges(elbowPatch)) {
            patch = <String, dynamic>{...patch, ...elbowPatch};
            nextArrow = applyArrowPatch(nextArrow, elbowPatch);
          }
        }

        if (_hasArrowPatchChanges(patch)) {
          arrowPatches.add(ArrowStatePatchWithId(id: arrow.id, patch: patch));
        }

        if (pruneResult.bindablePatches.isNotEmpty) {
          final relationPatches = reduceBindablePatchesToRelationPatches(
            bindables,
            pruneResult.bindablePatches,
          );

          if (relationPatches.isNotEmpty) {
            bindables = applyBindableRelationPatches(
              bindables,
              relationPatches,
            );
            for (final relationPatch in relationPatches) {
              relationPatchById[relationPatch.id] = relationPatch;
            }
          }
        }

        return nextArrow;
      })
      .toList(growable: false);

  return LifecycleSyncResult(
    arrows: arrows,
    bindables: bindables,
    arrowPatches: arrowPatches,
    relationPatches: relationPatchById.values.toList(growable: false),
    events: events,
  );
}

LifecycleSyncResult syncBindingsAfterDuplication(
  SyncBindingsAfterDuplicationInput input,
) {
  final arrows = _readArrowStates(input['arrows']);
  final bindables = _readBindableRelationStates(input['bindables']);
  final preserveUnmapped = input['preserveUnmapped'] == true;
  final bindableIdMap = input.containsKey('bindableIdMap')
      ? input['bindableIdMap'] as IdMapInput
      : <String, String>{};
  final arrowIdMap = input.containsKey('arrowIdMap')
      ? input['arrowIdMap'] as IdMapInput
      : <String, String>{};

  final arrowBindingPatches = remapArrowBindingsAfterDuplication(
    arrows: arrows.map(_toArrowBindingState).toList(growable: false),
    bindableIdMap: bindableIdMap,
    preserveUnmapped: preserveUnmapped,
  );
  final relationPatches = remapBindableRelationsAfterDuplication(
    bindables: bindables,
    arrowIdMap: arrowIdMap,
    preserveUnmapped: preserveUnmapped,
  );

  return _applyLifecycleBindingAndRelationPatches(
    input: input,
    arrowBindingPatches: arrowBindingPatches,
    relationPatches: relationPatches,
    recomputeAllElbows: true,
  );
}

LifecycleSyncResult syncBindingsAfterDeletion(
  SyncBindingsAfterDeletionInput input,
) {
  final arrows = _readArrowStates(input['arrows']);
  final bindables = _readBindableRelationStates(input['bindables']);
  final deletedBindableIds = _readStringList(input['deletedBindableIds']);
  final deletedArrowIds = _readStringList(input['deletedArrowIds']);

  final arrowBindingPatches = repairArrowBindingsAfterBindableDeletion(
    arrows: arrows.map(_toArrowBindingState).toList(growable: false),
    deletedBindableIds: deletedBindableIds,
  );
  final relationPatches = repairBindableRelationsAfterArrowDeletion(
    bindables: bindables,
    deletedArrowIds: deletedArrowIds,
  );

  return _applyLifecycleBindingAndRelationPatches(
    input: input,
    arrowBindingPatches: arrowBindingPatches,
    relationPatches: relationPatches,
    recomputeAllElbows: false,
  );
}
