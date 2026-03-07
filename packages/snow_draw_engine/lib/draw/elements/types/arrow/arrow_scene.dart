import 'package:meta/meta.dart';

import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../connector/connector_data.dart';
import 'arrow_binding.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';

/// Ordered bindable candidates projected for arrow algorithm queries.
///
/// The element and bindable collections mirror each other by id so callers can
/// switch between project-native and arrow-core state without rebuilding
/// lookups.
@immutable
final class ArrowBindableCandidates {
  factory ArrowBindableCandidates({
    required List<ElementState> elements,
    required List<core.BindableState> bindables,
  }) => ArrowBindableCandidates._(
    elements: elements,
    bindables: bindables,
    elementById: Map<String, ElementState>.unmodifiable({
      for (final element in elements) element.id: element,
    }),
    bindableById: Map<String, core.BindableState>.unmodifiable({
      for (final bindable in bindables) bindable.id: bindable,
    }),
  );

  static const empty = ArrowBindableCandidates._(
    elements: <ElementState>[],
    bindables: <core.BindableState>[],
    elementById: <String, ElementState>{},
    bindableById: <String, core.BindableState>{},
  );

  const ArrowBindableCandidates._({
    required this.elements,
    required this.bindables,
    required this.elementById,
    required this.bindableById,
  });

  final List<ElementState> elements;
  final List<core.BindableState> bindables;
  final Map<String, ElementState> elementById;
  final Map<String, core.BindableState> bindableById;

  bool get isEmpty => bindables.isEmpty;

  ElementState? elementForId(String id) => elementById[id];

  core.BindableState? bindableForId(String id) => bindableById[id];
}

/// Projects [elements] into ordered bindable candidates.
///
/// This keeps bindable projection consistent across create, preview, drag, and
/// reducer flows.
ArrowBindableCandidates projectArrowBindableCandidates({
  required Iterable<ElementState> elements,
  Map<String, core.BindableState>? bindablesById,
}) {
  final seenIds = <String>{};
  final projectedElements = <ElementState>[];
  final projectedBindables = <core.BindableState>[];

  for (final element in elements) {
    if (!seenIds.add(element.id)) {
      continue;
    }

    final bindable = bindablesById == null
        ? toCoreBindableState(element)
        : bindablesById[element.id];
    if (bindable == null) {
      continue;
    }

    projectedElements.add(element);
    projectedBindables.add(bindable);
  }

  if (projectedBindables.isEmpty) {
    return ArrowBindableCandidates.empty;
  }

  return ArrowBindableCandidates(
    elements: List<ElementState>.unmodifiable(projectedElements),
    bindables: List<core.BindableState>.unmodifiable(projectedBindables),
  );
}

/// Resolves bindable lookup candidates for arrow binding and focus routines.
///
/// The result always includes currently bound endpoint targets when provided
/// and can also include nearby spatial candidates around [worldPoint].
ArrowBindableCandidates resolveArrowBindableCandidates({
  required DocumentState document,
  required DrawPoint worldPoint,
  required double distance,
  ArrowBinding? preferredBinding,
  ArrowBinding? oppositeBinding,
  String? excludedElementId,
  bool includeNearby = true,
}) {
  final candidateIds = <String>{};
  if (preferredBinding != null) {
    candidateIds.add(preferredBinding.elementId);
  }
  if (oppositeBinding != null) {
    candidateIds.add(oppositeBinding.elementId);
  }

  if (includeNearby && distance > 0 && document.hasArrowBindableElements) {
    final nearbyBindables = document.queryArrowBindableElementsAtPointTopDown(
      worldPoint,
      distance,
      excludedElementId: excludedElementId,
      stopAtOpaque: true,
    );
    for (final element in nearbyBindables) {
      candidateIds.add(element.id);
    }
  }

  if (candidateIds.isEmpty) {
    return ArrowBindableCandidates.empty;
  }

  final candidateElements = <ElementState>[];
  for (final candidateId in document.orderedElementIds) {
    if (!candidateIds.contains(candidateId)) {
      continue;
    }
    final element = document.elementMap[candidateId];
    if (element == null) {
      continue;
    }
    candidateElements.add(element);
  }
  return projectArrowBindableCandidates(
    elements: candidateElements,
    bindablesById: document.arrowBindableStateById,
  );
}

