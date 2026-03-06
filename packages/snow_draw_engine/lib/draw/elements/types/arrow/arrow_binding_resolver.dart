import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_core_session.dart';

/// Resolves arrow bindings when bindable elements change position.
///
/// The resolver delegates recomputation to the integrated arrow core module
/// and maps the resulting patch back into engine element state.
@immutable
final class ArrowBindingResolutionResult {
  const ArrowBindingResolutionResult({
    this.updatedElements = const <String, ElementState>{},
    this.orderedElementIds,
  });

  static const empty = ArrowBindingResolutionResult();

  final Map<String, ElementState> updatedElements;
  final List<String>? orderedElementIds;
}

final class ArrowBindingResolver {
  ArrowBindingResolver._();

  static final instance = ArrowBindingResolver._();

  ArrowBindingResolutionResult resolve({
    required Map<String, ElementState> baseElements,
    required Map<String, ElementState> updatedElements,
    required Set<String> changedElementIds,
    required List<String> orderedElementIds,
    core.EngineContext? engineContext,
    Set<String> skipArrowIds = const <String>{},
  }) {
    if (changedElementIds.isEmpty) {
      return ArrowBindingResolutionResult.empty;
    }

    final lookup = CombinedElementLookup(
      base: baseElements,
      overlay: updatedElements,
    );
    final changedBindableIds = <String>{
      for (final id in changedElementIds)
        if (lookup[id] case final element? when isArrowBindableElement(element))
          id,
    };
    if (changedBindableIds.isEmpty) {
      return ArrowBindingResolutionResult.empty;
    }

    final session = ArrowCoreSession.fromElements(
      lookup.values,
      onlyBoundArrows: true,
      orderedElementIds: orderedElementIds,
      context: engineContext,
    );
    if (!session.hasArrows) {
      return ArrowBindingResolutionResult.empty;
    }

    final orderIndexById = <String, int>{
      for (var index = 0; index < orderedElementIds.length; index += 1)
        orderedElementIds[index]: index,
    };
    final sortedChangedBindableIds = changedBindableIds.toList(growable: false)
      ..sort((left, right) {
        final leftIndex = orderIndexById[left] ?? 1 << 30;
        final rightIndex = orderIndexById[right] ?? 1 << 30;
        if (leftIndex != rightIndex) {
          return leftIndex.compareTo(rightIndex);
        }
        return left.compareTo(right);
      });
    final changedBindableIdSet = sortedChangedBindableIds.toSet();

    final arrowPatches = <core.ArrowStatePatchWithId>[];
    final events = <core.ArrowEngineEvent>[];

    for (final arrow in session.arrows) {
      if (skipArrowIds.contains(arrow.id)) {
        continue;
      }
      if (!_isArrowAffectedByChangedBindables(arrow, changedBindableIdSet)) {
        continue;
      }

      final result = arrow.elbowed
          ? _recomputeElbowBindingsAfterBindableChange(
              arrow: arrow,
              bindables: session.bindables,
              context: session.context,
              changedBindableIds: sortedChangedBindableIds,
              changedBindableIdSet: changedBindableIdSet,
            )
          : recomputeCoreBindingsAfterBindableChange(
              arrow: arrow,
              bindables: session.bindables,
              context: session.context,
              changedBindableIds: sortedChangedBindableIds,
              options: _buildPerArrowRecomputeOptions(
                arrow: arrow,
                changedBindableIds: changedBindableIdSet,
              ),
            );
      if (result.arrowPatch.isNotEmpty) {
        arrowPatches.add(
          core.ArrowStatePatchWithId(id: arrow.id, patch: result.arrowPatch),
        );
      }
      if (result.events.isNotEmpty) {
        events.addAll(result.events);
      }
    }

    final patchedUpdates = session.applyArrowPatches(arrowPatches);
    final reorderedElementIds = session.reduceEventsToOrderedElementIds(events);

    if (patchedUpdates.isEmpty && reorderedElementIds == null) {
      return ArrowBindingResolutionResult.empty;
    }

    return ArrowBindingResolutionResult(
      updatedElements: patchedUpdates,
      orderedElementIds: reorderedElementIds,
    );
  }
}

const _emptyEngineResult = core.EngineResult(
  arrowPatch: <String, dynamic>{},
  bindablePatches: <core.BindablePatch>[],
  suggestedBinding: null,
  events: <core.ArrowEngineEvent>[],
);

