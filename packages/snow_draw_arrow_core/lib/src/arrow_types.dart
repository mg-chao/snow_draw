import 'dart:math' as math;

typedef Point = List<double>;
typedef Bounds = List<double>;

typedef BindMode = String;
const String bindModeInside = 'inside';
const String bindModeOrbit = 'orbit';
const String bindModeSkip = 'skip';

typedef ArrowEndpointEdge = String;
typedef ArrowEndpointBindingField = String;
typedef ArrowEndpointSelector = String;

const String arrowEndpointStart = 'start';
const String arrowEndpointEnd = 'end';

String normalizeArrowEndpointEdge(ArrowEndpointSelector edge) =>
    edge == 'start' || edge == 'startBinding' ? 'start' : 'end';

const Map<String, int> bindableRoundness = {
  'LEGACY': 1,
  'PROPORTIONAL': 2,
  'ADAPTIVE': 3,
};

typedef BindableRoundnessType = Object;

class BindableRoundness {
  const BindableRoundness({required this.type, this.value});

  final BindableRoundnessType type;
  final double? value;
}

typedef Arrowhead = String;
typedef ArrowStrokeStyle = String;
typedef ArrowheadDashMode = String;
typedef ArrowheadFillMode = String;
typedef CanonicalBindableShape = String;
typedef BindableShape = String;

String canonicalizeBindableShape(BindableShape shape) {
  switch (shape) {
    case 'rect':
      return 'rectangle';
    case 'circle':
      return 'ellipse';
    case 'rhombus':
      return 'diamond';
    default:
      return shape;
  }
}

class CurvePathOp {
  const CurvePathOp({required this.op, required this.data});

  final String op;
  final List<double> data;
}

typedef ArrowheadPoints = List<double>;

class FixedPointBinding {
  const FixedPointBinding({
    required this.elementId,
    required this.fixedPoint,
    required this.mode,
  });

  final String elementId;
  final Point fixedPoint;
  final BindMode mode;

  FixedPointBinding copyWith({
    String? elementId,
    Point? fixedPoint,
    BindMode? mode,
  }) => FixedPointBinding(
    elementId: elementId ?? this.elementId,
    fixedPoint: fixedPoint ?? this.fixedPoint,
    mode: mode ?? this.mode,
  );
}

class FixedSegment {
  const FixedSegment({
    required this.start,
    required this.end,
    required this.index,
  });

  final Point start;
  final Point end;
  final int index;

  FixedSegment copyWith({Point? start, Point? end, int? index}) => FixedSegment(
    start: start ?? this.start,
    end: end ?? this.end,
    index: index ?? this.index,
  );
}

class BindableState {
  const BindableState({
    required this.id,
    required this.shape,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.angle,
    required this.strokeWidth,
    this.roundness,
    this.zIndex,
    this.backgroundOpaque,
    this.bindingEnabled,
    this.interiorHitEnabled,
    this.visibilityBounds,
  });

  final String id;
  final BindableShape shape;
  final double x;
  final double y;
  final double width;
  final double height;
  final double angle;
  final double strokeWidth;
  final BindableRoundness? roundness;
  final double? zIndex;
  final bool? backgroundOpaque;
  final bool? bindingEnabled;
  final bool? interiorHitEnabled;
  final Bounds? visibilityBounds;

  BindableState copyWith({
    String? id,
    BindableShape? shape,
    double? x,
    double? y,
    double? width,
    double? height,
    double? angle,
    double? strokeWidth,
    BindableRoundness? roundness,
    double? zIndex,
    bool? backgroundOpaque,
    bool? bindingEnabled,
    bool? interiorHitEnabled,
    Bounds? visibilityBounds,
    bool setVisibilityBounds = false,
  }) => BindableState(
    id: id ?? this.id,
    shape: shape ?? this.shape,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    angle: angle ?? this.angle,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    roundness: roundness ?? this.roundness,
    zIndex: zIndex ?? this.zIndex,
    backgroundOpaque: backgroundOpaque ?? this.backgroundOpaque,
    bindingEnabled: bindingEnabled ?? this.bindingEnabled,
    interiorHitEnabled: interiorHitEnabled ?? this.interiorHitEnabled,
    visibilityBounds: setVisibilityBounds
        ? visibilityBounds
        : this.visibilityBounds,
  );
}