/// Resolves bindables for endpoint drag and strategy routines.
///
/// When [allowNewBinding] is true, every bindable in document order is
/// available. Otherwise only already-bound targets stay available.
ArrowBindableCandidates resolveArrowBindableCandidatesForEndpointStrategy({
  required DocumentState document,
  required bool allowNewBinding,
  ArrowBinding? activeBinding,
  ArrowBinding? oppositeBinding,
  String? excludedElementId,
  List<String>? orderedElementIds,
}) {
  final hasOrderOverride =
      orderedElementIds != null && orderedElementIds.isNotEmpty;
  final orderedIds = hasOrderOverride
      ? orderedElementIds
      : document.orderedElementIds;
  final canReuseCachedBindableProjection =
      !hasOrderOverride ||
      _stringListEquals(orderedIds, document.orderedElementIds);

  if (allowNewBinding) {
    final allBindableElements = <ElementState>[];
    for (final elementId in orderedIds) {
      if (excludedElementId != null && elementId == excludedElementId) {
        continue;
      }
      if (!document.arrowBindableStateById.containsKey(elementId)) {
        continue;
      }
      final element = document.elementMap[elementId];
      if (element == null) {
        continue;
      }
      allBindableElements.add(element);
    }

    if (allBindableElements.isEmpty) {
      return ArrowBindableCandidates.empty;
    }

    if (canReuseCachedBindableProjection) {
      return projectArrowBindableCandidates(
        elements: allBindableElements,
        bindablesById: document.arrowBindableStateById,
      );
    }

    final bindablesById = <String, core.BindableState>{};
    for (var index = 0; index < orderedIds.length; index += 1) {
      final elementId = orderedIds[index];
      if (excludedElementId != null && elementId == excludedElementId) {
        continue;
      }
      if (!document.arrowBindableStateById.containsKey(elementId)) {
        continue;
      }
      final element = document.elementMap[elementId];
      if (element == null) {
        continue;
      }
      final bindable = toCoreBindableState(element, zIndex: index);
      if (bindable == null) {
        continue;
      }
      bindablesById[element.id] = bindable;
    }

    return projectArrowBindableCandidates(
      elements: allBindableElements,
      bindablesById: bindablesById,
    );
  }

  final boundIds = <String>{};
  final activeId = activeBinding?.elementId;
  if (activeId != null && activeId.isNotEmpty) {
    boundIds.add(activeId);
  }
  final oppositeId = oppositeBinding?.elementId;
  if (oppositeId != null && oppositeId.isNotEmpty) {
    boundIds.add(oppositeId);
  }
  if (boundIds.isEmpty) {
    return ArrowBindableCandidates.empty;
  }

  final boundElements = <ElementState>[];
  for (final elementId in orderedIds) {
    if (!boundIds.contains(elementId)) {
      continue;
    }
    if (excludedElementId != null && elementId == excludedElementId) {
      continue;
    }
    final element = document.elementMap[elementId];
    if (element == null) {
      continue;
    }
    boundElements.add(element);
  }

  if (boundElements.isEmpty) {
    return ArrowBindableCandidates.empty;
  }

  if (canReuseCachedBindableProjection) {
    return projectArrowBindableCandidates(
      elements: boundElements,
      bindablesById: document.arrowBindableStateById,
    );
  }

  final bindablesById = <String, core.BindableState>{};
  for (var index = 0; index < orderedIds.length; index += 1) {
    final elementId = orderedIds[index];
    if (!boundIds.contains(elementId)) {
      continue;
    }
    if (excludedElementId != null && elementId == excludedElementId) {
      continue;
    }
    final element = document.elementMap[elementId];
    if (element == null) {
      continue;
    }
    final bindable = toCoreBindableState(element, zIndex: index);
    if (bindable == null) {
      continue;
    }
    bindablesById[element.id] = bindable;
  }

  return projectArrowBindableCandidates(
    elements: boundElements,
    bindablesById: bindablesById,
  );
}

/// Result of applying arrow engine output against a projected scene.
@immutable
final class ArrowAppliedResult {
  const ArrowAppliedResult({
    required this.value,
    required this.orderedElementIds,
  });

