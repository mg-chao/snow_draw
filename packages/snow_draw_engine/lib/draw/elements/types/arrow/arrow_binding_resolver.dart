import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/element_style.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_geometry_adapter.dart';
import 'arrow_core_ops.dart';
import 'arrow_core_session.dart';
import 'arrow_data.dart';
import 'elbow/elbow_editing.dart';

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
    final normalizedUpdates = _normalizeUpdatedElbowArrows(
      baseElements: baseElements,
      updatedElements: updatedElements,
      patchedUpdates: updates,
      context: session.context,
    );
    final reorderedElementIds = session.reduceEventsToOrderedElementIds(
      result.events,
    );

    return ArrowBindingResolutionResult(
      updatedElements: normalizedUpdates,
      orderedElementIds: reorderedElementIds,
    );
  }
}

Map<String, ElementState> _normalizeUpdatedElbowArrows({
  required Map<String, ElementState> baseElements,
  required Map<String, ElementState> updatedElements,
  required Map<String, ElementState> patchedUpdates,
  required core.EngineContext context,
}) {
  if (patchedUpdates.isEmpty) {
    return patchedUpdates;
  }

  final overlay = <String, ElementState>{...updatedElements, ...patchedUpdates};
  final normalized = Map<String, ElementState>.of(patchedUpdates);
  final lookup = CombinedElementLookup(base: baseElements, overlay: overlay);

  for (final entry in patchedUpdates.entries) {
    final element = entry.value;
    final data = element.data;
    if (data is! ArrowData || data.arrowType != ArrowType.elbow) {
      continue;
    }

    final worldPoints = resolveArrowWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
    if (worldPoints.length < 2) {
      continue;
    }
    final localEndpoints = worldToLocalPoints(element, <DrawPoint>[
      worldPoints.first,
      worldPoints.last,
    ]);
    final normalizedEdit = computeElbowEdit(
      element: element,
      data: data,
      lookup: lookup,
      localPointsOverride: localEndpoints,
      engineContext: context,
      finalize: true,
    );
    final geometry = resolveArrowGeometryUpdate(
      localPoints: normalizedEdit.localPoints,
      oldRect: element.rect,
      rotation: element.rotation,
      arrowType: data.arrowType,
    );
    final transformedFixedSegments = transformFixedSegments(
      segments: normalizedEdit.fixedSegments,
      oldRect: element.rect,
      newRect: geometry.rect,
      rotation: element.rotation,
    );
    final normalizedData = data.copyWith(
      points: geometry.normalizedPoints,
      fixedSegments: transformedFixedSegments,
      startIsSpecial: normalizedEdit.startIsSpecial,
      endIsSpecial: normalizedEdit.endIsSpecial,
    );
    final normalizedElement = element.copyWith(
      rect: geometry.rect,
      data: normalizedData,
    );
    normalized[entry.key] = normalizedElement;
    overlay[entry.key] = normalizedElement;
  }

  return Map<String, ElementState>.unmodifiable(normalized);
}
