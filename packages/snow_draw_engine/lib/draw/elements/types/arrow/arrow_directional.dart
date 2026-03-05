import 'package:meta/meta.dart';

import '../../../models/element_state.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import 'arrow_core.dart' as core;
import 'arrow_core_bridge.dart';
import 'arrow_like_data.dart';

/// Spacing configuration for directional node offset helpers.
@immutable
final class ArrowDirectionalSpacing {
  const ArrowDirectionalSpacing({this.horizontal, this.vertical});

  final double? horizontal;
  final double? vertical;
}

/// Directional graph projection used by arrow-core directional helpers.
@immutable
final class ArrowDirectionalProjection {
  const ArrowDirectionalProjection({required this.nodes, required this.arrows});

  final List<core.DirectionalFlowNodeState> nodes;
  final List<core.DirectionalFlowArrowState> arrows;

  bool get hasNodes => nodes.isNotEmpty;
  bool get hasArrows => arrows.isNotEmpty;
}

/// Converts a bindable engine element into arrow-core directional node state.
core.DirectionalFlowNodeState? toCoreDirectionalFlowNodeState(
  ElementState element,
) {
  final bindable = toCoreBindableState(element);
  if (bindable == null) {
    return null;
  }

  return core.DirectionalFlowNodeState(
    id: bindable.id,
    x: bindable.x,
    y: bindable.y,
    width: bindable.width,
    height: bindable.height,
    shape: bindable.shape,
    angle: bindable.angle,
    strokeWidth: bindable.strokeWidth,
  );
}

/// Converts an arrow-like engine element into directional arrow state.
///
/// When [onlyBoundArrows] is `true`, arrows missing either endpoint binding are
/// excluded.
core.DirectionalFlowArrowState? toCoreDirectionalFlowArrowState(
  ElementState element, {
  bool onlyBoundArrows = true,
}) {
  final data = element.data;
  if (data is! ArrowLikeData) {
    return null;
  }

  final arrow = toCoreArrowState(element: element, data: data);
  if (onlyBoundArrows &&
      (arrow.startBinding == null || arrow.endBinding == null)) {
    return null;
  }

  return core.DirectionalFlowArrowState(
    id: arrow.id,
    x: arrow.x,
    y: arrow.y,
    points: List<core.Point>.unmodifiable(
      arrow.points
          .map((point) => <double>[point[0], point[1]])
          .toList(growable: false),
    ),
    startBinding: arrow.startBinding == null
        ? null
        : core.DirectionalFlowArrowBinding(
            elementId: arrow.startBinding!.elementId,
          ),
    endBinding: arrow.endBinding == null
        ? null
        : core.DirectionalFlowArrowBinding(
            elementId: arrow.endBinding!.elementId,
          ),
    elbowed: arrow.elbowed,
  );
}

/// Projects a document snapshot into arrow-core directional node/arrow lists.
ArrowDirectionalProjection projectArrowDirectionalGraph(
  Iterable<ElementState> elements, {
  bool onlyBoundArrows = true,
}) {
  final nodes = <core.DirectionalFlowNodeState>[];
  final arrows = <core.DirectionalFlowArrowState>[];

  for (final element in elements) {
    final node = toCoreDirectionalFlowNodeState(element);
    if (node != null) {
      nodes.add(node);
    }

    final arrow = toCoreDirectionalFlowArrowState(
      element,
      onlyBoundArrows: onlyBoundArrows,
    );
    if (arrow != null) {
      arrows.add(arrow);
    }
  }

  return ArrowDirectionalProjection(
    nodes: List<core.DirectionalFlowNodeState>.unmodifiable(nodes),
    arrows: List<core.DirectionalFlowArrowState>.unmodifiable(arrows),
  );
}

/// Resolves directional successor ids for [nodeId].
List<String> getDirectionalSuccessorIds({
  required String nodeId,
  required core.DirectionalGraphDirection direction,
  required Iterable<ElementState> elements,
  bool elbowOnly = true,
}) {
  final projection = projectArrowDirectionalGraph(elements);
  if (!projection.hasNodes || !projection.hasArrows) {
    return const <String>[];
  }

  final resolved = core.getDirectionalSuccessorIds(
    core.DirectionalNodeRelationLookupInput(
      nodeId: nodeId,
      direction: direction,
      nodes: projection.nodes,
      arrows: projection.arrows,
      options: core.ResolveDirectionalNodeRelationsOptions(
        elbowOnly: elbowOnly,
      ),
    ),
  );
  return List<String>.unmodifiable(resolved);
}

