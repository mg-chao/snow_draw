import '../../../core/coordinates/element_space.dart';
import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../types/element_style.dart';
import '../../../utils/combined_element_lookup.dart';
import 'arrow_binding.dart';
import 'arrow_data.dart';
import 'arrow_geometry.dart';
import 'arrow_layout.dart';
import 'arrow_like_data.dart';
import 'elbow/elbow_editing.dart';

/// Resolves arrow bindings when bound elements change position.
///
/// This resolver intentionally favors correctness and maintainability over
/// incremental-cache complexity: every resolve pass scans current arrow-like
/// elements and applies endpoint updates when their bound targets changed.
final class ArrowBindingResolver {
  ArrowBindingResolver._();

  /// Global stateless resolver instance.
  static final instance = ArrowBindingResolver._();

  /// Resolves bound arrows when elements change.
  ///
  /// Uses [CombinedElementLookup] to avoid allocating merged maps.
  Map<String, ElementState> resolve({
    required Map<String, ElementState> baseElements,
    required Map<String, ElementState> updatedElements,
    required Set<String> changedElementIds,
  }) {
    if (changedElementIds.isEmpty) {
      return const {};
    }

    final changedTargetIds = changedElementIds;
    final lookup = CombinedElementLookup(
      base: baseElements,
      overlay: updatedElements,
    );
    final updates = <String, ElementState>{};
    for (final element in lookup.values) {
      final data = element.data;
      if (data is! ArrowLikeData) {
        continue;
      }
      final startBinding = data.startBinding;
      final endBinding = data.endBinding;
      if (startBinding == null && endBinding == null) {
        continue;
      }

      final updateStart =
          startBinding != null &&
          changedTargetIds.contains(startBinding.elementId);
      final updateEnd =
          endBinding != null && changedTargetIds.contains(endBinding.elementId);
      if (!updateStart && !updateEnd) {
        continue;
      }

      final updated = _applyBindings(
        element: element,
        data: data,
        lookup: lookup,
        updateStart: updateStart,
        updateEnd: updateEnd,
      );
      if (updated != null) {
        updates[updated.id] = updated;
      }
    }

    return updates;
  }
}

ElementState? _applyBindings({
  required ElementState element,
  required ArrowLikeData data,
  required CombinedElementLookup lookup,
  required bool updateStart,
  required bool updateEnd,
}) {
  assert(updateStart || updateEnd, 'At least one endpoint must be updated.');

  final localPoints = _resolveLocalPoints(element, data);
  if (localPoints.length < 2) {
    return null;
  }

  final syncBothEnds = data.startBinding != null && data.endBinding != null;
  final shouldUpdateStart = updateStart || syncBothEnds;
  final shouldUpdateEnd = updateEnd || syncBothEnds;

  final rect = element.rect;
  final space = ElementSpace(rotation: element.rotation, origin: rect.center);
  final isElbow = data.arrowType == ArrowType.elbow;
  final maxIterations =
      shouldUpdateStart && shouldUpdateEnd && localPoints.length == 2 ? 4 : 2;
  var changedAtLeastOnce = false;

  for (var i = 0; i < maxIterations; i++) {
    var changedThisPass = false;
    final startReference = space.toWorld(localPoints[1]);
    final endReference = space.toWorld(localPoints[localPoints.length - 2]);

    changedThisPass =
        _applyBoundEndpoint(
          binding: data.startBinding,
          shouldUpdate: shouldUpdateStart,
          pointIndex: 0,
          referencePoint: startReference,
          lookup: lookup,
          space: space,
          isElbow: isElbow,
          hasArrowhead: data.startArrowhead != ArrowheadStyle.none,
          localPoints: localPoints,
        ) ||
        changedThisPass;

    changedThisPass =
        _applyBoundEndpoint(
          binding: data.endBinding,
          shouldUpdate: shouldUpdateEnd,
          pointIndex: localPoints.length - 1,
          referencePoint: endReference,
          lookup: lookup,
          space: space,
          isElbow: isElbow,
          hasArrowhead: data.endArrowhead != ArrowheadStyle.none,
          localPoints: localPoints,
        ) ||
        changedThisPass;

    if (!changedThisPass) {
      break;
    }
    changedAtLeastOnce = true;
  }

  if (!changedAtLeastOnce) {
    return null;
  }

  if (data.arrowType == ArrowType.elbow && data is ArrowData) {
    return _applyElbowBindingResult(
      element: element,
      data: data,
      lookup: lookup,
      localPoints: localPoints,
    );
  }

  final geometry = resolveArrowGeometryUpdate(
    localPoints: localPoints,
    oldRect: element.rect,
    rotation: element.rotation,
    arrowType: data.arrowType,
  );
  final updatedData = data.copyWith(points: geometry.normalizedPoints);
  return _buildUpdatedElementOrNull(
    element: element,
    previousData: data,
    nextData: updatedData,
    nextRect: geometry.rect,
  );
}

