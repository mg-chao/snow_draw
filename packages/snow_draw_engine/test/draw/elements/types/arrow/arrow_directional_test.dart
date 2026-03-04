import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_directional.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_directional projection', () {
    test('projects bindable nodes and filters unbound arrows', () {
      final nodeA = _rectangleElement(
        id: 'node-a',
        rect: const DrawRect(maxX: 100, maxY: 60),
        zIndex: 0,
      );
      final nodeB = _rectangleElement(
        id: 'node-b',
        rect: const DrawRect(minX: 260, maxX: 360, maxY: 60),
        zIndex: 1,
      );
      final boundArrow = _arrowElement(
        id: 'arrow-bound',
        points: const <DrawPoint>[
          DrawPoint(x: 100, y: 30),
          DrawPoint(x: 260, y: 30),
        ],
        zIndex: 2,
        startBinding: const ArrowBinding(
          elementId: 'node-a',
          anchor: DrawPoint(x: 1, y: 0.5),
        ),
        endBinding: const ArrowBinding(
          elementId: 'node-b',
          anchor: DrawPoint(x: 0, y: 0.5),
        ),
      );
      final unboundArrow = _arrowElement(
        id: 'arrow-unbound',
        points: const <DrawPoint>[
          DrawPoint(x: 20, y: 100),
          DrawPoint(x: 180, y: 120),
        ],
        zIndex: 3,
      );

      final projection = projectArrowDirectionalGraph(<ElementState>[
        nodeA,
        nodeB,
        boundArrow,
        unboundArrow,
      ]);

      expect(
        projection.nodes.map((node) => node.id),
        containsAll(<String>['node-a', 'node-b']),
      );
      expect(projection.arrows, hasLength(1));
      expect(projection.arrows.first.id, boundArrow.id);
    });
  });

  group('arrow_directional relation lookup', () {
    test('resolves directional successors and predecessors', () {
      final elements = _linkedDirectionalElements();

      final successors = getDirectionalSuccessorIds(
        nodeId: 'node-a',
        direction: 'right',
        elements: elements,
      );
      final predecessors = getDirectionalPredecessorIds(
        nodeId: 'node-b',
        direction: 'left',
        elements: elements,
      );

      expect(successors, contains('node-b'));
      expect(predecessors, contains('node-a'));
    });

    test('navigator explores directionally linked node ids', () {
      final navigator = ArrowDirectionalNavigator();

      final nextNodeId = navigator.exploreByDirection(
        nodeId: 'node-a',
        direction: 'right',
        elements: _linkedDirectionalElements(),
      );

      expect(nextNodeId, 'node-b');
      expect(navigator.isExploring, isTrue);

      navigator.clear();
      expect(navigator.isExploring, isFalse);
    });

    test('isNodeLinkedByDirectionalArrow reflects graph connectivity', () {
      final linked = _linkedDirectionalElements();
      final unlinked = _linkedDirectionalElements(includeStandaloneNode: true);

      expect(
        isNodeLinkedByDirectionalArrow(nodeId: 'node-a', elements: linked),
        isTrue,
      );
      expect(
        isNodeLinkedByDirectionalArrow(nodeId: 'node-c', elements: unlinked),
        isFalse,
      );
    });
  });

  group('arrow_directional offset helpers', () {
    test('computes deterministic directional single-node offset', () {
      final offset = computeDirectionalNodeOffset(
        nodeBounds: const DrawRect(maxX: 100, maxY: 50),
        linkedNodeBounds: const <DrawRect>[],
        direction: 'right',
        spacing: const ArrowDirectionalSpacing(horizontal: 80, vertical: 60),
      );

      expect(offset, const DrawPoint(x: 180, y: 0));
    });

    test('computes directional batch offsets', () {
      final offsets = computeDirectionalNodeBatchOffsets(
        nodeBounds: const DrawRect(maxX: 100, maxY: 50),
        direction: 'down',
        count: 3,
        spacing: const ArrowDirectionalSpacing(horizontal: 80, vertical: 60),
      );

      expect(offsets, hasLength(3));
      expect(offsets[0].x, closeTo(-180, 0.0001));
      expect(offsets[1], const DrawPoint(x: 0, y: 110));
      expect(offsets[2].x, closeTo(180, 0.0001));
      expect(offsets.every((offset) => offset.y == 110), isTrue);
    });
  });
}

List<ElementState> _linkedDirectionalElements({
  bool includeStandaloneNode = false,
}) {
  final nodeA = _rectangleElement(
    id: 'node-a',
    rect: const DrawRect(maxX: 100, maxY: 60),
    zIndex: 0,
  );
  final nodeB = _rectangleElement(
    id: 'node-b',
    rect: const DrawRect(minX: 260, maxX: 360, maxY: 60),
    zIndex: 1,
  );
  final arrow = _arrowElement(
    id: 'arrow-ab',
    points: const <DrawPoint>[
      DrawPoint(x: 100, y: 30),
      DrawPoint(x: 260, y: 30),
    ],
    zIndex: 2,
    startBinding: const ArrowBinding(
      elementId: 'node-a',
      anchor: DrawPoint(x: 1, y: 0.5),
    ),
    endBinding: const ArrowBinding(
      elementId: 'node-b',
      anchor: DrawPoint(x: 0, y: 0.5),
    ),
  );
  final standaloneNode = _rectangleElement(
    id: 'node-c',
    rect: const DrawRect(minY: 200, maxX: 100, maxY: 260),
    zIndex: 3,
  );

  return <ElementState>[
    nodeA,
    nodeB,
    arrow,
    if (includeStandaloneNode) standaloneNode,
  ];
}

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
  required int zIndex,
  ArrowType arrowType = ArrowType.elbow,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: zIndex,
    data: ArrowData(
      points: normalized,
      arrowType: arrowType,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}