class ArrowState {
  const ArrowState({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.points,
    required this.startBinding,
    required this.endBinding,
    required this.startArrowhead,
    required this.endArrowhead,
    required this.elbowed,
    required this.fixedSegments,
    required this.startIsSpecial,
    required this.endIsSpecial,
  });

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final List<Point> points;
  final FixedPointBinding? startBinding;
  final FixedPointBinding? endBinding;
  final Arrowhead? startArrowhead;
  final Arrowhead? endArrowhead;
  final bool elbowed;
  final List<FixedSegment>? fixedSegments;
  final bool? startIsSpecial;
  final bool? endIsSpecial;

  ArrowState copyWith({
    String? id,
    double? x,
    double? y,
    double? width,
    double? height,
    List<Point>? points,
    FixedPointBinding? startBinding,
    bool setStartBinding = false,
    FixedPointBinding? endBinding,
    bool setEndBinding = false,
    Arrowhead? startArrowhead,
    bool setStartArrowhead = false,
    Arrowhead? endArrowhead,
    bool setEndArrowhead = false,
    bool? elbowed,
    List<FixedSegment>? fixedSegments,
    bool setFixedSegments = false,
    bool? startIsSpecial,
    bool setStartIsSpecial = false,
    bool? endIsSpecial,
    bool setEndIsSpecial = false,
  }) => ArrowState(
    id: id ?? this.id,
    x: x ?? this.x,
    y: y ?? this.y,
    width: width ?? this.width,
    height: height ?? this.height,
    points: points ?? this.points,
    startBinding: setStartBinding ? startBinding : this.startBinding,
    endBinding: setEndBinding ? endBinding : this.endBinding,
    startArrowhead: setStartArrowhead ? startArrowhead : this.startArrowhead,
    endArrowhead: setEndArrowhead ? endArrowhead : this.endArrowhead,
    elbowed: elbowed ?? this.elbowed,
    fixedSegments: setFixedSegments ? fixedSegments : this.fixedSegments,
    startIsSpecial: setStartIsSpecial ? startIsSpecial : this.startIsSpecial,
    endIsSpecial: setEndIsSpecial ? endIsSpecial : this.endIsSpecial,
  );
}

class EngineContext {
  const EngineContext({
    required this.zoom,
    required this.isBindingEnabled,
    required this.bindMode,
    required this.maxCoordinate,
  });

  final double zoom;
  final bool isBindingEnabled;
  final BindMode bindMode;
  final double maxCoordinate;
}

typedef ArrowPatch = Map<String, dynamic>;

class BindablePatch {
  const BindablePatch({
    required this.id,
    this.addBoundArrowId,
    this.removeBoundArrowId,
  });

  final String id;
  final String? addBoundArrowId;
  final String? removeBoundArrowId;
}

class ArrowBindingState {
  const ArrowBindingState({
    required this.id,
    required this.startBinding,
    required this.endBinding,
  });

  final String id;
  final FixedPointBinding? startBinding;
  final FixedPointBinding? endBinding;
}

typedef ArrowBindingStatePatch = Map<String, dynamic>;

class BindableRelationState {
  const BindableRelationState({required this.id, required this.boundArrowIds});

  final String id;
  final List<String> boundArrowIds;
}

class BindableRelationPatch {
  const BindableRelationPatch({required this.id, required this.boundArrowIds});

  final String id;
  final List<String> boundArrowIds;
}

class DeriveBindableRelationPatchesForBindingChangeInput {
  const DeriveBindableRelationPatchesForBindingChangeInput({
    required this.arrowId,
    required this.previous,
    required this.next,
    required this.bindables,
  });

  final String arrowId;
  final ArrowBindingState previous;
  final ArrowBindingState next;
  final List<BindableRelationState> bindables;
}

