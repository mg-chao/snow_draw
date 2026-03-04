import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import 'arrow_binding.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_core_session.dart';
import 'arrow_like_data.dart';

/// Endpoint identifier for arrow focus-point interactions.
enum ArrowFocusEndpoint { start, end }

/// Visible focus-point descriptor projected into engine types.
@immutable
final class ArrowFocusPoint {
  const ArrowFocusPoint({
    required this.endpoint,
    required this.position,
    required this.binding,
  });

  final ArrowFocusEndpoint endpoint;
  final DrawPoint position;
  final ArrowBinding binding;
}

/// Focus-point hit descriptor including pointer offset.
@immutable
final class ArrowFocusHit {
  const ArrowFocusHit({required this.endpoint, required this.pointerOffset});

  final ArrowFocusEndpoint? endpoint;
  final DrawPoint pointerOffset;
}

/// Result of dragging an arrow focus point.
@immutable
final class ArrowFocusDragResult {
  const ArrowFocusDragResult({
    required this.element,
    required this.elementChanged,
    required this.bindablePatches,
    this.orderedElementIds,
    this.suggestedBindableId,
  });

  final ElementState element;
  final bool elementChanged;
  final List<core.BindablePatch> bindablePatches;
  final List<String>? orderedElementIds;
  final String? suggestedBindableId;

  bool get hasChanges =>
      elementChanged || bindablePatches.isNotEmpty || orderedElementIds != null;
}

/// Result of finalizing a focus-point drag interaction.
@immutable
final class ArrowFocusFinalizeResult {
  const ArrowFocusFinalizeResult({required this.bindablePatches});

  final List<core.BindablePatch> bindablePatches;

  bool get hasChanges => bindablePatches.isNotEmpty;
}

/// Lists visible focus points for a non-elbow arrow.
///
/// Focus points are only visible when bindings are enabled and the endpoint/
/// focus geometry is separable at the current zoom.
List<ArrowFocusPoint> listVisibleArrowFocusPoints({
  required ElementState element,
  required ArrowLikeData data,
  required Iterable<ElementState> elements,
  core.EngineContext? engineContext,
  bool ignoreOverlap = false,
}) {
  final arrow = toCoreArrowState(element: element, data: data);
  final session = ArrowCoreSession.fromElements(
    elements,
    context: engineContext,
  );
  final bindables = session.bindables;
  if (bindables.isEmpty) {
    return const <ArrowFocusPoint>[];
  }

  final focusPoints = listCoreVisibleFocusPoints(
    arrow: arrow,
    bindables: bindables,
    context: session.context,
    ignoreOverlap: ignoreOverlap,
  );
  if (focusPoints.isEmpty) {
    return const <ArrowFocusPoint>[];
  }

  final converted = <ArrowFocusPoint>[];
  for (final focusPoint in focusPoints) {
    final binding = fromCoreBinding(focusPoint.binding);
    if (binding == null) {
      continue;
    }
    converted.add(
      ArrowFocusPoint(
        endpoint: _endpointFromCore(focusPoint.edge),
        position: toDrawPoint(focusPoint.point),
        binding: binding,
      ),
    );
  }

  return List<ArrowFocusPoint>.unmodifiable(converted);
}

/// Picks a focus-point endpoint under [pointer], if any.
ArrowFocusEndpoint? pickArrowFocusPoint({
  required ElementState element,
  required ArrowLikeData data,
  required Iterable<ElementState> elements,
  required DrawPoint pointer,
  core.EngineContext? engineContext,
  bool ignoreOverlap = false,
}) {
  final arrow = toCoreArrowState(element: element, data: data);
  final session = ArrowCoreSession.fromElements(
    elements,
    context: engineContext,
  );
  final bindables = session.bindables;
  if (bindables.isEmpty) {
    return null;
  }

  final edge = pickCoreFocusPoint(
    arrow: arrow,
    pointer: toCorePoint(pointer),
    bindables: bindables,
    context: session.context,
    ignoreOverlap: ignoreOverlap,
  );
  if (edge == null) {
    return null;
  }

  return _endpointFromCore(edge);
}

