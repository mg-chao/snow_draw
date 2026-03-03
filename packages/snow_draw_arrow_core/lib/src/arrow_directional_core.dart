import 'arrow_geom.dart';
import 'arrow_types.dart';

typedef DirectionalGraphDirection = String;

class DirectionalFlowNodeState {
  const DirectionalFlowNodeState({
    required this.id,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.shape,
    this.angle,
    this.strokeWidth,
  });

  final String id;
  final double x;
  final double y;
  final double width;
  final double height;
  final BindableShape? shape;
  final double? angle;
  final double? strokeWidth;
}

class DirectionalFlowArrowBinding {
  const DirectionalFlowArrowBinding({required this.elementId});

  final String elementId;
}

class DirectionalFlowArrowState {
  const DirectionalFlowArrowState({
    required this.id,
    required this.x,
    required this.y,
    required this.points,
    required this.startBinding,
    required this.endBinding,
    this.elbowed,
  });

  final String id;
  final double x;
  final double y;
  final List<Point> points;
  final DirectionalFlowArrowBinding? startBinding;
  final DirectionalFlowArrowBinding? endBinding;
  final bool? elbowed;
}

const double _defaultVerticalOffset = 100;
const double _defaultHorizontalOffset = 100;

class ResolveDirectionalNodeRelationsInput {
  const ResolveDirectionalNodeRelationsInput({
    required this.type,
    required this.nodeId,
    required this.direction,
    required this.nodes,
    required this.arrows,
    this.options,
  });

  final String type;
  final String nodeId;
  final DirectionalGraphDirection direction;
  final List<DirectionalFlowNodeState> nodes;
  final List<DirectionalFlowArrowState> arrows;
  final ResolveDirectionalNodeRelationsOptions? options;
}

class ResolveDirectionalNodeRelationsOptions {
  const ResolveDirectionalNodeRelationsOptions({this.elbowOnly});

  final bool? elbowOnly;
}

BindableState _toHeadingBindable(DirectionalFlowNodeState node) =>
    BindableState(
      id: node.id,
      shape: node.shape ?? 'rectangle',
      x: node.x,
      y: node.y,
      width: node.width,
      height: node.height,
      angle: node.angle ?? 0,
      strokeWidth: node.strokeWidth ?? 0,
    );

Point _getArrowEndpointGlobal(DirectionalFlowArrowState arrow, String edge) {
  final point = edge == 'start'
      ? (arrow.points.isNotEmpty ? arrow.points.first : null)
      : (arrow.points.isNotEmpty ? arrow.points.last : null);
  if (point == null) {
    return <double>[arrow.x, arrow.y];
  }
  return <double>[arrow.x + point[0], arrow.y + point[1]];
}

List<String> _resolveDirectionalNodeRelativeIds(
  ResolveDirectionalNodeRelationsInput input,
) {
  final nodeById = <String, DirectionalFlowNodeState>{
    for (final node in input.nodes) node.id: node,
  };
  final node = nodeById[input.nodeId];
  if (node == null) {
    return <String>[];
  }

  bool matchesDirection(DirectionalFlowArrowState arrow) {
    final endpoint = input.type == 'predecessors'
        ? _getArrowEndpointGlobal(arrow, 'end')
        : _getArrowEndpointGlobal(arrow, 'start');
    final heading = headingFromBindable(endpoint, _toHeadingBindable(node));
    return heading == input.direction;
  }

  final relativeIds = <String>[];

  for (final arrow in input.arrows) {
    if ((input.options?.elbowOnly ?? true) && arrow.elbowed != true) {
      continue;
    }

    final nodeSideBinding = input.type == 'predecessors'
        ? arrow.endBinding
        : arrow.startBinding;
    if (nodeSideBinding == null || nodeSideBinding.elementId != input.nodeId) {
      continue;
    }

    final oppositeBinding = input.type == 'predecessors'
        ? arrow.startBinding
        : arrow.endBinding;
    if (oppositeBinding == null ||
        !nodeById.containsKey(oppositeBinding.elementId)) {
      continue;
    }

    if (!matchesDirection(arrow)) {
      continue;
    }

    relativeIds.add(oppositeBinding.elementId);
  }

  return relativeIds;
}

List<String> getDirectionalSuccessorIds(
  ResolveDirectionalNodeRelationsInput input,
) => _resolveDirectionalNodeRelativeIds(
  ResolveDirectionalNodeRelationsInput(
    type: 'successors',
    nodeId: input.nodeId,
    direction: input.direction,
    nodes: input.nodes,
    arrows: input.arrows,
    options: input.options,
  ),
);

