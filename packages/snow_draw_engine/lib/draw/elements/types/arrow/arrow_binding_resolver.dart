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

    final updates = _refreshBoundArrowsForChangedBindables(
      session: session,
      changedBindableIds: changedBindableIds,
    );
    final normalizedUpdates = _normalizeUpdatedElbowArrows(
      baseElements: baseElements,
      updatedElements: updatedElements,
      patchedUpdates: updates,
      context: session.context,
    );

    return ArrowBindingResolutionResult(
      updatedElements: normalizedUpdates,
      orderedElementIds: null,
    );
  }
}

Map<String, ElementState> _refreshBoundArrowsForChangedBindables({
  required ArrowCoreSession session,
  required Set<String> changedBindableIds,
}) {
  if (changedBindableIds.isEmpty || !session.hasArrows) {
    return const <String, ElementState>{};
  }

  final bindablesById = <String, core.BindableState>{
    for (final bindable in session.bindables) bindable.id: bindable,
  };
  final updated = <String, ElementState>{};
  for (final arrow in session.arrows) {
    final source = session.arrowSources[arrow.id];
    if (source == null) {
      continue;
    }
    final (element, data) = source;

    final startBinding = arrow.startBinding;
    final endBinding = arrow.endBinding;
    final touchesChangedBindable =
        (startBinding != null &&
            changedBindableIds.contains(startBinding.elementId)) ||
        (endBinding != null &&
            changedBindableIds.contains(endBinding.elementId));
    if (!touchesChangedBindable) {
      continue;
    }

    var nextArrow = arrow;
    var changed = false;
    final nextPoints = nextArrow.points
        .map((point) => <double>[point[0], point[1]])
        .toList(growable: true);

    void updateEdge({
      required core.ArrowEndpointSelector edge,
      required core.FixedPointBinding? binding,
      required int pointIndex,
    }) {
      if (binding == null) {
        return;
      }
      final bindable = bindablesById[binding.elementId];
      if (bindable == null) {
        return;
      }
      final nextPoint = updateCoreBoundPoint(
        arrow: nextArrow,
        edge: edge,
        binding: binding,
        bindable: bindable,
        bindablesById: bindablesById,
      );
      if (nextPoint == null) {
        return;
      }
      nextPoints[pointIndex] = <double>[nextPoint[0], nextPoint[1]];
      changed = true;
    }

    updateEdge(edge: 'startBinding', binding: startBinding, pointIndex: 0);
    updateEdge(
      edge: 'endBinding',
      binding: endBinding,
      pointIndex: nextPoints.length - 1,
    );

    if (!changed) {
      continue;
    }

    final normalized = core.normalizeArrowFromGlobalPoints(
      nextPoints
          .map(
            (point) => <double>[nextArrow.x + point[0], nextArrow.y + point[1]],
          )
          .toList(growable: false),
      session.context.maxCoordinate,
    );
    nextArrow = nextArrow.copyWith(
      x: normalized.x,
      y: normalized.y,
      width: normalized.width,
      height: normalized.height,
      points: normalized.points,
    );

    final patched = applyCoreArrowStateToElement(
      element: element,
      data: data,
      nextArrow: nextArrow,
    );
    if (patched != element) {
      updated[patched.id] = patched;
    }
  }

  return Map<String, ElementState>.unmodifiable(updated);
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
      startBinding: normalizedEdit.startBinding,
      endBinding: normalizedEdit.endBinding,
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