/// Picks a focus-point endpoint under [pointer] and returns pointer offset.
ArrowFocusHit pickArrowFocusPointWithOffset({
  required ElementState element,
  required ArrowLikeData data,
  required Iterable<ElementState> elements,
  required DrawPoint pointer,
  core.EngineContext? engineContext,
  bool ignoreOverlap = false,
}) {
  final arrow = toCoreArrowState(element: element, data: data);
  final session = ArrowCoreSession.fromElements(
    elements,
    context: engineContext,
  );
  final bindables = session.bindables;
  if (bindables.isEmpty) {
    return const ArrowFocusHit(endpoint: null, pointerOffset: DrawPoint.zero);
  }

  final hit = pickCoreFocusPointWithOffset(
    arrow: arrow,
    pointer: toCorePoint(pointer),
    bindables: bindables,
    context: session.context,
    ignoreOverlap: ignoreOverlap,
  );
  return ArrowFocusHit(
    endpoint: hit.edge == null ? null : _endpointFromCore(hit.edge!),
    pointerOffset: toDrawPoint(hit.pointerOffset),
  );
}

/// Computes and applies a focus-point drag patch to [element].
ArrowFocusDragResult dragArrowFocusPoint({
  required ElementState element,
  required ArrowLikeData data,
  required Map<String, ElementState> elementsById,
  required ArrowFocusEndpoint draggedEndpoint,
  required DrawPoint pointer,
  core.EngineContext? engineContext,
  bool switchToInsideBinding = false,
  double? gridSize,
  List<String>? orderedElementIds,
}) {
  final arrow = toCoreArrowState(element: element, data: data);
  final session = ArrowCoreSession.fromElements(
    elementsById.values,
    orderedElementIds: orderedElementIds,
    context: engineContext,
  );
  final bindables = session.bindables;
  final result = computeCoreFocusPointDrag(
    arrow: arrow,
    draggedEdge: _endpointToCore(draggedEndpoint),
    pointer: toCorePoint(pointer),
    bindables: bindables,
    context: session.context,
    switchToInsideBinding: switchToInsideBinding,
    gridSize: gridSize,
  );

  final applied = applyCoreEngineResult(
    arrow: arrow,
    bindables: session.bindableRelations,
    result: result,
    orderedElementIds: orderedElementIds,
    anchorElementIdsByBindableId: session.anchorElementIdsByBindableId,
  );
  final reorderedElementIds = reorderedElementIdsFromCoreResult(applied);
  final patchedElement = applied.arrow == arrow
      ? element
      : applyCoreArrowStateToElement(
          element: element,
          data: data,
          nextArrow: applied.arrow,
        );

  return ArrowFocusDragResult(
    element: patchedElement,
    elementChanged: patchedElement != element,
    bindablePatches: List<core.BindablePatch>.unmodifiable(
      result.bindablePatches,
    ),
    orderedElementIds: reorderedElementIds,
    suggestedBindableId: result.suggestedBinding?.bindableId,
  );
}

/// Finalizes focus-point drag by deriving bindable relation patches.
ArrowFocusFinalizeResult finalizeArrowFocusPointDrag({
  required ElementState element,
  required ArrowLikeData data,
  required Iterable<ElementState> elements,
}) {
  final result = finalizeCoreFocusPointDrag(
    arrowId: element.id,
    startBinding: toCoreBinding(data.startBinding),
    endBinding: toCoreBinding(data.endBinding),
    bindables: collectCoreBindableRelations(elements),
  );

  return ArrowFocusFinalizeResult(
    bindablePatches: List<core.BindablePatch>.unmodifiable(
      result.bindablePatches,
    ),
  );
}

ArrowFocusEndpoint _endpointFromCore(core.ArrowEndpointEdge edge) =>
    edge == core.arrowEndpointEnd
    ? ArrowFocusEndpoint.end
    : ArrowFocusEndpoint.start;

core.ArrowEndpointEdge _endpointToCore(ArrowFocusEndpoint endpoint) =>
    endpoint == ArrowFocusEndpoint.end
    ? core.arrowEndpointEnd
    : core.arrowEndpointStart;
