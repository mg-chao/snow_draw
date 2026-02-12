part of 'elbow_editing.dart';

/// Internal state containers shared by the elbow edit pipeline and helpers.
@immutable
final class _FixedSegmentPathResult {
  const _FixedSegmentPathResult({
    required this.points,
    required this.fixedSegments,
  });

  final List<DrawPoint> points;
  final List<ElbowFixedSegment> fixedSegments;
}

/// Edit mode selection for the elbow edit pipeline.
enum _ElbowEditMode {
  /// Re-route a fresh elbow when no fixed segments exist.
  routeFresh,

  /// Re-route only the released span when fixed segments were removed.
  releaseFixedSegments,

  /// Preserve fixed segments while endpoints move.
  dragEndpoints,

  /// Apply fixed segment axes and simplify.
  applyFixedSegments,
}

@immutable
final class _PerpendicularAdjustment {
  const _PerpendicularAdjustment({
    required this.points,
    required this.moved,
    required this.inserted,
  });

  final List<DrawPoint> points;
  final bool moved;
  final bool inserted;
}

/// Resolved inputs and flags that drive edit mode selection.
@immutable
final class _ElbowEditContext {
  const _ElbowEditContext({
    required this.element,
    required this.data,
    required this.lookup,
    required this.basePoints,
    required this.incomingPoints,
    required this.previousFixedSegments,
    required this.fixedSegments,
    required this.startBinding,
    required this.endBinding,
    required this.previousStartBinding,
    required this.previousEndBinding,
    required this.bindingChanged,
    required this.startBindingRemoved,
    required this.endBindingRemoved,
    required this.pointsChanged,
    required this.fixedSegmentsChanged,
    required this.releaseRequested,
  });

  final ElementState element;
  final ArrowData data;
  final CombinedElementLookup lookup;
  final List<DrawPoint> basePoints;
  final List<DrawPoint> incomingPoints;
  final List<ElbowFixedSegment> previousFixedSegments;
  final List<ElbowFixedSegment> fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final ArrowBinding? previousStartBinding;
  final ArrowBinding? previousEndBinding;
  final bool bindingChanged;
  final bool startBindingRemoved;
  final bool endBindingRemoved;
  final bool pointsChanged;
  final bool fixedSegmentsChanged;
  final bool releaseRequested;

  bool get hasEnoughPoints => incomingPoints.length >= 2;

  /// Decides which edit pipeline branch to execute.
  _ElbowEditMode resolveMode() {
    if (fixedSegments.isEmpty) {
      return _ElbowEditMode.routeFresh;
    }
    if (releaseRequested) {
      return _ElbowEditMode.releaseFixedSegments;
    }
    if (bindingChanged || (pointsChanged && !fixedSegmentsChanged)) {
      return _ElbowEditMode.dragEndpoints;
    }
    return _ElbowEditMode.applyFixedSegments;
  }

  /// Returns a concrete map for downstream functions that require it.
  /// Lazily computed only when needed.
  Map<String, ElementState> get elementsById => lookup.toMap();
}

