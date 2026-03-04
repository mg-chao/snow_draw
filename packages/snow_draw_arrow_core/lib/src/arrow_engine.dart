import 'arrow_binding_core.dart';
import 'arrow_elbow_core.dart';
import 'arrow_focus_core.dart';
import 'arrow_geom.dart';
import 'arrow_hit_test.dart';
import 'arrow_state_core.dart';
import 'arrow_types.dart';

EngineResult _emptyEngineResult() => const EngineResult(
  arrowPatch: <String, dynamic>{},
  bindablePatches: <BindablePatch>[],
  suggestedBinding: null,
  events: <ArrowEngineEvent>[],
);

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

ArrowState? _readArrow(Object? value) => value is ArrowState ? value : null;

ArrowBindingState? _readArrowBindingState(Object? value) {
  if (value is ArrowBindingState) {
    return value;
  }
  if (value is ArrowState) {
    return ArrowBindingState(
      id: value.id,
      startBinding: value.startBinding,
      endBinding: value.endBinding,
    );
  }
  if (value is Map) {
    final id = value['id'];
    final startBinding = _readFixedPointBinding(value['startBinding']);
    final endBinding = _readFixedPointBinding(value['endBinding']);
    if (id is String) {
      return ArrowBindingState(
        id: id,
        startBinding: startBinding,
        endBinding: endBinding,
      );
    }
  }
  return null;
}

BindableState? _readBindable(Object? value) =>
    value is BindableState ? value : null;

List<ArrowState> _readArrows(Object? value) {
  if (value is List<ArrowState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<ArrowState>().toList(growable: false);
  }
  return const <ArrowState>[];
}

List<BindableState> _readBindables(Object? value) {
  if (value is List<BindableState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableState>().toList(growable: false);
  }
  return const <BindableState>[];
}

List<BindableRelationState> _readRelations(Object? value) {
  if (value is List<BindableRelationState>) {
    return value;
  }
  if (value is List) {
    return value.whereType<BindableRelationState>().toList(growable: false);
  }
  return const <BindableRelationState>[];
}

List<String>? _readStringList(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List<String>) {
    return value;
  }
  if (value is List) {
    return value.whereType<String>().toList(growable: false);
  }
  return null;
}

Point? _readPoint(Object? value) {
  if (value is! List || value.length < 2) {
    return null;
  }
  final x = value[0];
  final y = value[1];
  if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
    return null;
  }
  return <double>[x.toDouble(), y.toDouble()];
}

List<Point>? _readPoints(Object? value) {
  if (value is List<Point>) {
    return value;
  }
  if (value is! List) {
    return null;
  }
  final points = <Point>[];
  for (final entry in value) {
    final point = _readPoint(entry);
    if (point != null) {
      points.add(point);
    }
  }
  return points;
}

List<FixedSegment>? _readFixedSegments(Object? value) {
  if (value is List<FixedSegment>) {
    return value;
  }
  if (value is List) {
    return value.whereType<FixedSegment>().toList(growable: false);
  }
  return null;
}

FixedPointBinding? _readFixedPointBinding(Object? value) {
  if (value is FixedPointBinding) {
    return value;
  }
  if (value is Map) {
    final elementId = value['elementId'];
    final fixedPoint = _readPoint(value['fixedPoint']);
    final modeValue = value['mode'];
    final mode = modeValue is String ? modeValue : '';
    if (elementId is String && fixedPoint != null) {
      return FixedPointBinding(
        elementId: elementId,
        fixedPoint: fixedPoint,
        mode: mode,
      );
    }
  }
  return null;
}

EngineContext _readContext(Object? value) {
  if (value is EngineContext) {
    return value;
  }
  return normalizeEngineContext(_asStringDynamicMap(value));
}

ArrowEndpointEdge? _readArrowEndpointEdge(Object? value) {
  if (value == arrowEndpointStart || value == 'start') {
    return arrowEndpointStart;
  }
  if (value == arrowEndpointEnd || value == 'end') {
    return arrowEndpointEnd;
  }
  return null;
}