class IdMapEntry {
  const IdMapEntry({required this.from, required this.to});

  final String from;
  final String to;
}

typedef IdMapRecord = Map<String, String>;
typedef IdMapInput = Object;

class ArrowStatePatchWithId {
  const ArrowStatePatchWithId({required this.id, required this.patch});

  final String id;
  final ArrowPatch patch;
}

typedef LifecycleSyncBaseInput = Map<String, dynamic>;
typedef SyncBindingsAfterDuplicationInput = Map<String, dynamic>;
typedef SyncBindingsAfterDeletionInput = Map<String, dynamic>;
typedef SyncBindingsAfterBindablePruneInput = Map<String, dynamic>;

class LifecycleSyncResult {
  const LifecycleSyncResult({
    required this.arrows,
    required this.bindables,
    required this.arrowPatches,
    required this.relationPatches,
    required this.events,
  });

  final List<ArrowState> arrows;
  final List<BindableRelationState> bindables;
  final List<ArrowStatePatchWithId> arrowPatches;
  final List<BindableRelationPatch> relationPatches;
  final List<ArrowEngineEvent> events;
}

typedef BindableLookupRecord = Map<String, BindableState>;
typedef BindableLookupInput = Object;

class SuggestedBinding {
  const SuggestedBinding({
    this.bindableId,
    required this.element,
    this.midPoint,
  });

  final String? bindableId;
  final BindableState element;
  final Point? midPoint;
}

sealed class ArrowEngineEvent {
  const ArrowEngineEvent();

  String get type;
}

class ReorderArrowEvent extends ArrowEngineEvent {
  const ReorderArrowEvent({required this.arrowId, required this.bindableId});

  final String arrowId;
  final String bindableId;

  @override
  String get type => 'reorder-arrow';
}

class BindingBrokenEvent extends ArrowEngineEvent {
  const BindingBrokenEvent({required this.arrowId, required this.edge});

  final String arrowId;
  final ArrowEndpointEdge edge;

  @override
  String get type => 'binding-broken';
}

class EngineResult {
  const EngineResult({
    required this.arrowPatch,
    required this.bindablePatches,
    required this.suggestedBinding,
    required this.events,
  });

  final ArrowPatch arrowPatch;
  final List<BindablePatch> bindablePatches;
  final SuggestedBinding? suggestedBinding;
  final List<ArrowEngineEvent> events;
}

typedef AnchorElementIdsLookupRecord = Map<String, List<String>>;
typedef AnchorElementIdsLookupInput = Object;

class ReduceArrowEngineEventsToOrderInput {
  const ReduceArrowEngineEventsToOrderInput({
    required this.orderedElementIds,
    required this.events,
    this.anchorElementIdsByBindableId,
  });

  final List<String> orderedElementIds;
  final List<ArrowEngineEvent> events;
  final AnchorElementIdsLookupInput? anchorElementIdsByBindableId;
}

class ReduceArrowEngineEventsToOrderResult {
  const ReduceArrowEngineEventsToOrderResult({
    required this.orderedElementIds,
    required this.moved,
    required this.reorderOperations,
    required this.bindingBrokenEvents,
  });

  final List<String> orderedElementIds;
  final bool moved;
  final List<ReorderArrowAboveElementsResult> reorderOperations;
  final List<BindingBrokenEvent> bindingBrokenEvents;
}

class ApplyEngineResultInput {
  const ApplyEngineResultInput({
    required this.arrow,
    required this.bindables,
    required this.result,
    this.orderedElementIds,
    this.anchorElementIdsByBindableId,
  });

  final ArrowState arrow;
  final List<BindableRelationState> bindables;
  final EngineResult result;
  final List<String>? orderedElementIds;
  final AnchorElementIdsLookupInput? anchorElementIdsByBindableId;
}

class ApplyEngineResultValue {
  const ApplyEngineResultValue({
    required this.arrow,
    required this.bindables,
    required this.relationPatches,
    this.orderedElementIds,
    this.orderChanged,
    this.reorderOperations,
    this.bindingBrokenEvents,
  });