core.EngineResult _recomputeElbowBindingsAfterBindableChange({
  required core.ArrowState arrow,
  required List<core.BindableState> bindables,
  required core.EngineContext context,
  required List<String> changedBindableIds,
  required Set<String> changedBindableIdSet,
}) {
  final bindablesById = <String, core.BindableState>{
    for (final bindable in bindables) bindable.id: bindable,
  };
  final startBinding = arrow.startBinding;
  final endBinding = arrow.endBinding;
  if (startBinding == null && endBinding == null) {
    return _emptyEngineResult;
  }

  final shouldUpdateStart =
      startBinding != null &&
      (changedBindableIds.isEmpty ||
          changedBindableIdSet.contains(startBinding.elementId));
  final shouldUpdateEnd =
      endBinding != null &&
      (changedBindableIds.isEmpty ||
          changedBindableIdSet.contains(endBinding.elementId));

  if (!shouldUpdateStart && !shouldUpdateEnd) {
    return _emptyEngineResult;
  }

  core.Point? nextStartPoint;
  core.Point? nextEndPoint;

  final startBindingToUpdate = shouldUpdateStart ? startBinding : null;
  if (startBindingToUpdate != null) {
    final startBindable = bindablesById[startBindingToUpdate.elementId];
    if (startBindable == null) {
      return recomputeCoreBindingsAfterBindableChange(
        arrow: arrow,
        bindables: bindables,
        context: context,
        changedBindableIds: changedBindableIds,
      );
    }
    final updatedStart = updateCoreBoundPoint(
      arrow: arrow,
      edge: 'startBinding',
      binding: startBindingToUpdate,
      bindable: startBindable,
      bindablesById: bindablesById,
    );
    if (updatedStart != null) {
      nextStartPoint = updatedStart;
    }
  }

  final endBindingToUpdate = shouldUpdateEnd ? endBinding : null;
  if (endBindingToUpdate != null) {
    final endBindable = bindablesById[endBindingToUpdate.elementId];
    if (endBindable == null) {
      return recomputeCoreBindingsAfterBindableChange(
        arrow: arrow,
        bindables: bindables,
        context: context,
        changedBindableIds: changedBindableIds,
      );
    }
    final updatedEnd = updateCoreBoundPoint(
      arrow: arrow,
      edge: 'endBinding',
      binding: endBindingToUpdate,
      bindable: endBindable,
      bindablesById: bindablesById,
    );
    if (updatedEnd != null) {
      nextEndPoint = updatedEnd;
    }
  }

  final resolvedStartPoint = nextStartPoint ?? arrow.points.first;
  final resolvedEndPoint = nextEndPoint ?? arrow.points.last;
  if (nextStartPoint == null && nextEndPoint == null) {
    return _emptyEngineResult;
  }

  final patch = updateCoreElbowArrowPatch(
    arrow: arrow,
    updates: <String, dynamic>{
      'points': <core.Point>[resolvedStartPoint, resolvedEndPoint],
    },
    bindables: bindables,
    context: context,
  );
  if (patch.isEmpty) {
    return _emptyEngineResult;
  }

  return core.EngineResult(
    arrowPatch: patch,
    bindablePatches: const <core.BindablePatch>[],
    suggestedBinding: null,
    events: const <core.ArrowEngineEvent>[],
  );
}

bool _isArrowAffectedByChangedBindables(
  core.ArrowState arrow,
  Set<String> changedBindableIds,
) {
  if (changedBindableIds.isEmpty) {
    return true;
  }
  final startBindableId = arrow.startBinding?.elementId;
  if (startBindableId != null && changedBindableIds.contains(startBindableId)) {
    return true;
  }
  final endBindableId = arrow.endBinding?.elementId;
  if (endBindableId != null && changedBindableIds.contains(endBindableId)) {
    return true;
  }
  return false;
}

Map<String, dynamic>? _buildPerArrowRecomputeOptions({
  required core.ArrowState arrow,
  required Set<String> changedBindableIds,
}) {
  final startBindableId = arrow.startBinding?.elementId;
  final endBindableId = arrow.endBinding?.elementId;
  if (startBindableId == null ||
      endBindableId == null ||
      startBindableId != endBindableId) {
    return null;
  }
  if (!changedBindableIds.contains(startBindableId)) {
    return null;
  }
  return const <String, dynamic>{'moveMidPointsWithElement': true};
}
