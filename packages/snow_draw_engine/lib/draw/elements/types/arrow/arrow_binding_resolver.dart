import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_core_bridge.dart';
import 'arrow_engine_events.dart';
import 'arrow_like_data.dart';

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
    final bindables = collectCoreBindables(lookup.values);
    final relations = collectCoreBindableRelations(lookup.values);
    final arrows = <core.ArrowState>[];
    final elementsByArrowId = <String, (ElementState, ArrowLikeData)>{};

    for (final element in lookup.values) {
      final data = element.data;
      if (data is! ArrowLikeData) {
        continue;
      }
      if (data.startBinding == null && data.endBinding == null) {
        continue;
      }

      arrows.add(toCoreArrowState(element: element, data: data));
      elementsByArrowId[element.id] = (element, data);
    }

    if (arrows.isEmpty) {
      return ArrowBindingResolutionResult.empty;
    }

    final result = core.recomputeBindingsForChangedBindables(<String, dynamic>{
      'arrows': arrows,
      'bindables': bindables,
      'relations': relations,
      'changedBindableIds': changedElementIds.toList(growable: false),
      'context': engineContext ?? core.defaultEngineContext,
    });

    final updates = <String, ElementState>{};
    for (final arrowPatch in result.arrowPatches) {
      final source = elementsByArrowId[arrowPatch.id];
      if (source == null) {
        continue;
      }
      final (element, data) = source;
      final nextElement = applyCoreArrowPatchToElement(
        element: element,
        data: data,
        patch: arrowPatch.patch,
      );
      if (nextElement != element) {
        updates[nextElement.id] = nextElement;
      }
    }

    final reorderedElementIds = reduceArrowEngineEventsToOrderedIds(
      orderedElementIds: orderedElementIds,
      events: result.events,
    );

    return ArrowBindingResolutionResult(
      updatedElements: updates,
      orderedElementIds: reorderedElementIds,
    );
  }
}