  final ArrowState arrow;
  final List<BindableRelationState> bindables;
  final List<BindableRelationPatch> relationPatches;
  final List<String>? orderedElementIds;
  final bool? orderChanged;
  final List<ReorderArrowAboveElementsResult>? reorderOperations;
  final List<BindingBrokenEvent>? bindingBrokenEvents;
}

class ValidationReport {
  const ValidationReport({required this.valid, required this.violations});

  final bool valid;
  final List<String> violations;
}

class EndpointBindingStrategy {
  const EndpointBindingStrategy({
    this.mode,
    this.bindableId,
    this.element,
    this.focusPoint,
  });

  final BindMode? mode;
  final String? bindableId;
  final BindableState? element;
  final Point? focusPoint;
}

class PointUpdate {
  const PointUpdate({required this.index, required this.point});

  final int index;
  final Point point;
}

typedef PointUpdatesRecord = Map<int, Point>;
typedef PointUpdates = Object;

typedef ComputeEndpointDragInput = Map<String, dynamic>;
typedef RefreshEndpointBindingInput = Map<String, dynamic>;
typedef PruneArrowBindingsInput = Map<String, dynamic>;
typedef RecomputeAfterBindableChangeInput = Map<String, dynamic>;
typedef RecomputeBindingsForChangedBindablesInput = Map<String, dynamic>;

class RecomputeBindingsForChangedBindablesResult {
  const RecomputeBindingsForChangedBindablesResult({
    required this.arrows,
    required this.bindables,
    required this.arrowPatches,
    required this.relationPatches,
    required this.events,
  });

  final List<ArrowState> arrows;
  final List<BindableRelationState> bindables;
  final List<ArrowStatePatchWithId> arrowPatches;
  final List<BindableRelationPatch> relationPatches;
  final List<ArrowEngineEvent> events;
}

typedef RecomputeElbowInput = Map<String, dynamic>;

typedef ElbowUpdatePatch = Map<String, dynamic>;
typedef UpdateElbowArrowInput = Map<String, dynamic>;
typedef ComputeElbowResizePatchInput = Map<String, dynamic>;
typedef MoveFixedSegmentToPointInput = Map<String, dynamic>;

class MoveFixedSegmentToPointResult {
  const MoveFixedSegmentToPointResult({
    required this.patch,
    required this.activeSegmentIndex,
    required this.activeSegmentMidPoint,
  });

  final ArrowPatch patch;
  final int? activeSegmentIndex;
  final Point? activeSegmentMidPoint;
}

typedef RepairBindingOnRestoreInput = Map<String, dynamic>;
typedef RepairInvalidUnboundElbowArrowOnRestoreInput = Map<String, dynamic>;
typedef RepairSelfBoundExtremeElbowArrowOnRestoreInput = Map<String, dynamic>;

class FocusPointDescriptor {
  const FocusPointDescriptor({
    required this.edge,
    required this.point,
    required this.binding,
  });

  final ArrowEndpointEdge edge;
  final Point point;
  final FixedPointBinding binding;
}

typedef ListVisibleFocusPointsInput = Map<String, dynamic>;
typedef PickFocusPointInput = Map<String, dynamic>;
typedef PickFocusPointWithOffsetInput = Map<String, dynamic>;

class FocusPointHit {
  const FocusPointHit({required this.edge, required this.pointerOffset});

  final ArrowEndpointEdge? edge;
  final Point pointerOffset;
}

typedef ResizeHandleDirection = Object;
typedef ResizeArrowDirection = String;

typedef ComputeFocusPointDragInput = Map<String, dynamic>;
typedef FinalizeFocusPointDragInput = Map<String, dynamic>;

class ReorderArrowAboveElementsInput {
  const ReorderArrowAboveElementsInput({
    required this.orderedElementIds,
    required this.arrowId,
    required this.anchorElementIds,
  });

  final List<String> orderedElementIds;
  final String arrowId;
  final List<String> anchorElementIds;
}

