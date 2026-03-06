import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_core.dart'
    as core;
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_label_layout.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_label_layout constraints', () {
    test('computes container dimension and text constraints via core', () {
      final dimension = computeArrowContainerDimensionForBoundText(100);
      final constraints = computeArrowBoundTextConstraints(
        containerWidth: 200,
        containerHeight: 200,
        fontSize: 16,
        boundTextHeight: 12,
      );

      expect(dimension, 180);
      expect(constraints.maxWidth, 176);
      expect(constraints.maxHeight, 200);
    });

    test('respects custom options', () {
      const options = core.ArrowLabelLayoutOptions(
        textPadding: 4,
        widthFraction: 0.5,
        fontSizeToMinWidthRatio: 10,
        paddingMultiplier: 6,
      );

      final dimension = computeArrowContainerDimensionForBoundText(
        80,
        options: options,
      );
      final constraints = computeArrowBoundTextConstraints(
        containerWidth: 160,
        containerHeight: 160,
        fontSize: 12,
        boundTextHeight: 10,
        options: options,
      );

      expect(dimension, 128);
      expect(constraints.maxWidth, 120);
      expect(constraints.maxHeight, 160);
    });
  });

  group('arrow_label_layout anchor and position', () {
    test('resolves anchor for odd and even point counts', () {
      final oddAnchor = resolveArrowLabelAnchorPoint(
        worldPoints: const <DrawPoint>[
          DrawPoint.zero,
          DrawPoint(x: 50, y: 30),
          DrawPoint(x: 100, y: 0),
        ],
      );
      final evenAnchor = resolveArrowLabelAnchorPoint(
        worldPoints: const <DrawPoint>[DrawPoint.zero, DrawPoint(x: 100, y: 0)],
      );

      expect(oddAnchor, const DrawPoint(x: 50, y: 30));
      expect(evenAnchor, const DrawPoint(x: 50, y: 0));
    });

    test('resolves bound text position from arrow points', () {
      final position = resolveArrowBoundTextPosition(
        worldPoints: const <DrawPoint>[DrawPoint.zero, DrawPoint(x: 100, y: 0)],
        boundTextWidth: 40,
        boundTextHeight: 20,
      );

      expect(position, const DrawPoint(x: 30, y: -10));
    });

    test('resolves anchor and position for element snapshots', () {
      final element = _arrowElement(
        id: 'arrow-1',
        points: const <DrawPoint>[
          DrawPoint(x: 20, y: 20),
          DrawPoint(x: 70, y: 50),
          DrawPoint(x: 140, y: 20),
        ],
      );
      final data = element.data as ArrowData;

      final anchor = resolveArrowLabelAnchorPointForElement(
        element: element,
        data: data,
      );
      final position = resolveArrowBoundTextPositionForElement(
        element: element,
        data: data,
        boundTextWidth: 60,
        boundTextHeight: 24,
      );

      expect(anchor, const DrawPoint(x: 70, y: 50));
      expect(position, const DrawPoint(x: 40, y: 38));
    });
  });

  group('arrow_label_layout bound-aware bounds', () {
    test('expands linear bounds to include bound text', () {
      final bounds = resolveLinearBoundsWithBoundText(
        elementBounds: const DrawRect(maxX: 100, maxY: 40),
        boundTextBounds: const DrawRect(
          minX: 120,
          minY: 10,
          maxX: 160,
          maxY: 30,
        ),
        angle: 0,
      );

      expect(bounds.rect.minX, 0);
      expect(bounds.rect.maxX, 160);
      expect(bounds.rect.minY, 0);
      expect(bounds.rect.maxY, 40);
      expect(bounds.center, const DrawPoint(x: 50, y: 20));
    });
  });
}

ElementState _arrowElement({
  required String id,
  required List<DrawPoint> points,
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
    zIndex: 0,
    data: ArrowData(points: normalized),
  );
}
