import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding_resolver.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/connector/connector_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/connector/connector_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowBindingResolver', () {
    test('recompute keeps middle points moving with dual-bound target', () {
      const bindable = ElementState(
        id: 'bindable-1',
        rect: DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final arrow = _buildArrowBoundToSingleTarget(
        id: 'arrow-1',
        targetId: bindable.id,
        zIndex: 1,
        worldPoints: const <DrawPoint>[
          DrawPoint(x: 100, y: 160),
          DrawPoint(x: 160, y: 120),
          DrawPoint(x: 220, y: 160),
        ],
      );

      const dragDelta = DrawPoint(x: 40, y: 20);
      final movedBindable = bindable.copyWith(
        rect: bindable.rect.translate(dragDelta),
      );
      final originalWorldPoints = _resolveWorldPoints(arrow);

      final resolution = ArrowBindingResolver.instance.resolve(
        baseElements: <String, ElementState>{
          bindable.id: bindable,
          arrow.id: arrow,
        },
        updatedElements: <String, ElementState>{bindable.id: movedBindable},
        changedElementIds: <String>{bindable.id},
        orderedElementIds: <String>[bindable.id, arrow.id],
      );

      final updatedArrow = resolution.updatedElements[arrow.id];
      expect(updatedArrow, isNotNull);

      final updatedWorldPoints = _resolveWorldPoints(updatedArrow!);
      expect(updatedWorldPoints, hasLength(3));
      for (var index = 0; index < updatedWorldPoints.length; index += 1) {
        expect(
          updatedWorldPoints[index].x - originalWorldPoints[index].x,
          closeTo(dragDelta.x, 0.05),
        );
        expect(
          updatedWorldPoints[index].y - originalWorldPoints[index].y,
          closeTo(dragDelta.y, 0.05),
        );
      }
    });

    test('skips recomputing arrows that are simultaneously updated', () {
      const bindable = ElementState(
        id: 'bindable-1',
        rect: DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final arrow = _buildArrowBoundToSingleTarget(
        id: 'arrow-1',
        targetId: bindable.id,
        zIndex: 1,
        worldPoints: const <DrawPoint>[
          DrawPoint(x: 100, y: 160),
          DrawPoint(x: 160, y: 120),
          DrawPoint(x: 220, y: 160),
        ],
      );
      final baseArrowPoints = _resolveWorldPoints(arrow);
      final movedBindable = bindable.copyWith(
        rect: bindable.rect.translate(const DrawPoint(x: 40, y: 20)),
      );
      final movedArrow = _copyArrowWithWorldPoints(
        arrow,
        _translatePoints(baseArrowPoints, const DrawPoint(x: 5, y: 5)),
      );

      final withoutSkip = ArrowBindingResolver.instance.resolve(
        baseElements: <String, ElementState>{
          bindable.id: bindable,
          arrow.id: arrow,
        },
        updatedElements: <String, ElementState>{
          bindable.id: movedBindable,
          arrow.id: movedArrow,
        },
        changedElementIds: <String>{bindable.id, arrow.id},
        orderedElementIds: <String>[bindable.id, arrow.id],
      );
      final withSkip = ArrowBindingResolver.instance.resolve(
        baseElements: <String, ElementState>{
          bindable.id: bindable,
          arrow.id: arrow,
        },
        updatedElements: <String, ElementState>{
          bindable.id: movedBindable,
          arrow.id: movedArrow,
        },
        changedElementIds: <String>{bindable.id, arrow.id},
        orderedElementIds: <String>[bindable.id, arrow.id],
        skipArrowIds: <String>{arrow.id},
      );

      expect(withoutSkip.updatedElements.containsKey(arrow.id), isTrue);
      expect(withSkip.updatedElements.containsKey(arrow.id), isFalse);
    });
  });
}

ElementState _buildArrowBoundToSingleTarget({
  required String id,
  required String targetId,
  required int zIndex,
  required List<DrawPoint> worldPoints,
}) {
  final rect = DrawRect.fromPointCloud(worldPoints);
  final normalized = ConnectorGeometry.normalizePoints(
    worldPoints: worldPoints,
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
      startBinding: ArrowBinding(
        elementId: targetId,
        anchor: const DrawPoint(x: 0, y: 0.5),
      ),
      endBinding: ArrowBinding(
        elementId: targetId,
        anchor: const DrawPoint(x: 1, y: 0.5),
      ),
    ),
  );
}

List<DrawPoint> _resolveWorldPoints(ElementState arrowElement) {
  final data = arrowElement.data as ConnectorData;
  return ConnectorGeometry.resolveWorldPoints(
    rect: arrowElement.rect,
    normalizedPoints: data.points,
  );
}

List<DrawPoint> _translatePoints(List<DrawPoint> points, DrawPoint delta) => [
  for (final point in points)
    DrawPoint(x: point.x + delta.x, y: point.y + delta.y),
];

ElementState _copyArrowWithWorldPoints(
  ElementState arrowElement,
  List<DrawPoint> worldPoints,
) {
  final data = arrowElement.data as ArrowData;
  final rect = DrawRect.fromPointCloud(worldPoints);
  final normalized = ConnectorGeometry.normalizePoints(
    worldPoints: worldPoints,
    rect: rect,
  );
  return arrowElement.copyWith(
    rect: rect,
    data: data.copyWith(points: normalized),
  );
}