ArrowState _applyPatchToArrow(ArrowState arrow, ArrowPatch patch) {
  final hasStartBinding = patch.containsKey('startBinding');
  final hasEndBinding = patch.containsKey('endBinding');
  final hasFixedSegments = patch.containsKey('fixedSegments');
  final hasStartIsSpecial = patch.containsKey('startIsSpecial');
  final hasEndIsSpecial = patch.containsKey('endIsSpecial');

  return arrow.copyWith(
    x: patch['x'] is num ? (patch['x'] as num).toDouble() : null,
    y: patch['y'] is num ? (patch['y'] as num).toDouble() : null,
    width: patch['width'] is num ? (patch['width'] as num).toDouble() : null,
    height: patch['height'] is num ? (patch['height'] as num).toDouble() : null,
    points: _readPoints(patch['points']),
    startBinding: hasStartBinding
        ? patch['startBinding'] as FixedPointBinding?
        : null,
    setStartBinding: hasStartBinding,
    endBinding: hasEndBinding
        ? patch['endBinding'] as FixedPointBinding?
        : null,
    setEndBinding: hasEndBinding,
    fixedSegments: _readFixedSegments(patch['fixedSegments']),
    setFixedSegments: hasFixedSegments,
    startIsSpecial: hasStartIsSpecial ? patch['startIsSpecial'] as bool? : null,
    setStartIsSpecial: hasStartIsSpecial,
    endIsSpecial: hasEndIsSpecial ? patch['endIsSpecial'] as bool? : null,
    setEndIsSpecial: hasEndIsSpecial,
  );
}

bool _hasPatchChanges(ArrowPatch patch) => patch.isNotEmpty;

bool _isArrowAffectedByChangedBindables(
  ArrowState arrow,
  Set<String>? changedBindableIds,
) {
  if (changedBindableIds == null || changedBindableIds.isEmpty) {
    return true;
  }
  return (arrow.startBinding != null &&
          changedBindableIds.contains(arrow.startBinding!.elementId)) ||
      (arrow.endBinding != null &&
          changedBindableIds.contains(arrow.endBinding!.elementId));
}

List<BindableState> _mergeBindables(
  List<BindableState> primary, [
  List<BindableState>? fallback,
]) {
  if (fallback == null || fallback.isEmpty) {
    return primary;
  }

  final byId = <String, BindableState>{
    for (final bindable in primary) bindable.id: bindable,
  };
  final merged = <BindableState>[...primary];
  for (final bindable in fallback) {
    if (byId.containsKey(bindable.id)) {
      continue;
    }
    byId[bindable.id] = bindable;
    merged.add(bindable);
  }
  return merged;
}

FixedPointBinding? _withModeNormalized(
  FixedPointBinding? binding,
  BindMode mode,
) {
  if (binding == null) {
    return null;
  }
  return binding.copyWith(
    mode: mode,
    fixedPoint: normalizeFixedPoint(binding.fixedPoint),
  );
}

Set<String> _collectBoundBindableIds(ArrowBindingState arrow) {
  final ids = <String>{};
  if (arrow.startBinding != null) {
    ids.add(arrow.startBinding!.elementId);
  }
  if (arrow.endBinding != null) {
    ids.add(arrow.endBinding!.elementId);
  }
  return ids;
}