  final core.ApplyEngineResultValue value;
  final List<String>? orderedElementIds;

  core.ArrowState get arrow => value.arrow;

  bool get orderChanged => orderedElementIds != null;
}

/// Immutable arrow scene snapshot used across create, drag, and reducer flows.
///
/// The scene packages projected bindables, projected arrows, and the normalized
/// arrow-core context so callers share one consistent view of the document.
@immutable
final class ArrowScene {
  const ArrowScene({required this.projection, required this.context});

  factory ArrowScene.fromElements(
    Iterable<ElementState> elements, {
    bool onlyBoundArrows = false,
    List<String>? orderedElementIds,
    core.EngineContext? context,
    double zoom = 1,
    bool isBindingEnabled = true,
    String bindMode = core.bindModeOrbit,
    double maxCoordinate = 1e6,
  }) => ArrowScene(
    projection: projectCoreDocument(
      elements,
      onlyBoundArrows: onlyBoundArrows,
      orderedElementIds: orderedElementIds,
    ),
    context:
        context ??
        buildCoreEngineContext(
          zoom: zoom,
          isBindingEnabled: isBindingEnabled,
          bindMode: bindMode,
          maxCoordinate: maxCoordinate,
        ),
  );

  factory ArrowScene.fromDocument(
    DocumentState document, {
    bool onlyBoundArrows = false,
    List<String>? orderedElementIds,
    core.EngineContext? context,
    double zoom = 1,
    bool isBindingEnabled = true,
    String bindMode = core.bindModeOrbit,
    double maxCoordinate = 1e6,
  }) {
    final hasOrderedOverride =
        orderedElementIds != null && orderedElementIds.isNotEmpty;
    final shouldReuseDocumentProjection =
        !hasOrderedOverride ||
        _stringListEquals(orderedElementIds, document.orderedElementIds);

    if (!shouldReuseDocumentProjection) {
      return ArrowScene(
        projection: projectCoreDocument(
          document.elements,
          onlyBoundArrows: onlyBoundArrows,
          orderedElementIds: orderedElementIds,
        ),
        context:
            context ??
            buildCoreEngineContext(
              zoom: zoom,
              isBindingEnabled: isBindingEnabled,
              bindMode: bindMode,
              maxCoordinate: maxCoordinate,
            ),
      );
    }

    final arrowsWithSources = collectCoreArrowStatesWithSources(
      document.elements,
      onlyBoundArrows: onlyBoundArrows,
    );

    return ArrowScene(
      projection: ArrowCoreDocumentProjection(
        bindables: document.arrowBindableStates,
        bindableRelations: document.arrowBindableRelations,
        arrows: arrowsWithSources.arrows,
        arrowSources: arrowsWithSources.sources,
        orderedElementIds: List<String>.unmodifiable(
          hasOrderedOverride ? orderedElementIds : document.orderedElementIds,
        ),
        anchorElementIdsByBindableId:
            document.arrowAnchorElementIdsByBindableId,
      ),
      context:
          context ??
          buildCoreEngineContext(
            zoom: zoom,
            isBindingEnabled: isBindingEnabled,
            bindMode: bindMode,
            maxCoordinate: maxCoordinate,
          ),
    );
  }

  final ArrowCoreDocumentProjection projection;
  final core.EngineContext context;

  List<core.BindableState> get bindables => projection.bindables;

  List<core.BindableRelationState> get bindableRelations =>
      projection.bindableRelations;

  List<core.ArrowState> get arrows => projection.arrows;

  Map<String, (ElementState, ConnectorData)> get arrowSources =>
      projection.arrowSources;

  List<String> get orderedElementIds => projection.orderedElementIds;

  Map<String, List<String>> get anchorElementIdsByBindableId =>
      projection.anchorElementIdsByBindableId;

  bool get hasArrows => projection.arrows.isNotEmpty;

  /// Applies arrow patches to projected sources and returns changed elements.
  Map<String, ElementState> applyArrowPatches(
    Iterable<core.ArrowStatePatchWithId> patches,
  ) => applyCoreArrowPatchesToSources(
    patches: patches,
    sources: projection.arrowSources,
  );