/// Resolves directional predecessor ids for [nodeId].
List<String> getDirectionalPredecessorIds({
  required String nodeId,
  required core.DirectionalGraphDirection direction,
  required Iterable<ElementState> elements,
  bool elbowOnly = true,
}) {
  final projection = projectArrowDirectionalGraph(elements);
  if (!projection.hasNodes || !projection.hasArrows) {
    return const <String>[];
  }

  final resolved = core.getDirectionalPredecessorIds(
    core.DirectionalNodeRelationLookupInput(
      nodeId: nodeId,
      direction: direction,
      nodes: projection.nodes,
      arrows: projection.arrows,
      options: core.ResolveDirectionalNodeRelationsOptions(
        elbowOnly: elbowOnly,
      ),
    ),
  );
  return List<String>.unmodifiable(resolved);
}

/// Computes directional placement offset for a single node.
DrawPoint computeDirectionalNodeOffset({
  required DrawRect nodeBounds,
  required List<DrawRect> linkedNodeBounds,
  required core.DirectionalGraphDirection direction,
  ArrowDirectionalSpacing? spacing,
}) {
  final offset = core.computeDirectionalNodeOffset(
    core.ComputeDirectionalNodeOffsetInput(
      node: _toDirectionalNodeBounds(nodeBounds),
      linkedNodes: linkedNodeBounds
          .map(_toDirectionalNodeBounds)
          .toList(growable: false),
      direction: direction,
      spacing: _toDirectionalNodeSpacing(spacing),
    ),
  );
  return DrawPoint(x: offset[0], y: offset[1]);
}

/// Computes directional placement offsets for a node batch.
List<DrawPoint> computeDirectionalNodeBatchOffsets({
  required DrawRect nodeBounds,
  required core.DirectionalGraphDirection direction,
  required int count,
  ArrowDirectionalSpacing? spacing,
}) {
  if (count <= 0) {
    return const <DrawPoint>[];
  }

  final offsets = core.computeDirectionalNodeBatchOffsets(
    core.ComputeDirectionalNodeBatchOffsetsInput(
      node: _toDirectionalNodeBounds(nodeBounds),
      direction: direction,
      count: count,
      spacing: _toDirectionalNodeSpacing(spacing),
    ),
  );
  return List<DrawPoint>.unmodifiable(
    offsets
        .map((offset) => DrawPoint(x: offset[0], y: offset[1]))
        .toList(growable: false),
  );
}

/// Wrapper around arrow-core directional exploration navigator.
final class ArrowDirectionalNavigator {
  ArrowDirectionalNavigator({core.DirectionalArrowNavigator? navigator})
    : _navigator = navigator ?? core.DirectionalArrowNavigator();

  final core.DirectionalArrowNavigator _navigator;

  bool get isExploring => _navigator.isExploring;

  void clear() => _navigator.clear();

  /// Explores directional neighbors for [nodeId].
  ///
  /// Returns the next linked node id or `null` when no linked node exists.
  String? exploreByDirection({
    required String nodeId,
    required core.DirectionalGraphDirection direction,
    required Iterable<ElementState> elements,
    bool elbowOnly = true,
  }) {
    final projection = projectArrowDirectionalGraph(elements);
    if (!projection.hasNodes || !projection.hasArrows) {
      return null;
    }

    return _navigator.exploreByDirection(
      core.DirectionalNavigatorExploreInput(
        nodeId: nodeId,
        direction: direction,
        nodes: projection.nodes,
        arrows: projection.arrows,
        options: core.ResolveDirectionalNodeRelationsOptions(
          elbowOnly: elbowOnly,
        ),
      ),
    );
  }
}

/// Returns whether [nodeId] is connected by any bound directional arrow.
bool isNodeLinkedByDirectionalArrow({
  required String nodeId,
  required Iterable<ElementState> elements,
}) {
  final arrows = projectArrowDirectionalGraph(elements).arrows;
  return core.isNodeLinkedByArrow(nodeId, arrows);
}

core.DirectionalNodeBounds _toDirectionalNodeBounds(DrawRect rect) =>
    core.DirectionalNodeBounds(
      x: rect.minX,
      y: rect.minY,
      width: rect.width,
      height: rect.height,
    );

core.DirectionalNodeSpacing? _toDirectionalNodeSpacing(
  ArrowDirectionalSpacing? spacing,
) {
  if (spacing == null) {
    return null;
  }
  return core.DirectionalNodeSpacing(
    horizontal: spacing.horizontal,
    vertical: spacing.vertical,
  );
}