List<BindablePatch> _reconcileBindablePatchesForArrow(
  ArrowBindingState arrow,
  List<BindableRelationState> bindables,
) {
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

EngineResult computeEndpointDrag(ComputeEndpointDragInput input) {
  final bindingResult = computeSimpleBindingPatch(input);
  final arrow = _readArrow(input['arrow']);
  if (arrow == null) {
    return bindingResult;
  }

  final nextArrow = _applyPatchToArrow(arrow, bindingResult.arrowPatch);
  if (!nextArrow.elbowed) {
    return EngineResult(
      arrowPatch: bindingResult.arrowPatch,
      bindablePatches: bindingResult.bindablePatches,
      suggestedBinding: bindingResult.suggestedBinding,
      events: bindingResult.events,
    );
  }

  final elbowPatch = recomputeElbowPatch(<String, dynamic>{
    'arrow': nextArrow,
    'bindables': _readBindables(input['bindables']),
    'context': _readContext(input['context']),
  });

  final bindingPatch = bindingResult.arrowPatch;
  return EngineResult(
    arrowPatch: <String, dynamic>{
      ...bindingPatch,
      ...elbowPatch,
      if (!bindingPatch.containsKey('startBinding'))
        'startBinding': nextArrow.startBinding,
      if (!bindingPatch.containsKey('endBinding'))
        'endBinding': nextArrow.endBinding,
    },
    bindablePatches: bindingResult.bindablePatches,
    suggestedBinding: bindingResult.suggestedBinding,
    events: bindingResult.events,
  );
}

EngineResult finalizeEndpointDrag(ComputeEndpointDragInput input) {
  final nextInput = <String, dynamic>{...input};
  final options = _asStringDynamicMap(input['options']) ?? <String, dynamic>{};
  nextInput['options'] = <String, dynamic>{...options, 'finalize': true};
  return computeEndpointDrag(nextInput);
}

EngineResult recomputeAfterBindableChange(
  RecomputeAfterBindableChangeInput input,
) {
  final arrow = _readArrow(input['arrow']);
  if (arrow == null) {
    return _emptyEngineResult();
  }

  final bindables = _readBindables(input['bindables']);
  final context = _readContext(input['context']);
  final changedBindableIds = _readStringList(input['changedBindableIds']);
  final options = _asStringDynamicMap(input['options']);

  final base = recomputeBindingsAfterBindableChange(
    arrow,
    bindables,
    context,
    changedBindableIds,
    options,
  );

  final arrowWithBase = _applyPatchToArrow(arrow, base.arrowPatch);
  if (!arrowWithBase.elbowed) {
    return base;
  }

  final elbowPatch = recomputeElbowPatch(<String, dynamic>{
    'arrow': arrowWithBase,
    'bindables': bindables,
    'context': context,
  });

  final basePatch = base.arrowPatch;
  return EngineResult(
    arrowPatch: <String, dynamic>{
      ...basePatch,
      ...elbowPatch,
      if (!basePatch.containsKey('startBinding'))
        'startBinding': arrowWithBase.startBinding,
      if (!basePatch.containsKey('endBinding'))
        'endBinding': arrowWithBase.endBinding,
    },
    bindablePatches: base.bindablePatches,
    suggestedBinding: base.suggestedBinding,
    events: base.events,
  );
}

RecomputeBindingsForChangedBindablesResult recomputeBindingsForChangedBindables(
  RecomputeBindingsForChangedBindablesInput input,
) {
  final changedBindableIds = _readStringList(input['changedBindableIds']);
  final changedSet = changedBindableIds != null && changedBindableIds.isNotEmpty
      ? changedBindableIds.toSet()
      : null;

  final arrowsInput = _readArrows(input['arrows']);
  final bindablesInput = _readBindables(input['bindables']);
  final relationsInput = _readRelations(input['relations']);
  final context = _readContext(input['context']);
  final options = _asStringDynamicMap(input['options']);

  final arrows = <ArrowState>[];
  final arrowPatches = <ArrowStatePatchWithId>[];
  final bindablePatches = <BindablePatch>[];
  final events = <ArrowEngineEvent>[];

  for (final arrow in arrowsInput) {
    if (!_isArrowAffectedByChangedBindables(arrow, changedSet)) {
      arrows.add(arrow);
      continue;
    }

    final result = recomputeAfterBindableChange(<String, dynamic>{
      'arrow': arrow,
      'bindables': bindablesInput,
      'changedBindableIds': changedBindableIds,
      'context': context,
      'options': options,
    });

    final patch = result.arrowPatch;
    if (_hasPatchChanges(patch)) {
      arrows.add(_applyPatchToArrow(arrow, patch));
      arrowPatches.add(ArrowStatePatchWithId(id: arrow.id, patch: patch));
    } else {
      arrows.add(arrow);
    }

    if (result.bindablePatches.isNotEmpty) {
      bindablePatches.addAll(result.bindablePatches);
    }
    if (result.events.isNotEmpty) {
      events.addAll(result.events);
    }
  }

  final relationPatches = reduceBindablePatchesToRelationPatches(
    relationsInput,
    bindablePatches,
  );
  final bindables = applyBindableRelationPatches(
    relationsInput,
    relationPatches,
  );

  return RecomputeBindingsForChangedBindablesResult(
    arrows: arrows,
    bindables: bindables,
    arrowPatches: arrowPatches,
    relationPatches: relationPatches,
    events: events,
  );
}

ArrowPatch recomputeElbow(RecomputeElbowInput input) =>
    recomputeElbowPatch(input);

EngineResult computeFocusDrag(ComputeFocusPointDragInput input) =>
    computeFocusPointDrag(input);

EngineResult finalizeFocusDrag(FinalizeFocusPointDragInput input) {
  final arrow = _readArrowBindingState(input['arrow']);
  final bindables = _readRelations(input['bindables']);
  return EngineResult(
    arrowPatch: const <String, dynamic>{},
    bindablePatches: arrow == null
        ? const <BindablePatch>[]
        : _reconcileBindablePatchesForArrow(arrow, bindables),
    suggestedBinding: null,
    events: const <ArrowEngineEvent>[],
  );
}

List<FocusPointDescriptor> resolveVisibleFocusPoints(
  ListVisibleFocusPointsInput input,
) => listVisibleFocusPoints(input);

ArrowEndpointEdge? resolveFocusPointHit(PickFocusPointInput input) =>
    pickFocusPoint(input);

FocusPointHit resolveFocusPointHitWithOffset(
  PickFocusPointWithOffsetInput input,
) => pickFocusPointWithOffset(input);

FixedPointBinding? repairBindingOnRestore(RepairBindingOnRestoreInput input) {
  final binding = _readFixedPointBinding(input['binding']);
  if (binding == null) {
    return null;
  }

  final bindables = _readBindables(input['bindables']);
  final existingBindables = _readBindables(input['existingBindables']);
  final allBindables = _mergeBindables(bindables, existingBindables);

  BindableState? bindable;
  for (final candidate in allBindables) {
    if (candidate.id == binding.elementId) {
      bindable = candidate;
      break;
    }
  }
  if (bindable == null || binding.elementId.isEmpty) {
    return null;
  }

  final arrow = _readArrow(input['arrow']);
  if (arrow?.elbowed ?? false) {
    return FixedPointBinding(
      elementId: bindable.id,
      mode: binding.mode.isNotEmpty ? binding.mode : bindModeOrbit,
      fixedPoint: normalizeFixedPoint(binding.fixedPoint),
    );
  }

  if (binding.mode.isNotEmpty) {
    return FixedPointBinding(
      elementId: bindable.id,
      mode: binding.mode,
      fixedPoint: normalizeFixedPoint(binding.fixedPoint),
    );
  }

  final edge = _readArrowEndpointEdge(input['edge']);
  if (arrow == null || edge == null) {
    return FixedPointBinding(
      elementId: bindable.id,
      mode: bindModeOrbit,
      fixedPoint: normalizeFixedPoint(binding.fixedPoint),
    );
  }

  final edgeIndex = edge == arrowEndpointStart ? 0 : arrow.points.length - 1;
  final edgePoint = getPointAtIndexGlobal(arrow, edgeIndex);
  final mode = isPointInBindable(edgePoint, bindable)
      ? bindModeInside
      : bindModeOrbit;

  final safeArrow = arrow.copyWith(
    startBinding: _withModeNormalized(arrow.startBinding, mode),
    setStartBinding: true,
    endBinding: _withModeNormalized(arrow.endBinding, mode),
    setEndBinding: true,
  );
  final focusPoint = mode == bindModeInside
      ? edgePoint
      : (projectFixedPointOntoDiagonal(
              safeArrow,
              edgePoint,
              bindable,
              edge,
              allBindables,
              1,
            ) ??
            edgePoint);

  return FixedPointBinding(
    elementId: bindable.id,
    mode: mode,
    fixedPoint: calculateFixedPointForBinding(
      bindable: bindable,
      point: focusPoint,
    ),
  );
}

ArrowPatch? repairInvalidUnboundElbowArrowOnRestore(
  RepairInvalidUnboundElbowArrowOnRestoreInput input,
) {
  final arrow = _readArrow(input['arrow']);
  if (arrow == null) {
    return null;
  }
  if (arrow.startBinding != null ||
      arrow.endBinding != null ||
      !arrow.elbowed) {
    return null;
  }
  if (validateElbowPoints(arrow.points)) {
    return null;
  }
  if (arrow.points.isEmpty) {
    return null;
  }

  final lastPoint = arrow.points.last;
  return updateElbowArrowPatch(<String, dynamic>{
    'arrow': arrow,
    'updates': <String, dynamic>{
      'points': <Point>[
        <double>[0, 0],
        <double>[lastPoint[0], lastPoint[1]],
      ],
    },
    'bindables': _readBindables(input['bindables']),
    'context': _readContext(input['context']),
  });
}

ArrowPatch? repairSelfBoundExtremeElbowArrowOnRestore(
  RepairSelfBoundExtremeElbowArrowOnRestoreInput input,
) {
  final maxCoordinateValue = input['maxCoordinate'];
  final maxCoordinate = maxCoordinateValue is num
      ? maxCoordinateValue.toDouble()
      : 1e6;
  final arrow = _readArrow(input['arrow']);
  final bindable = _readBindable(input['bindable']);
  if (arrow == null || bindable == null) {
    return null;
  }

  if (!arrow.elbowed ||
      arrow.startBinding == null ||
      arrow.endBinding == null ||
      arrow.startBinding!.elementId != arrow.endBinding!.elementId ||
      arrow.startBinding!.elementId != bindable.id ||
      arrow.points.length <= 1) {
    return null;
  }

  final hasExtremePoint = arrow.points.any(
    (point) => point[0].abs() > maxCoordinate || point[1].abs() > maxCoordinate,
  );
  if (!hasExtremePoint) {
    return null;
  }

  return <String, dynamic>{
    'x': bindable.x + bindable.width / 2,
    'y': bindable.y - 5,
    'width': bindable.width,
    'height': bindable.height,
    'points': <Point>[
      <double>[0, 0],
      <double>[0, -10],
      <double>[bindable.width / 2 + 5, -10],
      <double>[bindable.width / 2 + 5, bindable.height / 2 + 5],
    ],
  };
}

ValidationReport validateArrowInvariant(ArrowState arrow) {
  final violations = <String>[];

  if (arrow.points.length < 2) {
    violations.add('arrow must contain at least two points');
  }

  final firstPoint = arrow.points.isEmpty ? null : arrow.points.first;
  if (firstPoint != null && !pointsEqual(firstPoint, <double>[0, 0])) {
    violations.add('arrow points must be normalized with [0,0] as first point');
  }

  if (arrow.elbowed) {
    if (!validateElbowPoints(arrow.points)) {
      violations.add('elbow arrow must keep orthogonal segments');
    }
    violations.addAll(validateElbowInvariant(arrow));
  }

  return ValidationReport(valid: violations.isEmpty, violations: violations);
}

typedef ArrowEngine = ({
  EngineResult Function(ComputeEndpointDragInput input) computeEndpointDrag,
  EngineResult Function(ComputeEndpointDragInput input) finalizeEndpointDrag,
  EngineResult Function(ComputeFocusPointDragInput input) computeFocusDrag,
  EngineResult Function(FinalizeFocusPointDragInput input) finalizeFocusDrag,
  List<FocusPointDescriptor> Function(ListVisibleFocusPointsInput input)
  resolveVisibleFocusPoints,
  ArrowEndpointEdge? Function(PickFocusPointInput input) resolveFocusPointHit,
  FocusPointHit Function(PickFocusPointWithOffsetInput input)
  resolveFocusPointHitWithOffset,
  EngineResult Function(RecomputeAfterBindableChangeInput input)
  recomputeAfterBindableChange,
  RecomputeBindingsForChangedBindablesResult Function(
    RecomputeBindingsForChangedBindablesInput input,
  )
  recomputeBindingsForChangedBindables,
  ArrowPatch Function(RecomputeElbowInput input) recomputeElbow,
  FixedPointBinding? Function(RepairBindingOnRestoreInput input)
  repairBindingOnRestore,
  ArrowPatch? Function(RepairInvalidUnboundElbowArrowOnRestoreInput input)
  repairInvalidUnboundElbowArrowOnRestore,
  ArrowPatch? Function(RepairSelfBoundExtremeElbowArrowOnRestoreInput input)
  repairSelfBoundExtremeElbowArrowOnRestore,
  ValidationReport Function(ArrowState arrow) validateArrowInvariant,
});

ArrowEngine createArrowEngine() => (
  computeEndpointDrag: computeEndpointDrag,
  finalizeEndpointDrag: finalizeEndpointDrag,
  computeFocusDrag: computeFocusDrag,
  finalizeFocusDrag: finalizeFocusDrag,
  resolveVisibleFocusPoints: resolveVisibleFocusPoints,
  resolveFocusPointHit: resolveFocusPointHit,
  resolveFocusPointHitWithOffset: resolveFocusPointHitWithOffset,
  recomputeAfterBindableChange: recomputeAfterBindableChange,
  recomputeBindingsForChangedBindables: recomputeBindingsForChangedBindables,
  recomputeElbow: recomputeElbow,
  repairBindingOnRestore: repairBindingOnRestore,
  repairInvalidUnboundElbowArrowOnRestore:
      repairInvalidUnboundElbowArrowOnRestore,
  repairSelfBoundExtremeElbowArrowOnRestore:
      repairSelfBoundExtremeElbowArrowOnRestore,
  validateArrowInvariant: validateArrowInvariant,
);
