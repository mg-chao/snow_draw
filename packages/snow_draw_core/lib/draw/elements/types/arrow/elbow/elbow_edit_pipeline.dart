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
    required this.elementsById,
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
  final Map<String, ElementState> elementsById;
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
}

/// Step-by-step edit orchestration used by [computeElbowEdit].
final class _ElbowEditPipeline {
  _ElbowEditPipeline({
    required this.element,
    required this.data,
    required this.elementsById,
    this.localPointsOverride,
    this.fixedSegmentsOverride,
    this.startBindingOverride,
    this.endBindingOverride,
  });

  final ElementState element;
  final ArrowData data;
  final Map<String, ElementState> elementsById;
  final List<DrawPoint>? localPointsOverride;
  final List<ElbowFixedSegment>? fixedSegmentsOverride;
  final ArrowBinding? startBindingOverride;
  final ArrowBinding? endBindingOverride;

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
    // Step 1: resolve the base local points from the element and incoming
    // edits.
    final basePoints = _resolveLocalPoints(element, data);
    final incomingPoints = localPointsOverride ?? basePoints;

    // Step 2: sanitize fixed segments and resolve binding overrides.
    final previousFixedSegments = _sanitizeFixedSegments(
      data.fixedSegments,
      basePoints.length,
    );
    final fixedSegments = _sanitizeFixedSegments(
      fixedSegmentsOverride ?? data.fixedSegments,
      incomingPoints.length,
    );
    final startBinding = startBindingOverride ?? data.startBinding;
    final endBinding = endBindingOverride ?? data.endBinding;
    final previousData = element.data is ArrowData
        ? element.data as ArrowData
        : data;
    final previousStartBinding = previousData.startBinding;
    final previousEndBinding = previousData.endBinding;
    final bindingChanged =
        previousStartBinding != startBinding ||
        previousEndBinding != endBinding;
    final startBindingRemoved =
        previousStartBinding != null && startBinding == null;
    final endBindingRemoved = previousEndBinding != null && endBinding == null;

    final pointsChanged = !_pointsEqual(basePoints, incomingPoints);
    final fixedSegmentsChanged = !_fixedSegmentsEqual(
      previousFixedSegments,
      fixedSegments,
    );
    final releaseRequested =
        fixedSegmentsOverride != null &&
        fixedSegments.length < previousFixedSegments.length;

    return _ElbowEditContext(
      element: element,
      data: data,
      elementsById: elementsById,
      basePoints: basePoints,
      incomingPoints: incomingPoints,
      previousFixedSegments: previousFixedSegments,
      fixedSegments: fixedSegments,
      startBinding: startBinding,
      endBinding: endBinding,
      previousStartBinding: previousStartBinding,
      previousEndBinding: previousEndBinding,
      bindingChanged: bindingChanged,
      startBindingRemoved: startBindingRemoved,
      endBindingRemoved: endBindingRemoved,
      pointsChanged: pointsChanged,
      fixedSegmentsChanged: fixedSegmentsChanged,
      releaseRequested: releaseRequested,
    );
  }

  ElbowEditResult _routeWithoutFixedSegments(_ElbowEditContext context) {
    // Step 3: no fixed segments means a fresh route is required.
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
    // Step 4: fixed segment release (e.g. user unpins a segment).
    final updated = _handleFixedSegmentRelease(
      element: context.element,
      data: context.data,
      elementsById: context.elementsById,
      currentPoints: context.incomingPoints,
      previousFixed: context.previousFixedSegments,
      remainingFixed: context.fixedSegments,
      startBinding: context.startBinding,
      endBinding: context.endBinding,
    );
    final mapped = _applyFixedSegmentsToBaselineRoute(
      baseline: updated.points,
      fixedSegments: updated.fixedSegments,
    );
    final reconciled =
        mapped.fixedSegments.length == updated.fixedSegments.length
        ? mapped
        : updated;
    final normalized = _normalizeFixedSegmentReleasePath(
      points: reconciled.points,
      fixedSegments: reconciled.fixedSegments,
    );
    final resultSegments = normalized.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(normalized.fixedSegments);
    return _buildResult(
      data: context.data,
      points: normalized.points,
      fixedSegments: resultSegments,
    );
  }

  ElbowEditResult _handleEndpointDragFlow(_ElbowEditContext context) {
    // Step 5: endpoint drag while fixed segments stay pinned.
    final startPointChanged =
        context.basePoints.isNotEmpty &&
        context.incomingPoints.isNotEmpty &&
        context.basePoints.first != context.incomingPoints.first;
    final endPointChanged =
        context.basePoints.isNotEmpty &&
        context.incomingPoints.isNotEmpty &&
        context.basePoints.last != context.incomingPoints.last;
    final startBindingChanged =
        context.previousStartBinding != context.startBinding;
    final endBindingChanged = context.previousEndBinding != context.endBinding;
    final startWasBound = context.previousStartBinding != null;
    final endWasBound = context.previousEndBinding != null;
    final updated = _applyEndpointDragWithFixedSegments(
      context: _EndpointDragContext(
        element: context.element,
        elementsById: context.elementsById,
        basePoints: context.basePoints,
        incomingPoints: context.incomingPoints,
        fixedSegments: context.fixedSegments,
        startBinding: context.startBinding,
        endBinding: context.endBinding,
        startBindingRemoved: context.startBindingRemoved,
        endBindingRemoved: context.endBindingRemoved,
        startWasBound: startWasBound,
        endWasBound: endWasBound,
        startActive: startPointChanged || startBindingChanged,
        endActive: endPointChanged || endBindingChanged,
        startArrowhead: context.data.startArrowhead,
        endArrowhead: context.data.endArrowhead,
      ),
    );
    final resultSegments = updated.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(updated.fixedSegments);
    return _buildResult(
      data: context.data,
      points: List<DrawPoint>.unmodifiable(updated.points),
      fixedSegments: resultSegments,
    );
  }

  ElbowEditResult _applyFixedSegmentsFlow(_ElbowEditContext context) {
    // Step 6: apply fixed segments to updated points if needed.
    var workingPoints = context.incomingPoints;
    if (!context.pointsChanged && context.fixedSegmentsChanged) {
      workingPoints = _applyFixedSegmentsToPoints(
        context.basePoints,
        context.fixedSegments,
      );
    }
    workingPoints = _applyFixedSegmentsToPoints(
      workingPoints,
      context.fixedSegments,
    );

    // Step 7: simplify and reindex segments to keep the path stable.
    final simplified = _simplifyFixedSegmentPath(
      points: workingPoints,
      fixedSegments: context.fixedSegments,
    );
    final resultSegments = simplified.fixedSegments.isEmpty
        ? null
        : List<ElbowFixedSegment>.unmodifiable(simplified.fixedSegments);

    return _buildResult(
      data: context.data,
      points: simplified.points,
      fixedSegments: resultSegments,
    );
  }
}

ElbowEditResult _buildResult({
  required ArrowData data,
  required List<DrawPoint> points,
  required List<ElbowFixedSegment>? fixedSegments,
}) => ElbowEditResult(
  localPoints: points,
  fixedSegments: fixedSegments,
  startIsSpecial: data.startIsSpecial,
  endIsSpecial: data.endIsSpecial,
);