bool _applyBoundEndpoint({
  required ArrowBinding? binding,
  required bool shouldUpdate,
  required int pointIndex,
  required DrawPoint referencePoint,
  required CombinedElementLookup lookup,
  required ElementSpace space,
  required bool isElbow,
  required bool hasArrowhead,
  required List<DrawPoint> localPoints,
}) {
  if (!shouldUpdate || binding == null) {
    return false;
  }
  final nextLocal = _resolveBoundLocalPoint(
    binding: binding,
    lookup: lookup,
    space: space,
    isElbow: isElbow,
    hasArrowhead: hasArrowhead,
    referencePoint: referencePoint,
  );
  if (nextLocal == null) {
    return false;
  }

  if (nextLocal == localPoints[pointIndex]) {
    return false;
  }
  localPoints[pointIndex] = nextLocal;
  return true;
}

ElementState? _applyElbowBindingResult({
  required ElementState element,
  required ArrowData data,
  required CombinedElementLookup lookup,
  required List<DrawPoint> localPoints,
}) {
  final updated = computeElbowEdit(
    element: element,
    data: data,
    lookup: lookup,
    localPointsOverride: localPoints,
    fixedSegmentsOverride: data.fixedSegments,
  );
  final geometry = resolveArrowGeometryUpdate(
    localPoints: updated.localPoints,
    oldRect: element.rect,
    rotation: element.rotation,
    arrowType: data.arrowType,
  );
  final transformedFixedSegments = transformFixedSegments(
    segments: updated.fixedSegments,
    oldRect: element.rect,
    newRect: geometry.rect,
    rotation: element.rotation,
  );
  final updatedData = data.copyWith(
    points: geometry.normalizedPoints,
    fixedSegments: transformedFixedSegments,
    startIsSpecial: updated.startIsSpecial,
    endIsSpecial: updated.endIsSpecial,
  );
  return _buildUpdatedElementOrNull(
    element: element,
    previousData: data,
    nextData: updatedData,
    nextRect: geometry.rect,
  );
}

ElementState? _buildUpdatedElementOrNull({
  required ElementState element,
  required ArrowLikeData previousData,
  required ArrowLikeData nextData,
  required DrawRect nextRect,
}) {
  if (nextData == previousData && nextRect == element.rect) {
    return null;
  }
  return element.copyWith(rect: nextRect, data: nextData);
}

DrawPoint? _resolveBoundLocalPoint({
  required ArrowBinding binding,
  required CombinedElementLookup lookup,
  required ElementSpace space,
  required bool isElbow,
  required bool hasArrowhead,
  DrawPoint? referencePoint,
}) {
  final target = lookup[binding.elementId];
  if (target == null) {
    return null;
  }

  final boundPoint = isElbow
      ? ArrowBindingUtils.resolveElbowBoundPoint(
          binding: binding,
          target: target,
          hasArrowhead: hasArrowhead,
        )
      : ArrowBindingUtils.resolveBoundPoint(
          binding: binding,
          target: target,
          referencePoint: referencePoint,
        );
  if (boundPoint == null) {
    return null;
  }

  return space.fromWorld(boundPoint);
}

List<DrawPoint> _resolveLocalPoints(ElementState element, ArrowLikeData data) =>
    ArrowGeometry.resolveWorldPoints(
      rect: element.rect,
      normalizedPoints: data.points,
    );
