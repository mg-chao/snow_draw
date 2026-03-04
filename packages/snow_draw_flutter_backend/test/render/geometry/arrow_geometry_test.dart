import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/render/geometry/arrow_geometry.dart';

void main() {
  group('FlutterArrowGeometry elbow integration', () {
    test(
      'buildShaftPathFromResolvedPoints rounds elbow corners via core path',
      () {
        const points = <Offset>[Offset.zero, Offset(100, 0), Offset(100, 100)];

        final elbowPath = FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
          points: points,
          arrowType: ArrowType.elbow,
        );
        final straightPath =
            FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
              points: points,
              arrowType: ArrowType.straight,
            );

        final elbowLength = _totalPathLength(elbowPath);
        final straightLength = _totalPathLength(straightPath);

        expect(elbowLength, lessThan(straightLength));
        expect(elbowLength, greaterThan(150));
      },
    );

    test('buildShaftPathFromResolvedPoints preserves elbow endpoints', () {
      const points = <Offset>[Offset.zero, Offset(100, 0), Offset(100, 100)];

      final path = FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
        points: points,
        arrowType: ArrowType.elbow,
      );
      final metric = path.computeMetrics().first;

      final start = metric.getTangentForOffset(0);
      expect(start, isNotNull);
      expect(start!.position.dx, closeTo(points.first.dx, 1e-6));
      expect(start.position.dy, closeTo(points.first.dy, 1e-6));

      final endProbeOffset = metric.length > 1e-3
          ? metric.length - 1e-3
          : metric.length;
      final end = metric.getTangentForOffset(endProbeOffset);
      expect(end, isNotNull);
      expect(end!.position.dx, closeTo(points.last.dx, 1e-2));
      expect(end.position.dy, closeTo(points.last.dy, 1e-2));
    });

    test(
      'buildShaftPathFromResolvedPoints keeps two-point elbows straight',
      () {
        const points = <Offset>[Offset.zero, Offset(100, 0)];
        final path = FlutterArrowGeometry.buildShaftPathFromResolvedPoints(
          points: points,
          arrowType: ArrowType.elbow,
        );

        expect(_totalPathLength(path), closeTo(100, 1e-6));
      },
    );
  });

  group('FlutterArrowGeometry arrowhead integration', () {
    const straightPoints = <Offset>[Offset.zero, Offset(100, 0)];

    test('triangle arrowhead returns both stroke and fill paths', () {
      final paths = FlutterArrowGeometry.buildArrowheadPaths(
        points: straightPoints,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.triangle,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
      );

      expect(paths.strokePath.getBounds().isEmpty, isFalse);
      expect(paths.fillPath.getBounds().isEmpty, isFalse);
    });

    test('standard arrowhead returns stroke path without fill path', () {
      final paths = FlutterArrowGeometry.buildArrowheadPaths(
        points: straightPoints,
        arrowType: ArrowType.straight,
        style: ArrowheadStyle.standard,
        strokeStyle: StrokeStyle.solid,
        strokeWidth: 2,
        position: ArrowEndpointPosition.end,
      );

      expect(paths.strokePath.getBounds().isEmpty, isFalse);
      expect(paths.fillPath.getBounds().isEmpty, isTrue);
    });
  });
}

double _totalPathLength(Path path) {
  var total = 0.0;
  for (final metric in path.computeMetrics()) {
    total += metric.length;
  }
  return total;
}