List<String> getDirectionalPredecessorIds(
  ResolveDirectionalNodeRelationsInput input,
) => _resolveDirectionalNodeRelativeIds(
  ResolveDirectionalNodeRelationsInput(
    type: 'predecessors',
    nodeId: input.nodeId,
    direction: input.direction,
    nodes: input.nodes,
    arrows: input.arrows,
    options: input.options,
  ),
);

class DirectionalNodeBounds {
  const DirectionalNodeBounds({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;
  final double width;
  final double height;
}

class DirectionalNodeSpacing {
  const DirectionalNodeSpacing({this.horizontal, this.vertical});

  final double? horizontal;
  final double? vertical;
}

class ComputeDirectionalNodeOffsetInput {
  const ComputeDirectionalNodeOffsetInput({
    required this.node,
    required this.linkedNodes,
    required this.direction,
    this.spacing,
  });

  final DirectionalNodeBounds node;
  final List<DirectionalNodeBounds> linkedNodes;
  final DirectionalGraphDirection direction;
  final DirectionalNodeSpacing? spacing;
}

Point computeDirectionalNodeOffset(ComputeDirectionalNodeOffsetInput input) {
  final horizontalOffset =
      input.spacing?.horizontal ?? _defaultHorizontalOffset;
  final verticalOffset = input.spacing?.vertical ?? _defaultVerticalOffset;
  final withNodeHorizontalOffset = horizontalOffset + input.node.width;
  final withNodeVerticalOffset = verticalOffset + input.node.height;

  if (input.direction == 'up' || input.direction == 'down') {
    final minX = input.node.x;
    final maxX = input.node.x + input.node.width;
    final noOverlap = input.linkedNodes.every(
      (linkedNode) =>
          linkedNode.x + linkedNode.width < minX || linkedNode.x > maxX,
    );
    if (noOverlap) {
      return <double>[
        0,
        withNodeVerticalOffset * (input.direction == 'up' ? -1 : 1),
      ];
    }
  } else {
    final minY = input.node.y;
    final maxY = input.node.y + input.node.height;
    final noOverlap = input.linkedNodes.every(
      (linkedNode) =>
          linkedNode.y + linkedNode.height < minY || linkedNode.y > maxY,
    );
    if (noOverlap) {
      return <double>[
        withNodeHorizontalOffset * (input.direction == 'left' ? -1 : 1),
        0,
      ];
    }
  }

  if (input.direction == 'up' || input.direction == 'down') {
    final length = input.linkedNodes.length;
    final x = length == 0
        ? 0.0
        : (length + 1).isEven
        ? ((length + 1) / 2) * withNodeHorizontalOffset
        : (length / 2) * withNodeHorizontalOffset * -1;
    final y = withNodeVerticalOffset * (input.direction == 'up' ? -1 : 1);
    return <double>[x, y];
  }

  final x = withNodeHorizontalOffset * (input.direction == 'left' ? -1 : 1);
  final length = input.linkedNodes.length;
  final y = length == 0
      ? 0.0
      : (length + 1).isEven
      ? ((length + 1) / 2) * withNodeVerticalOffset
      : (length / 2) * withNodeVerticalOffset * -1;
  return <double>[x, y];
}

class ComputeDirectionalNodeBatchOffsetsInput {
  const ComputeDirectionalNodeBatchOffsetsInput({
    required this.node,
    required this.direction,
    required this.count,
    this.spacing,
  });

  final DirectionalNodeBounds node;
  final DirectionalGraphDirection direction;
  final int count;
  final DirectionalNodeSpacing? spacing;
}

List<Point> computeDirectionalNodeBatchOffsets(
  ComputeDirectionalNodeBatchOffsetsInput input,
) {
  final count = input.count < 0 ? 0 : input.count;
  if (count == 0) {
    return <Point>[];
  }

  final horizontalOffset =
      input.spacing?.horizontal ?? _defaultHorizontalOffset;
  final verticalOffset = input.spacing?.vertical ?? _defaultVerticalOffset;
  final offsets = <Point>[];

  if (input.direction == 'left' || input.direction == 'right') {
    final totalHeight =
        verticalOffset * (count - 1) + count * input.node.height;
    final startY = input.node.y + input.node.height / 2 - totalHeight / 2;
    final offsetX =
        (horizontalOffset + input.node.width) *
        (input.direction == 'left' ? -1 : 1);

    for (var index = 0; index < count; index += 1) {
      final nextX = input.node.x + offsetX;
      final nextY = startY + (verticalOffset + input.node.height) * index;
      offsets.add(<double>[nextX - input.node.x, nextY - input.node.y]);
    }
    return offsets;
  }

  final totalWidth = horizontalOffset * (count - 1) + count * input.node.width;
  final startX = input.node.x + input.node.width / 2 - totalWidth / 2;
  final offsetY =
      (verticalOffset + input.node.height) * (input.direction == 'up' ? -1 : 1);

  for (var index = 0; index < count; index += 1) {
    final nextX = startX + (horizontalOffset + input.node.width) * index;
    final nextY = input.node.y + offsetY;
    offsets.add(<double>[nextX - input.node.x, nextY - input.node.y]);
  }

  return offsets;
}

const List<DirectionalGraphDirection> _directionSequence = <String>[
  'up',
  'right',
  'down',
  'left',
];

class DirectionalNavigatorExploreInput {
  const DirectionalNavigatorExploreInput({
    required this.nodeId,
    required this.direction,
    required this.nodes,
    required this.arrows,
    this.options,
  });

  final String nodeId;
  final DirectionalGraphDirection direction;
  final List<DirectionalFlowNodeState> nodes;
  final List<DirectionalFlowArrowState> arrows;
  final ResolveDirectionalNodeRelationsOptions? options;
}

class DirectionalArrowNavigator {
  bool _exploring = false;
  List<String> _sameLevelNodeIds = <String>[];
  int _sameLevelIndex = 0;
  DirectionalGraphDirection? _direction;
  final Set<String> _visitedNodeIds = <String>{};

  bool get isExploring => _exploring;

  void clear() {
    _exploring = false;
    _sameLevelNodeIds = <String>[];
    _sameLevelIndex = 0;
    _direction = null;
    _visitedNodeIds.clear();
  }

  String? exploreByDirection(DirectionalNavigatorExploreInput input) {
    if (input.direction != _direction) {
      clear();
    }

    _visitedNodeIds.add(input.nodeId);

    if (_exploring &&
        input.direction == _direction &&
        _sameLevelNodeIds.length > 1) {
      _sameLevelIndex = (_sameLevelIndex + 1) % _sameLevelNodeIds.length;
      return _sameLevelNodeIds[_sameLevelIndex];
    }

    final directionalNodeIds = <String>[
      ...getDirectionalSuccessorIds(
        ResolveDirectionalNodeRelationsInput(
          type: 'successors',
          nodeId: input.nodeId,
          direction: input.direction,
          nodes: input.nodes,
          arrows: input.arrows,
          options: input.options,
        ),
      ),
      ...getDirectionalPredecessorIds(
        ResolveDirectionalNodeRelationsInput(
          type: 'predecessors',
          nodeId: input.nodeId,
          direction: input.direction,
          nodes: input.nodes,
          arrows: input.arrows,
          options: input.options,
        ),
      ),
    ];

    if (directionalNodeIds.isNotEmpty) {
      _sameLevelIndex = 0;
      _exploring = true;
      _sameLevelNodeIds = List<String>.from(directionalNodeIds);
      _direction = input.direction;
      _visitedNodeIds.add(directionalNodeIds.first);
      return directionalNodeIds.first;
    }

    if (input.direction == _direction || !_exploring) {
      if (!_exploring) {
        _visitedNodeIds.add(input.nodeId);
      }

      final otherDirections = _directionSequence
          .where((direction) => direction != input.direction)
          .toList(growable: false);

      final otherLinkedNodeIds = otherDirections
          .expand(
            (direction) => <String>[
              ...getDirectionalSuccessorIds(
                ResolveDirectionalNodeRelationsInput(
                  type: 'successors',
                  nodeId: input.nodeId,
                  direction: direction,
                  nodes: input.nodes,
                  arrows: input.arrows,
                  options: input.options,
                ),
              ),
              ...getDirectionalPredecessorIds(
                ResolveDirectionalNodeRelationsInput(
                  type: 'predecessors',
                  nodeId: input.nodeId,
                  direction: direction,
                  nodes: input.nodes,
                  arrows: input.arrows,
                  options: input.options,
                ),
              ),
            ],
          )
          .where((nodeId) => !_visitedNodeIds.contains(nodeId))
          .toList(growable: false);

      for (final nodeId in otherLinkedNodeIds) {
        if (!_visitedNodeIds.contains(nodeId)) {
          _visitedNodeIds.add(nodeId);
          _exploring = true;
          _direction = input.direction;
          return nodeId;
        }
      }
    }

    return null;
  }
}

bool isNodeLinkedByArrow(
  String nodeId,
  List<DirectionalFlowArrowState> arrows,
) => arrows.any(
  (arrow) =>
      arrow.startBinding?.elementId == nodeId ||
      arrow.endBinding?.elementId == nodeId,
);
