import 'package:snow_draw_engine/draw/actions/draw_actions.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_routing_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/reducers/element/delete_element_handler.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('delete_element_handler arrow lifecycle sync', () {
    test('deleting a bindable clears dependent arrow endpoint bindings', () {
      final elements = _buildScenarioElements();
      final state = _stateWithElements(elements);

      final next = handleDeleteElements(
        state,
        DeleteElements(elementIds: ['r2']),
        DrawContext.withDefaults(),
      );

      expect(next.domain.document.elementMap.containsKey('r2'), isFalse);

      final arrow = next.domain.document.getElementById('a1');
      expect(arrow, isNotNull);

      final data = arrow!.data as ArrowData;
      expect(data.startBinding?.elementId, 'r1');
      expect(data.endBinding, isNull);
    });

    test('duplicating arrows remaps bindings to duplicated bindables', () {
      final elements = _buildScenarioElements();
      final state = _stateWithElements(elements);
      final context = DrawContext.withDefaults(
        idGenerator: _idGeneratorFrom(<String>['dup-r1', 'dup-r2', 'dup-a1']),
      );

      final next = handleDuplicateElements(
        state,
        DuplicateElements(
          elementIds: ['r1', 'r2', 'a1'],
          offsetX: 24,
          offsetY: 16,
        ),
        context,
      );

      final duplicatedArrow = next.domain.document.getElementById('dup-a1');
      expect(duplicatedArrow, isNotNull);

      final duplicatedData = duplicatedArrow!.data as ArrowData;
      expect(duplicatedData.startBinding?.elementId, 'dup-r1');
      expect(duplicatedData.endBinding?.elementId, 'dup-r2');

      final sourceArrow = state.domain.document.getElementById('a1')!;
      expect(
        duplicatedArrow.rect.minX,
        closeTo(sourceArrow.rect.minX + 24, 0.1),
      );
      expect(
        duplicatedArrow.rect.minY,
        closeTo(sourceArrow.rect.minY + 16, 0.1),
      );
    });
  });
}

DrawState _stateWithElements(List<ElementState> elements) => DrawState(
  domain: DomainState(document: DocumentState(elements: elements)),
);

List<ElementState> _buildScenarioElements() {
  const startBinding = ArrowBinding(
    elementId: 'r1',
    anchor: DrawPoint(x: 1, y: 0.5),
  );
  const endBinding = ArrowBinding(
    elementId: 'r2',
    anchor: DrawPoint(x: 0, y: 0.5),
  );

  const rect1 = ElementState(
    id: 'r1',
    rect: DrawRect(maxX: 100, maxY: 100),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  );
  const rect2 = ElementState(
    id: 'r2',
    rect: DrawRect(minX: 300, maxX: 400, maxY: 100),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  );

  final arrowPoints = <DrawPoint>[
    const DrawPoint(x: 100, y: 50),
    const DrawPoint(x: 200, y: 50),
    const DrawPoint(x: 200, y: 120),
    const DrawPoint(x: 300, y: 120),
    const DrawPoint(x: 300, y: 50),
  ];
  final arrowRect = DrawRect.fromPointCloud(arrowPoints);
  final normalizedArrowPoints = ArrowGeometry.normalizePoints(
    worldPoints: arrowPoints,
    rect: arrowRect,
  );
  final arrow = ElementState(
    id: 'a1',
    rect: arrowRect,
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: ArrowData(
      points: normalizedArrowPoints,
      arrowType: ArrowType.elbow,
      startArrowhead: ArrowheadStyle.standard,
      startBinding: startBinding,
      endBinding: endBinding,
      elbowRoutingData: const ElbowRoutingData(
        startIsSpecial: true,
        endIsSpecial: true,
      ),
    ),
  );

  return <ElementState>[rect1, rect2, arrow];
}

String Function() _idGeneratorFrom(List<String> ids) {
  var index = 0;
  return () {
    if (index >= ids.length) {
      final generated = 'generated-$index';
      index += 1;
      return generated;
    }
    final value = ids[index];
    index += 1;
    return value;
  };
}
