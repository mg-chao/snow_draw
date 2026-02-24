part of 'elbow_editing.dart';

@immutable
final class _FixedSegmentPathResult {
  const _FixedSegmentPathResult({
    required this.points,
    required this.fixedSegments,
  });

  final List<DrawPoint> points;
  final List<ElbowFixedSegment> fixedSegments;

  _FixedSegmentPathResult copyWith({
    List<DrawPoint>? points,
    List<ElbowFixedSegment>? fixedSegments,
  }) => _FixedSegmentPathResult(
    points: points ?? this.points,
    fixedSegments: fixedSegments ?? this.fixedSegments,
  );
}

/// Result of a perpendicular endpoint adjustment.
///
/// `moved` is true when existing points were shifted; `inserted` is true
/// when new points were added to the path.
typedef _PerpendicularAdjustment = ({
  List<DrawPoint> points,
  bool moved,
  bool inserted,
});

_PerpendicularAdjustment _unchangedAdjustment(List<DrawPoint> points) =>
    (points: points, moved: false, inserted: false);

final class _ElbowEditContext {
  _ElbowEditContext({
    required this.element,
    required this.data,
    required this.elementsById,
    required this.basePoints,
    required this.incomingPoints,
    required this.previousFixedSegments,
    required this.fixedSegments,
    required this.startBinding,
    required this.endBinding,
    required this.previousStartBinding,
    required this.previousEndBinding,
    required this.releaseRequested,
  });

  final ElementState element;
  final ArrowData data;
  final Map<String, ElementState> elementsById;
  final List<DrawPoint> basePoints;
  final List<DrawPoint> incomingPoints;
  final List<ElbowFixedSegment> previousFixedSegments;
  final List<ElbowFixedSegment> fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final ArrowBinding? previousStartBinding;
  final ArrowBinding? previousEndBinding;
  final bool releaseRequested;

  // -- Derived change flags (lazy) --

  late final bool bindingChanged =
      previousStartBinding != startBinding || previousEndBinding != endBinding;

  late final bool startBindingRemoved =
      previousStartBinding != null && startBinding == null;

  late final bool endBindingRemoved =
      previousEndBinding != null && endBinding == null;

  late final bool pointsChanged = !ElbowGeometry.pointListsEqual(
    basePoints,
    incomingPoints,
  );

  late final bool fixedSegmentsChanged = !_fixedSegmentsEqual(
    previousFixedSegments,
    fixedSegments,
  );

  // -- Endpoint drag helpers (replaces _EndpointDragContext) --

  late final bool startActive = _isEndpointActive(
    basePoints: basePoints,
    incomingPoints: incomingPoints,
    isStart: true,
    previousBinding: previousStartBinding,
    nextBinding: startBinding,
  );

  late final bool endActive = _isEndpointActive(
    basePoints: basePoints,
    incomingPoints: incomingPoints,
    isStart: false,
    previousBinding: previousEndBinding,
    nextBinding: endBinding,
  );

  bool get startWasBound => previousStartBinding != null;
  bool get endWasBound => previousEndBinding != null;

  ArrowheadStyle get startArrowhead => data.startArrowhead;
  ArrowheadStyle get endArrowhead => data.endArrowhead;

  bool get hasBindings => startBinding != null || endBinding != null;

  bool get hasBoundStart =>
      startBinding != null && elementsById.containsKey(startBinding!.elementId);

  bool get hasBoundEnd =>
      endBinding != null && elementsById.containsKey(endBinding!.elementId);

  bool get isFullyUnbound => startBinding == null && endBinding == null;

  /// Resolves the required heading for a bound endpoint.
  ///
  /// Returns the heading the first segment must follow (flipped for end).
  ElbowHeading? resolveRequiredHeading({
    required bool isStart,
    required DrawPoint point,
  }) {
    final binding = isStart ? startBinding : endBinding;
    if (binding == null) {
      return null;
    }
    final heading = ElbowGeometry.resolveBoundHeading(
      binding: binding,
      elementsById: elementsById,
      point: point,
    );
    if (heading == null) {
      return null;
    }
    return isStart ? heading : heading.opposite;
  }
}

