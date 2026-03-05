import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/document_state.dart';
import '../../../models/element_state.dart';
import 'arrow_core_bridge.dart';
import 'arrow_core_ops.dart';
import 'arrow_engine_events.dart';
import 'arrow_like_data.dart';

/// Immutable arrow-core projection + context snapshot for a document view.
///
/// This consolidates common host integration work:
/// - projecting engine elements into arrow-core DTOs
/// - carrying a normalized engine context
/// - applying arrow patches back onto engine elements
/// - reducing arrow-core events into document ordering
@immutable
final class ArrowCoreAppliedResult {
  const ArrowCoreAppliedResult({
    required this.value,
    required this.orderedElementIds,
  });

  final core.ApplyEngineResultValue value;
  final List<String>? orderedElementIds;

  core.ArrowState get arrow => value.arrow;

  bool get orderChanged => orderedElementIds != null;
}

@immutable
final class ArrowCoreSession {
  const ArrowCoreSession({required this.projection, required this.context});

  factory ArrowCoreSession.fromElements(
    Iterable<ElementState> elements, {
    bool onlyBoundArrows = false,
    List<String>? orderedElementIds,
    core.EngineContext? context,
    double zoom = 1,
    bool isBindingEnabled = true,
    String bindMode = core.bindModeOrbit,
    double maxCoordinate = 1e6,
  }) => ArrowCoreSession(
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

  factory ArrowCoreSession.fromDocument(
    DocumentState document, {
    bool onlyBoundArrows = false,
    List<String>? orderedElementIds,
    core.EngineContext? context,
    double zoom = 1,
    bool isBindingEnabled = true,
    String bindMode = core.bindModeOrbit,
    double maxCoordinate = 1e6,
  }) {
    final arrowsWithSources = collectCoreArrowStatesWithSources(
      document.elements,
      onlyBoundArrows: onlyBoundArrows,
    );

    return ArrowCoreSession(
      projection: ArrowCoreDocumentProjection(
        bindables: document.arrowCoreBindables,
        bindableRelations: document.arrowCoreBindableRelations,
        arrows: arrowsWithSources.arrows,
        arrowSources: arrowsWithSources.sources,
        orderedElementIds: List<String>.unmodifiable(
          orderedElementIds ?? document.orderedElementIds,
        ),
        anchorElementIdsByBindableId:
            document.arrowCoreAnchorElementIdsByBindableId,
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
  Map<String, (ElementState, ArrowLikeData)> get arrowSources =>
      projection.arrowSources;
  List<String> get orderedElementIds => projection.orderedElementIds;
  Map<String, List<String>> get anchorElementIdsByBindableId =>
      projection.anchorElementIdsByBindableId;

  bool get hasArrows => projection.arrows.isNotEmpty;

  /// Applies arrow patches to projected arrow sources and returns changed
  /// engine elements keyed by id.
  Map<String, ElementState> applyArrowPatches(
    Iterable<core.ArrowStatePatchWithId> patches,
  ) => applyCoreArrowPatchesToSources(
    patches: patches,
    sources: projection.arrowSources,
  );

  /// Reduces arrow-core events into a reordered element-id list, if moved.
  List<String>? reduceEventsToOrderedElementIds(
    List<core.ArrowEngineEvent> events,
  ) => reduceArrowEngineEventsToOrderedIds(
    orderedElementIds: projection.orderedElementIds,
    events: events,
    anchorElementIdsByBindableId: projection.anchorElementIdsByBindableId,
  );

  /// Reorders [arrowId] above a hovered/suggested bindable when possible.
  ///
  /// Returns reordered ids only when a move occurred.
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

  /// Applies an arrow-core engine [result] to [arrow] with session projection.
  ///
  /// This ensures every caller uses the same relation graph, anchor mapping,
  /// and ordering baseline for result reduction.
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

  /// Applies [result] and resolves element ordering with hovered/suggested
  /// bindable fallback when the engine result does not emit reorder events.
  ///
  /// This keeps reorder behavior consistent across creation, drag, and focus
  /// flows.
  ArrowCoreAppliedResult applyEngineResultWithOrderFallback({
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
    if (nextOrderedElementIds == null) {
      final suggestedBindableId =
          hoveredBindableId ?? result.suggestedBinding?.bindableId;
      if (suggestedBindableId != null && suggestedBindableId.isNotEmpty) {
        nextOrderedElementIds = reorderArrowAboveHoveredBindable(
          arrowId: arrow.id,
          hoveredBindableId: suggestedBindableId,
          point: point,
          orderedElementIds: orderedElementIds,
          tolerance: tolerance,
        );
      }
    }

    return ArrowCoreAppliedResult(
      value: applied,
      orderedElementIds: nextOrderedElementIds,
    );
  }
}
