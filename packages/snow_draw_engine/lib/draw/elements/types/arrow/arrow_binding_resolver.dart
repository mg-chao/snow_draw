import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_core.dart' as core;
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
    final session = ArrowCoreSession.fromElements(
      lookup.values,
      onlyBoundArrows: true,
      orderedElementIds: orderedElementIds,
      context: engineContext,
    );
    if (!session.hasArrows) {
      return ArrowBindingResolutionResult.empty;
    }

    final result = recomputeCoreBindingsForChangedBindables(
      arrows: session.arrows,
      bindables: session.bindables,
      relations: session.bindableRelations,
      changedBindableIds: changedElementIds.toList(growable: false),
      context: session.context,
    );

    final updates = session.applyArrowPatches(result.arrowPatches);
    final reorderedElementIds = session.reduceEventsToOrderedElementIds(
      result.events,
    );

    return ArrowBindingResolutionResult(
      updatedElements: updates,
      orderedElementIds: reorderedElementIds,
    );
  }
}
