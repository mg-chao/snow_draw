import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_focus.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('Arrow focus core integration', () {
    test('listVisibleArrowFocusPoints exposes bound start focus point', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement();
      final data = arrow.data as ArrowData;

      final focusPoints = listVisibleArrowFocusPoints(
        element: arrow,
        data: data,
        elements: <ElementState>[bindable, arrow],
      );

      expect(focusPoints, hasLength(1));
      expect(focusPoints.single.endpoint, ArrowFocusEndpoint.start);
      expect(focusPoints.single.binding.elementId, bindable.id);
    });

    test('pickArrowFocusPoint detects start focus point hit', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement();
      final data = arrow.data as ArrowData;
      final focusPoint = listVisibleArrowFocusPoints(
        element: arrow,
        data: data,
        elements: <ElementState>[bindable, arrow],
      ).single;

      final edge = pickArrowFocusPoint(
        element: arrow,
        data: data,
        elements: <ElementState>[bindable, arrow],
        pointer: focusPoint.position,
      );
      final hit = pickArrowFocusPointWithOffset(
        element: arrow,
        data: data,
        elements: <ElementState>[bindable, arrow],
        pointer: focusPoint.position,
      );

      expect(edge, ArrowFocusEndpoint.start);
      expect(hit.endpoint, ArrowFocusEndpoint.start);
      expect(hit.pointerOffset.x, closeTo(0, 1e-6));
      expect(hit.pointerOffset.y, closeTo(0, 1e-6));
    });

    test(
      'dragArrowFocusPoint supports switching dragged endpoint to inside',
      () {
        final bindable = _bindableElement();
        final arrow = _boundArrowElement();
        final data = arrow.data as ArrowData;
        final result = dragArrowFocusPoint(
          element: arrow,
          data: data,
          elementsById: <String, ElementState>{
            bindable.id: bindable,
            arrow.id: arrow,
          },
          draggedEndpoint: ArrowFocusEndpoint.start,
          pointer: const DrawPoint(x: 40, y: 40),
          switchToInsideBinding: true,
        );

        final updatedData = result.element.data as ArrowData;
        expect(updatedData.startBinding, isNotNull);
        expect(updatedData.startBinding!.mode, ArrowBindingMode.inside);
        expect(result.elementChanged, isTrue);
        expect(result.hasChanges, isTrue);
        expect(result.suggestedBindableId, bindable.id);
      },
    );

    test('dragArrowFocusPoint reorders arrow above suggested bindable', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement().copyWith(zIndex: 0);
      final data = arrow.data as ArrowData;
      final focusPoint = listVisibleArrowFocusPoints(
        element: arrow,
        data: data,
        elements: <ElementState>[arrow, bindable],
      ).single;
      final result = dragArrowFocusPoint(
        element: arrow,
        data: data,
        elementsById: <String, ElementState>{
          arrow.id: arrow,
          bindable.id: bindable,
        },
        draggedEndpoint: ArrowFocusEndpoint.start,
        pointer: focusPoint.position,
        orderedElementIds: const <String>['arrow-1', 'bindable-1'],
      );

      expect(result.suggestedBindableId, bindable.id);
      expect(result.orderedElementIds, <String>['bindable-1', 'arrow-1']);
    });
  });
}

ElementState _bindableElement() => const ElementState(
  id: 'bindable-1',
  rect: DrawRect(maxX: 100, maxY: 100),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

ElementState _boundArrowElement() => const ElementState(
  id: 'arrow-1',
  rect: DrawRect(minX: 120, minY: 20, maxX: 320, maxY: 21),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: ArrowData(
    points: <DrawPoint>[DrawPoint(x: 0, y: 0.5), DrawPoint(x: 1, y: 0.5)],
    startBinding: ArrowBinding(
      elementId: 'bindable-1',
      anchor: DrawPoint(x: 1, y: 0.5),
    ),
  ),
);