final class _ElbowEditPipeline {
  _ElbowEditPipeline({
    required this.element,
    required this.data,
    required this.lookup,
    this.localPointsOverride,
    this.fixedSegmentsOverride,
    this.startBindingOverride,
    this.endBindingOverride,
    this.startBindingOverrideIsSet = false,
    this.endBindingOverrideIsSet = false,
  });

  final ElementState element;
  final ArrowData data;
  final CombinedElementLookup lookup;
  final List<DrawPoint>? localPointsOverride;
  final List<ElbowFixedSegment>? fixedSegmentsOverride;
  final ArrowBinding? startBindingOverride;
  final ArrowBinding? endBindingOverride;
  final bool startBindingOverrideIsSet;
  final bool endBindingOverrideIsSet;

  ElbowEditResult run() {
    final context = _buildContext();
    if (context.incomingPoints.length < 2) {
      return _finalizePath(context.data, context.incomingPoints, null);
    }

    if (context.fixedSegments.isEmpty) {
      return _routeWithoutFixedSegments(context);
    }
    if (context.releaseRequested) {
      return _handleFixedSegmentReleaseFlow(context);
    }
    if (context.bindingChanged ||
        (context.pointsChanged && !context.fixedSegmentsChanged)) {
      return _handleEndpointDragFlow(context);
    }
    return _applyFixedSegmentsFlow(context);
  }

  _ElbowEditContext _buildContext() {
    final basePoints = _resolveLocalPoints(element, data);
    final incomingPoints = localPointsOverride ?? basePoints;
    final previousFixedSegments = _sanitizeFixedSegments(
      data.fixedSegments,
      basePoints.length,
    );
    final fixedSegments = _sanitizeFixedSegments(
      fixedSegmentsOverride ?? data.fixedSegments,
      incomingPoints.length,
    );
    final startBinding = _resolveBindingOverride(
      override: startBindingOverride,
      overrideIsSet: startBindingOverrideIsSet,
      fallback: data.startBinding,
    );
    final endBinding = _resolveBindingOverride(
      override: endBindingOverride,
      overrideIsSet: endBindingOverrideIsSet,
      fallback: data.endBinding,
    );
    final previousData = element.data is ArrowData
        ? element.data as ArrowData
        : data;

    return _ElbowEditContext(
      element: element,
      data: data,
      elementsById: lookup.toMap(),
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      previousFixedSegments: previousFixedSegments,
      fixedSegments: fixedSegments,
      startBinding: startBinding,
      endBinding: endBinding,
      previousStartBinding: previousData.startBinding,
      previousEndBinding: previousData.endBinding,
      releaseRequested:
          fixedSegmentsOverride != null &&
          fixedSegments.length < previousFixedSegments.length,
    );
  }

  ElbowEditResult _routeWithoutFixedSegments(_ElbowEditContext context) {
    final routed = routeElbowArrowForElement(
      element: context.element,
      data: context.data.copyWith(
        startBinding: context.startBinding,
        endBinding: context.endBinding,
      ),
      elementsById: context.elementsById,
      startOverride: context.incomingPoints.first,
      endOverride: context.incomingPoints.last,
    );
    return _finalizePath(context.data, routed.localPoints, null);
  }

  ElbowEditResult _handleFixedSegmentReleaseFlow(_ElbowEditContext context) {
    final result = _releaseFixedSegments(
      context,
      currentPoints: context.incomingPoints,
      previousFixed: context.previousFixedSegments,
      remainingFixed: context.fixedSegments,
    );
    return _finalizePath(context.data, result.points, result.fixedSegments);
  }

