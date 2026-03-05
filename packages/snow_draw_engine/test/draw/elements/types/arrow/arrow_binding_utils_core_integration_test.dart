import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_layout.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowBindingUtils core integration', () {
    test('resolveBindingCandidate resolves nearby rectangle via core', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        zIndex: 3,
      );

      final result = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: const DrawPoint(x: 160, y: 160),
        targets: <ElementState>[target],
        snapDistance: 48,
      );

      expect(result, isNotNull);
      expect(result!.binding.elementId, target.id);
      expect(result.zIndex, target.zIndex);
    });

    test('resolveBindingCandidate supports alt-key inside mode via core', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        zIndex: 3,
      );

      final orbit = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: const DrawPoint(x: 160, y: 160),
        targets: <ElementState>[target],
        snapDistance: 48,
      );
      final inside = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: const DrawPoint(x: 160, y: 160),
        targets: <ElementState>[target],
        snapDistance: 48,
        altKey: true,
      );

      expect(orbit, isNotNull);
      expect(inside, isNotNull);
      expect(orbit!.binding.mode, ArrowBindingMode.orbit);
      expect(inside!.binding.mode, ArrowBindingMode.inside);
    });

    test('resolveBindingCandidate supports new-arrow initial binding '
        'for start drag', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        zIndex: 3,
      );

      final result = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: const DrawPoint(x: 160, y: 160),
        targets: <ElementState>[target],
        snapDistance: 48,
        referencePoint: const DrawPoint(x: 280, y: 160),
        dragStart: true,
        newArrow: true,
        initialBinding: true,
      );

      expect(result, isNotNull);
      expect(result!.binding.elementId, target.id);
      expect(result.binding.mode, ArrowBindingMode.inside);
    });

    test('resolveBindingCandidate supports highlight ellipse bindables', () {
      final target = _highlightElement(
        id: 'highlight-1',
        rect: const DrawRect(minX: 80, minY: 80, maxX: 240, maxY: 220),
        zIndex: 7,
      );

      final result = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: const DrawPoint(x: 160, y: 150),
        targets: <ElementState>[target],
        snapDistance: 56,
      );

      expect(result, isNotNull);
      expect(result!.binding.elementId, target.id);
      expect(result.zIndex, target.zIndex);
    });

    test('resolveBindingCandidate respects allowNewBinding=false '
        'with preferred target', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        zIndex: 3,
      );

      final result = ArrowBindingUtils.resolveBindingCandidate(
        worldPoint: const DrawPoint(x: 160, y: 160),
        targets: <ElementState>[target],
        snapDistance: 48,
        preferredBinding: const ArrowBinding(
          elementId: 'other-target',
          anchor: DrawPoint(x: 0.5, y: 0.5),
        ),
        allowNewBinding: false,
      );

      expect(result, isNull);
    });

    test('resolveBindingGap uses serial-number scaled stroke width', () {
      const serialData = SerialNumberData(fontSize: 42);
      const serial = ElementState(
        id: 'serial-1',
        rect: DrawRect(maxX: 100, maxY: 100),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: serialData,
      );

      final gap = ArrowBindingUtils.resolveBindingGap(target: serial);
      final expectedGap =
          5 + resolveSerialNumberStrokeWidth(data: serialData) / 2;

      expect(gap, closeTo(expectedGap, 1e-6));
    });

    test('resolveBoundPoint returns inside anchor for inside mode', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        zIndex: 3,
      );
      const binding = ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 0.25, y: 0.75),
        mode: ArrowBindingMode.inside,
      );

      final bound = ArrowBindingUtils.resolveBoundPoint(
        binding: binding,
        target: target,
        referencePoint: const DrawPoint(x: 40, y: 160),
      );

      expect(bound, isNotNull);
      expect(bound!.x, closeTo(130, 1e-6));
      expect(bound.y, closeTo(190, 1e-6));
    });

    test('resolveElbowBoundPoint returns an orbit point for elbow edge', () {
      final target = _rectangleElement(
        id: 'rect-1',
        rect: const DrawRect(minX: 100, minY: 100, maxX: 220, maxY: 220),
        zIndex: 3,
      );
      const binding = ArrowBinding(
        elementId: 'rect-1',
        anchor: DrawPoint(x: 1, y: 0.5),
      );

      final bound = ArrowBindingUtils.resolveElbowBoundPoint(
        binding: binding,
        target: target,
        hasArrowhead: true,
      );

      expect(bound, isNotNull);
      expect(bound!.x, greaterThanOrEqualTo(220));
      expect(bound.y, closeTo(160, 2));
    });
  });
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

ElementState _highlightElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const HighlightData(shape: HighlightShape.ellipse),
);
