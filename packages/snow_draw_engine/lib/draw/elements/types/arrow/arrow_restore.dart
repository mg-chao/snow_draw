import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_geometry.dart';
import 'arrow_like_data.dart';

/// Repairs arrow payloads restored from persisted snapshots.
///
/// This normalizes dangling endpoint bindings against [elements], then applies
/// elbow-specific restore fixes from `snow_draw_arrow_core`.
///
/// Returns [elements] unchanged when no repair is needed.
List<ElementState> repairArrowElementsOnRestore({
  required List<ElementState> elements,
  Map<String, ElementState>? existingElementsById,
  core.EngineContext engineContext = core.defaultEngineContext,
}) {
  if (elements.isEmpty) {
    return elements;
  }

  final bindables = collectCoreBindables(elements);
  final bindableById = {
    for (final bindable in bindables) bindable.id: bindable,
  };
  final existingBindables = existingElementsById == null
      ? null
      : collectCoreBindables(existingElementsById.values);

  var changed = false;
  final repaired = <ElementState>[];
  for (final element in elements) {
    final next = _repairArrowElementOnRestore(
      element: element,
      bindables: bindables,
      bindableById: bindableById,
      existingBindables: existingBindables,
      engineContext: engineContext,
    );
    if (next != element) {
      changed = true;
    }
    repaired.add(next);
  }

  if (!changed) {
    return elements;
  }
  return List<ElementState>.unmodifiable(repaired);
}

/// Builds world points for a directional two-point arrow path.
///
/// This delegates direction-aware endpoint placement to
/// `snow_draw_arrow_core`.
List<DrawPoint> createDirectionalArrowWorldPoints({
  required DrawRect startBounds,
  required DrawRect endBounds,
  required core.DirectionalLinkDirection direction,
  double padding = 6,
  double endpointDelta = 0.5,
}) {
  final directional = createCoreDirectionalLinkArrow(
    start: _toDirectionalBounds(startBounds),
    end: _toDirectionalBounds(endBounds),
    direction: direction,
    padding: padding,
  );

  final points = endpointDelta > 0
      ? offsetCoreArrowEndpointsForBindingOverlap(
          points: directional.points,
          delta: endpointDelta,
        )
      : directional.points;

  return List<DrawPoint>.unmodifiable([
    for (final point in points)
      DrawPoint(x: directional.x + point[0], y: directional.y + point[1]),
  ]);
}

/// Builds rect + normalized points for directional arrow initialization.
///
/// The output can be directly assigned to [ArrowLikeData.points] and
/// [ElementState.rect].
({DrawRect rect, List<DrawPoint> normalizedPoints})
createDirectionalArrowLayout({
  required DrawRect startBounds,
  required DrawRect endBounds,
  required core.DirectionalLinkDirection direction,
  ArrowType arrowType = ArrowType.straight,
  double padding = 6,
  double endpointDelta = 0.5,
}) {
  final worldPoints = createDirectionalArrowWorldPoints(
    startBounds: startBounds,
    endBounds: endBounds,
    direction: direction,
    padding: padding,
    endpointDelta: endpointDelta,
  );
  final rect = ArrowGeometry.calculatePathBounds(
    worldPoints: worldPoints,
    arrowType: arrowType,
  );
  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: worldPoints,
    rect: rect,
  );
  return (
    rect: rect,
    normalizedPoints: List<DrawPoint>.unmodifiable(normalizedPoints),
  );
}

ElementState _repairArrowElementOnRestore({
  required ElementState element,
  required List<core.BindableState> bindables,
  required Map<String, core.BindableState> bindableById,
  required List<core.BindableState>? existingBindables,
  required core.EngineContext engineContext,
}) {
  final data = element.data;
  if (data is! ArrowLikeData) {
    return element;
  }

  var workingElement = element;
  var workingData = data;

  final bindingRepaired = _repairBindingsOnRestore(
    element: workingElement,
    data: workingData,
    bindables: bindables,
    existingBindables: existingBindables,
  );
  if (bindingRepaired != null) {
    workingData = bindingRepaired;
    workingElement = workingElement.copyWith(data: bindingRepaired);
  }

  if (workingData.arrowType != ArrowType.elbow) {
    return workingElement;
  }

  final restorePatch = _resolveElbowRestorePatch(
    element: workingElement,
    data: workingData,
    bindables: bindables,
    bindableById: bindableById,
    engineContext: engineContext,
  );
  if (restorePatch == null || restorePatch.isEmpty) {
    return workingElement;
  }

  return applyCoreArrowPatchToElement(
    element: workingElement,
    data: workingData,
    patch: restorePatch,
  );
}

ArrowLikeData? _repairBindingsOnRestore({
  required ElementState element,
  required ArrowLikeData data,
  required List<core.BindableState> bindables,
  required List<core.BindableState>? existingBindables,
}) {
  final arrow = toCoreArrowState(element: element, data: data);
  final repairedStart = fromCoreBinding(
    repairCoreBindingOnRestore(
      binding: toCoreBinding(data.startBinding),
      bindables: bindables,
      arrow: arrow,
      edge: core.arrowEndpointStart,
      existingBindables: existingBindables,
    ),
  );
  final repairedEnd = fromCoreBinding(
    repairCoreBindingOnRestore(
      binding: toCoreBinding(data.endBinding),
      bindables: bindables,
      arrow: arrow,
      edge: core.arrowEndpointEnd,
      existingBindables: existingBindables,
    ),
  );

  if (repairedStart == data.startBinding && repairedEnd == data.endBinding) {
    return null;
  }
  return data.copyWith(startBinding: repairedStart, endBinding: repairedEnd);
}

core.ArrowPatch? _resolveElbowRestorePatch({
  required ElementState element,
  required ArrowLikeData data,
  required List<core.BindableState> bindables,
  required Map<String, core.BindableState> bindableById,
  required core.EngineContext engineContext,
}) {
  final arrow = toCoreArrowState(element: element, data: data);
  final invalidUnboundPatch = repairCoreInvalidUnboundElbowArrowOnRestore(
    arrow: arrow,
    bindables: bindables,
    context: engineContext,
  );
  if (invalidUnboundPatch != null && invalidUnboundPatch.isNotEmpty) {
    return invalidUnboundPatch;
  }

  final startBinding = data.startBinding;
  final endBinding = data.endBinding;
  if (startBinding == null ||
      endBinding == null ||
      startBinding.elementId != endBinding.elementId) {
    return null;
  }

  final bindable = bindableById[startBinding.elementId];
  if (bindable == null) {
    return null;
  }
  return repairCoreSelfBoundExtremeElbowArrowOnRestore(
    arrow: arrow,
    bindable: bindable,
    maxCoordinate: engineContext.maxCoordinate,
  );
}

core.DirectionalLinkBounds _toDirectionalBounds(DrawRect rect) =>
    core.DirectionalLinkBounds(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: rect.height,
    );
