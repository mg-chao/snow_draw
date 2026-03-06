import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_core_session.dart';

/// Resolves arrow bindings when bindable elements change position.
///
/// The resolver delegates recomputation to `snow_draw_arrow_core` and maps the
/// resulting patch back into engine element state.
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
      if (!_isArrowAffectedByChangedBindables(arrow, changedBindableIdSet)) {
        continue;
      }

      final result = recomputeCoreBindingsAfterBindableChange(
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