/// Step-by-step edit orchestration used by [computeElbowEdit].
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
    if (!context.hasEnoughPoints) {
      return _buildResult(
        data: context.data,
        points: context.incomingPoints,
        fixedSegments: null,
      );
    }

    switch (context.resolveMode()) {
      case _ElbowEditMode.routeFresh:
        return _routeWithoutFixedSegments(context);
      case _ElbowEditMode.releaseFixedSegments:
        return _handleFixedSegmentReleaseFlow(context);
      case _ElbowEditMode.dragEndpoints:
        return _handleEndpointDragFlow(context);
      case _ElbowEditMode.applyFixedSegments:
        return _applyFixedSegmentsFlow(context);
    }
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
      lookup: lookup,
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      previousFixedSegments: previousFixedSegments,
      fixedSegments: fixedSegments,
      startBinding: startBinding,
      endBinding: endBinding,
      previousStartBinding: previousData.startBinding,
      previousEndBinding: previousData.endBinding,
      bindingChanged:
          previousData.startBinding != startBinding ||
          previousData.endBinding != endBinding,
      startBindingRemoved:
          previousData.startBinding != null && startBinding == null,
      endBindingRemoved: previousData.endBinding != null && endBinding == null,
      pointsChanged: !ElbowGeometry.pointListsEqual(basePoints, incomingPoints),
      fixedSegmentsChanged: !_fixedSegmentsEqual(
        previousFixedSegments,
        fixedSegments,
      ),
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
    return _buildResult(
      data: context.data,
      points: routed.localPoints,
      fixedSegments: null,
    );
  }

  ElbowEditResult _handleFixedSegmentReleaseFlow(_ElbowEditContext context) {
    final result = _releaseFixedSegments(
      context,
      currentPoints: context.incomingPoints,
      previousFixed: context.previousFixedSegments,
      remainingFixed: context.fixedSegments,
    );
    return _buildResult(
      data: context.data,
      points: result.points,
      fixedSegments: result.fixedSegments,
    );
  }

  ElbowEditResult _handleEndpointDragFlow(_ElbowEditContext context) {
    final updated = _applyEndpointDragWithFixedSegments(
      context: _EndpointDragContext.fromEditContext(context),
    );

    var resolvedPoints = updated.points;
    var resolvedFixed = updated.fixedSegments;
    if (resolvedFixed.length < context.fixedSegments.length) {
      final result = _releaseFixedSegments(
        context,
        currentPoints: resolvedPoints,
        previousFixed: context.fixedSegments,
        remainingFixed: resolvedFixed,
        preserveCorners: true,
      );
      resolvedPoints = result.points;
      resolvedFixed = result.fixedSegments;
    }

    return _buildResult(
      data: context.data,
      points: resolvedPoints,
      fixedSegments: resolvedFixed,
    );
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
      element: context.element,
      data: context.data,
      elementsById: context.elementsById,
      currentPoints: currentPoints,
      previousFixed: previousFixed,
      remainingFixed: remainingFixed,
      startBinding: context.startBinding,
      endBinding: context.endBinding,
    );
    final mapped = _mapFixedSegmentsToBaseline(
      baseline: released.points,
      fixedSegments: released.fixedSegments,
    );
    final reconciled =
        mapped != null &&
            mapped.fixedSegments.length == released.fixedSegments.length
        ? mapped
        : released;
    final extraPinned = preserveCorners
        ? () {
            final corners = ElbowGeometry.cornerPoints(released.points);
            return corners.length > 2
                ? corners.sublist(1, corners.length - 1).toSet()
                : const <DrawPoint>{};
          }()
        : const <DrawPoint>{};
    return _normalizeFixedSegmentReleasePath(
      points: reconciled.points,
      fixedSegments: reconciled.fixedSegments,
      extraPinned: extraPinned,
    );
  }

  ElbowEditResult _applyFixedSegmentsFlow(_ElbowEditContext context) {
    final base = !context.pointsChanged && context.fixedSegmentsChanged
        ? context.basePoints
        : context.incomingPoints;
    final simplified = _simplifyFixedSegmentPath(
      points: base,
      fixedSegments: context.fixedSegments,
      enforceAxes: true,
    );
    return _buildResult(
      data: context.data,
      points: simplified.points,
      fixedSegments: simplified.fixedSegments,
    );
  }
}

ElbowEditResult _buildResult({
  required ArrowData data,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment>? fixedSegments,
}) {
  final hasFixed = fixedSegments != null && fixedSegments.isNotEmpty;
  final pinned = _collectPinnedPoints(
    points: points,
    fixedSegments: hasFixed ? fixedSegments : const [],
  );
  final merged = ElbowGeometry.mergeConsecutiveSameHeading(
    points,
    pinned: pinned,
  );
  final resolvedFixed = hasFixed
      ? _reindexFixedSegments(merged, fixedSegments)
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
}) {
  if (overrideIsSet || override != null) {
    return override;
  }
  return fallback;
}

// ---------------------------------------------------------------------------
// Geometry helpers (merged from elbow_edit_geometry.dart)
// ---------------------------------------------------------------------------

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowData data) {
  final resolved = ArrowGeometry.resolveWorldPoints(
    rect: element.rect,
    normalizedPoints: data.points,
  );
  return resolved
      .map((point) => DrawPoint(x: point.dx, y: point.dy))
      .toList(growable: false);
}
