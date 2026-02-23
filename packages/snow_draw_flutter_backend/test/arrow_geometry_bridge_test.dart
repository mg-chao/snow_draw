import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/render/geometry/arrow_geometry.dart';

void main() {
  group('ArrowGeometry bridge', () {
    test('resolveWorldPoints stays aligned with core geometry math', () {
      const rect = DrawRect(minX: 10, minY: 20, maxX: 110, maxY: 220);
      const normalizedPoints = <DrawPoint>[
        DrawPoint(x: 0.1, y: 0.2),
        DrawPoint(x: 0.8, y: 0.7),
      ];

      final backendPoints = FlutterArrowGeometry.resolveWorldPoints(
        rect: rect,
        normalizedPoints: normalizedPoints,
      );
      final corePoints = ArrowGeometry.resolveWorldPoints(
        rect: rect,
        normalizedPoints: normalizedPoints,
      );

      expect(backendPoints.length, corePoints.length);
      for (var i = 0; i < backendPoints.length; i++) {
        _expectOffsetMatchesDrawPoint(backendPoints[i], corePoints[i]);
      }
    });

    test('descriptor exposes core inset and direction outputs', () {
      const rect = DrawRect(maxX: 200, maxY: 120);
      const data = ArrowData(
        points: <DrawPoint>[
          DrawPoint(x: 0.05, y: 0.10),
          DrawPoint(x: 0.40, y: 0.25),
          DrawPoint(x: 0.65, y: 0.70),
          DrawPoint(x: 0.90, y: 0.85),
        ],
        arrowType: ArrowType.curved,
        strokeWidth: 5,
        startArrowhead: ArrowheadStyle.triangle,
        endArrowhead: ArrowheadStyle.circle,
      );

      final backendDescriptor = FlutterArrowGeometryDescriptor(
        data: data,
        rect: rect,
      );
      final coreDescriptor = ArrowGeometryDescriptor(data: data, rect: rect);

      expect(
        backendDescriptor.localPoints.length,
        coreDescriptor.localDrawPoints.length,
      );
      for (var i = 0; i < backendDescriptor.localPoints.length; i++) {
        _expectOffsetMatchesDrawPoint(
          backendDescriptor.localPoints[i],
          coreDescriptor.localDrawPoints[i],
        );
      }

      expect(
        backendDescriptor.insetPoints.length,
        coreDescriptor.insetDrawPoints.length,
      );
      for (var i = 0; i < backendDescriptor.insetPoints.length; i++) {
        _expectOffsetMatchesDrawPoint(
          backendDescriptor.insetPoints[i],
          coreDescriptor.insetDrawPoints[i],
        );
      }

      _expectNullableOffsetMatchesDrawPoint(
        backendDescriptor.startDirection,
        coreDescriptor.startDirectionPoint,
      );
      _expectNullableOffsetMatchesDrawPoint(
        backendDescriptor.endDirection,
        coreDescriptor.endDirectionPoint,
      );
    });
  });
}

void _expectOffsetMatchesDrawPoint(Offset offset, DrawPoint point) {
  expect(offset.dx, point.x);
  expect(offset.dy, point.y);
}

void _expectNullableOffsetMatchesDrawPoint(Offset? offset, DrawPoint? point) {
  if (offset == null || point == null) {
    expect(offset, isNull);
    expect(point, isNull);
    return;
  }
  _expectOffsetMatchesDrawPoint(offset, point);
}
