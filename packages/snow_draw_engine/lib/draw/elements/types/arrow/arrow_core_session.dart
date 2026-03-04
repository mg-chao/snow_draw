import 'package:meta/meta.dart';
import 'package:snow_draw_arrow_core/snow_draw_arrow_core.dart' as core;

import '../../../models/element_state.dart';
import 'arrow_core_bridge.dart';
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
}