  /// Reduces arrow engine events into a reordered element-id list, if moved.
  List<String>? reduceEventsToOrderedElementIds(
    List<core.ArrowEngineEvent> events,
  ) => reduceArrowEventsToOrderedIds(
    orderedElementIds: projection.orderedElementIds,
    events: events,
    anchorElementIdsByBindableId: projection.anchorElementIdsByBindableId,
  );

  /// Reorders [arrowId] above a hovered or suggested bindable when possible.
  List<String>? reorderArrowAboveHoveredBindable({
    required String arrowId,
    String? hoveredBindableId,
    core.Point? point,
    List<String>? orderedElementIds,
    double? tolerance,
  }) {
    final reorder = reorderCoreArrowAboveHoveredBindable(
      orderedElementIds: orderedElementIds ?? projection.orderedElementIds,
      arrowId: arrowId,
      hoveredBindableId: hoveredBindableId,
      point: point,
      bindables: projection.bindables,
      tolerance: tolerance,
      anchorElementIdsByBindableId: projection.anchorElementIdsByBindableId,
    );
    return reorderedElementIdsFromCoreHoveredReorder(reorder);
  }

  /// Applies an engine [result] to [arrow] with this scene's relation graph.
  core.ApplyEngineResultValue applyEngineResult({
    required core.ArrowState arrow,
    required core.EngineResult result,
    List<String>? orderedElementIds,
  }) => applyCoreEngineResult(
    arrow: arrow,
    bindables: projection.bindableRelations,
    result: result,
    orderedElementIds: orderedElementIds ?? projection.orderedElementIds,
    anchorElementIdsByBindableId: projection.anchorElementIdsByBindableId,
  );

  /// Applies [result] and resolves ordering fallback when the engine omits one.
  ArrowAppliedResult applyEngineResultWithOrderFallback({
    required core.ArrowState arrow,
    required core.EngineResult result,
    String? hoveredBindableId,
    core.Point? point,
    List<String>? orderedElementIds,
    double? tolerance,
  }) {
    final applied = applyEngineResult(
      arrow: arrow,
      result: result,
      orderedElementIds: orderedElementIds,
    );

    var nextOrderedElementIds = reorderedElementIdsFromCoreResult(applied);
    if (nextOrderedElementIds == null && context.isBindingEnabled) {
      final explicitHoveredId =
          hoveredBindableId != null && hoveredBindableId.isNotEmpty
          ? hoveredBindableId
          : null;
      final suggestedBindableId =
          result.suggestedBinding?.bindableId ??
          result.suggestedBinding?.element.id;
      final suggestedId =
          suggestedBindableId != null && suggestedBindableId.isNotEmpty
          ? suggestedBindableId
          : null;
      final reorderTargetId = explicitHoveredId ?? suggestedId;

      if (reorderTargetId != null || point != null) {
        nextOrderedElementIds = reorderArrowAboveHoveredBindable(
          arrowId: arrow.id,
          hoveredBindableId: reorderTargetId,
          point: point,
          orderedElementIds: orderedElementIds,
          tolerance: tolerance,
        );
      }
    }

    return ArrowAppliedResult(
      value: applied,
      orderedElementIds: nextOrderedElementIds,
    );
  }
}

/// Reduces arrow engine events into an updated element ordering.
///
/// Returns `null` when no ordering change is required.
List<String>? reduceArrowEventsToOrderedIds({
  required List<String> orderedElementIds,
  required List<core.ArrowEngineEvent> events,
  Map<String, List<String>>? anchorElementIdsByBindableId,
}) {
  if (orderedElementIds.isEmpty || events.isEmpty) {
    return null;
  }

  final result = core.reduceArrowEngineEventsToOrder(
    core.ReduceArrowEngineEventsToOrderInput(
      orderedElementIds: orderedElementIds,
      events: events,
      anchorElementIdsByBindableId: anchorElementIdsByBindableId,
    ),
  );
  if (!result.moved ||
      _stringListEquals(result.orderedElementIds, orderedElementIds)) {
    return null;
  }

  return List<String>.unmodifiable(result.orderedElementIds);
}

bool _stringListEquals(List<String> left, List<String> right) {
  if (identical(left, right)) {
    return true;
  }
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