class ReorderArrowAboveElementsResult {
  const ReorderArrowAboveElementsResult({
    required this.orderedElementIds,
    required this.moved,
    required this.fromIndex,
    required this.toIndex,
  });

  final List<String> orderedElementIds;
  final bool moved;
  final int fromIndex;
  final int toIndex;
}

class ReorderArrowAboveHoveredBindableInput {
  const ReorderArrowAboveHoveredBindableInput({
    required this.orderedElementIds,
    required this.arrowId,
    this.hoveredBindableId,
    this.point,
    this.bindables,
    this.tolerance,
    this.anchorElementIdsByBindableId,
  });

  final List<String> orderedElementIds;
  final String arrowId;
  final String? hoveredBindableId;
  final Point? point;
  final List<BindableState>? bindables;
  final double? tolerance;
  final AnchorElementIdsLookupInput? anchorElementIdsByBindableId;
}

class ReorderArrowAboveHoveredBindableResult
    extends ReorderArrowAboveElementsResult {
  const ReorderArrowAboveHoveredBindableResult({
    required super.orderedElementIds,
    required super.moved,
    required super.fromIndex,
    required super.toIndex,
    required this.hoveredBindableId,
    required this.anchorElementIds,
  });

  final String? hoveredBindableId;
  final List<String> anchorElementIds;
}

const EngineContext defaultEngineContext = EngineContext(
  zoom: 1,
  isBindingEnabled: true,
  bindMode: bindModeOrbit,
  maxCoordinate: 1e6,
);

EngineContext normalizeEngineContext(Map<String, dynamic>? context) {
  final zoom = context?['zoom'];
  final isBindingEnabled = context?['isBindingEnabled'];
  final bindMode = context?['bindMode'];
  final maxCoordinate = context?['maxCoordinate'];

  final normalizedZoom = zoom is num && zoom.isFinite
      ? zoom.toDouble()
      : defaultEngineContext.zoom;
  final normalizedBinding = isBindingEnabled is bool
      ? isBindingEnabled
      : defaultEngineContext.isBindingEnabled;
  final normalizedMode =
      bindMode == bindModeInside ||
          bindMode == bindModeOrbit ||
          bindMode == bindModeSkip
      ? bindMode as String
      : defaultEngineContext.bindMode;
  final normalizedMaxCoordinate = maxCoordinate is num && maxCoordinate.isFinite
      ? maxCoordinate.toDouble()
      : defaultEngineContext.maxCoordinate;

  return EngineContext(
    zoom: normalizedZoom,
    isBindingEnabled: normalizedBinding,
    bindMode: normalizedMode,
    maxCoordinate: normalizedMaxCoordinate,
  );
}

BindableState normalizeBindableState(BindableState bindable) {
  Bounds? normalizedVisibilityBounds;
  final visibilityBounds = bindable.visibilityBounds;
  if (visibilityBounds == null) {
    normalizedVisibilityBounds = null;
  } else if (visibilityBounds.length == 4 &&
      visibilityBounds.every((value) => value.isFinite)) {
    normalizedVisibilityBounds = [
      visibilityBounds[0],
      visibilityBounds[1],
      visibilityBounds[2],
      visibilityBounds[3],
    ];
  }

  return bindable.copyWith(
    shape: canonicalizeBindableShape(bindable.shape),
    backgroundOpaque: bindable.backgroundOpaque ?? true,
    bindingEnabled: bindable.bindingEnabled ?? true,
    interiorHitEnabled: bindable.interiorHitEnabled ?? true,
    visibilityBounds: normalizedVisibilityBounds,
    setVisibilityBounds:
        normalizedVisibilityBounds != null || bindable.visibilityBounds == null,
  );
}

List<BindableState> normalizeBindableStates(List<BindableState> bindables) =>
    bindables.map(normalizeBindableState).toList(growable: false);

bool isFiniteNum(Object? value) => value is num && value.isFinite;

double clampNum(double value, double min, double max) =>
    math.max(min, math.min(max, value));