  ElbowEditResult _handleEndpointDragFlow(_ElbowEditContext context) {
    final updated = _applyEndpointDragWithFixedSegments(context: context);

    var points = updated.points;
    var fixed = updated.fixedSegments;
    if (fixed.length < context.fixedSegments.length) {
      final result = _releaseFixedSegments(
        context,
        currentPoints: points,
        previousFixed: context.fixedSegments,
        remainingFixed: fixed,
        preserveCorners: true,
      );
      points = result.points;
      fixed = result.fixedSegments;
    }

    return _finalizePath(context.data, points, fixed);
  }

  /// Shared release logic for both explicit release and lost-segment
  /// recovery during endpoint drag.
  _FixedSegmentPathResult _releaseFixedSegments(
    _ElbowEditContext context, {
    required List<DrawPoint> currentPoints,
    required List<ElbowFixedSegment> previousFixed,
    required List<ElbowFixedSegment> remainingFixed,
    bool preserveCorners = false,
  }) {
    final released = _handleFixedSegmentRelease(
      context: context,
      currentPoints: currentPoints,
      previousFixed: previousFixed,
      remainingFixed: remainingFixed,
    );
    final mapped =
        _mapFixedSegmentsToBaseline(
          baseline: released.points,
          fixedSegments: released.fixedSegments,
        ) ??
        released;
    final reconciled =
        mapped.fixedSegments.length == released.fixedSegments.length
        ? mapped
        : released;
    final extraPinned = preserveCorners
        ? _interiorCornerPoints(released.points)
        : const <DrawPoint>{};
    return _normalizeFixedSegmentPath(
      points: reconciled.points,
      fixedSegments: reconciled.fixedSegments,
      extraPinned: extraPinned,
      enforceAxes: true,
    );
  }

  ElbowEditResult _applyFixedSegmentsFlow(_ElbowEditContext context) {
    final simplified = _normalizeFixedSegmentPath(
      points: context.incomingPoints,
      fixedSegments: context.fixedSegments,
      enforceAxes: true,
    );
    return _finalizePath(
      context.data,
      simplified.points,
      simplified.fixedSegments,
    );
  }
}

/// Shared finalization: merge same-heading runs, reindex fixed segments,
/// and build the final [ElbowEditResult].
ElbowEditResult _finalizePath(
  ArrowData data,
  List<DrawPoint> points,
  List<ElbowFixedSegment>? fixedSegments,
) {
  final effectiveFixedSegments = fixedSegments ?? const <ElbowFixedSegment>[];
  final hasFixed = effectiveFixedSegments.isNotEmpty;
  final pinned = _collectPinnedPoints(
    points: points,
    fixedSegments: effectiveFixedSegments,
  );
  final merged = ElbowGeometry.mergeConsecutiveSameHeading(
    points,
    pinned: pinned,
  );
  final resolvedFixed = hasFixed
      ? _reindexFixedSegments(merged, effectiveFixedSegments)
      : null;
  return ElbowEditResult(
    localPoints: merged,
    fixedSegments: resolvedFixed,
    startIsSpecial: data.startIsSpecial,
    endIsSpecial: data.endIsSpecial,
  );
}

ArrowBinding? _resolveBindingOverride({
  required ArrowBinding? override,
  required bool overrideIsSet,
  required ArrowBinding? fallback,
}) => overrideIsSet ? override : fallback;

bool _isEndpointActive({
  required List<DrawPoint> basePoints,
  required List<DrawPoint> incomingPoints,
  required bool isStart,
  required ArrowBinding? previousBinding,
  required ArrowBinding? nextBinding,
}) =>
    _didEndpointMove(
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      isStart: isStart,
    ) ||
    previousBinding != nextBinding;

bool _didEndpointMove({
  required List<DrawPoint> basePoints,
  required List<DrawPoint> incomingPoints,
  required bool isStart,
}) =>
    basePoints.isNotEmpty &&
    incomingPoints.isNotEmpty &&
    (isStart
        ? basePoints.first != incomingPoints.first
        : basePoints.last != incomingPoints.last);

// ---------------------------------------------------------------------------
// Geometry helpers (merged from elbow_edit_geometry.dart)
// ---------------------------------------------------------------------------

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
  return ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
}
