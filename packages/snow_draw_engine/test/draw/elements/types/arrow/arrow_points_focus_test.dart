import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowPointUtils focus integration', () {
    test('buildOverlay exposes focus handles for bound endpoints', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement();

      final overlay = ArrowPointUtils.buildOverlay(
        element: arrow,
        loopThreshold: 16,
        handleSize: 10,
        elements: <ElementState>[bindable, arrow],
      );

      expect(overlay.focusPoints, hasLength(1));
      expect(overlay.focusPoints.single.kind, ArrowPointKind.focusStart);
      expect(overlay.turningPoints.any((handle) => handle.index == 0), isFalse);
    });

    test('hitTest resolves focus handle under pointer', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement();
      final overlay = ArrowPointUtils.buildOverlay(
        element: arrow,
        loopThreshold: 16,
        handleSize: 10,
        elements: <ElementState>[bindable, arrow],
      );
      final focusPoint = overlay.focusPoints.single.position;

      final hit = ArrowPointUtils.hitTest(
        element: arrow,
        position: focusPoint,
        hitRadius: 12,
        loopThreshold: 16,
        handleSize: 10,
        elements: <ElementState>[bindable, arrow],
      );

      expect(hit, isNotNull);
      expect(hit!.kind, ArrowPointKind.focusStart);
      expect(hit.index, 0);
    });

    test('buildOverlay hides focus handles when binding disabled', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement();

      final overlay = ArrowPointUtils.buildOverlay(
        element: arrow,
        loopThreshold: 16,
        handleSize: 10,
        elements: <ElementState>[bindable, arrow],
        isBindingEnabled: false,
      );

      expect(overlay.focusPoints, isEmpty);
      expect(overlay.turningPoints.any((handle) => handle.index == 0), isTrue);
    });

    test('hitTest ignores focus handles when binding disabled', () {
      final bindable = _bindableElement();
      final arrow = _boundArrowElement();
      final overlay = ArrowPointUtils.buildOverlay(
        element: arrow,
        loopThreshold: 16,
        handleSize: 10,
        elements: <ElementState>[bindable, arrow],
      );
      final focusPoint = overlay.focusPoints.single.position;

      final hit = ArrowPointUtils.hitTest(
        element: arrow,
        position: focusPoint,
        hitRadius: 12,
        loopThreshold: 16,
        handleSize: 10,
        elements: <ElementState>[bindable, arrow],
        isBindingEnabled: false,
      );

      expect(hit, isNull);
    });
  });
}

ElementState _bindableElement() => const ElementState(
  id: 'bindable-focus',
  rect: DrawRect(maxX: 100, maxY: 100),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

ElementState _boundArrowElement() => const ElementState(
  id: 'arrow-focus',
  rect: DrawRect(minX: 120, minY: 20, maxX: 320, maxY: 21),
  rotation: 0,
  opacity: 1,
  zIndex: 1,
  data: ArrowData(
    points: <DrawPoint>[DrawPoint(x: 0, y: 0.5), DrawPoint(x: 1, y: 0.5)],
    startBinding: ArrowBinding(
      elementId: 'bindable-focus',
      anchor: DrawPoint(x: 1, y: 0.5),
    ),
  ),
);
