import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/services/grid_snap_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('GridSnapService', () {
    const service = GridSnapService();

    test('snapValue snaps to the nearest grid interval', () {
      expect(service.snapValue(23, 10), 20);
      expect(service.snapValue(26, 10), 30);
      expect(service.snapValue(-23, 10), -20);
      expect(service.snapValue(-26, 10), -30);
    });

    test('snapValue returns the original value for non-positive grid size', () {
      expect(service.snapValue(17.5, 0), 17.5);
      expect(service.snapValue(17.5, -10), 17.5);
    });

    test('snapPoint snaps both coordinates', () {
      final snapped = service.snapPoint(
        point: const DrawPoint(x: 14.9, y: 25.1),
        gridSize: 10,
      );

      expect(snapped, const DrawPoint(x: 10, y: 30));
    });

    test('snapPoint reuses instance when point is already aligned', () {
      const aligned = DrawPoint(x: 20, y: -40);

      final snapped = service.snapPoint(point: aligned, gridSize: 10);

      expect(snapped, same(aligned));
    });

    test('snapRect only snaps requested edges', () {
      final snapped = service.snapRect(
        rect: const DrawRect(minX: 12, minY: 13, maxX: 38, maxY: 39),
        gridSize: 10,
        snapMinX: true,
        snapMaxX: true,
      );

      expect(snapped, const DrawRect(minX: 10, minY: 13, maxX: 40, maxY: 39));
    });

    test('snapRect reuses instance when no edges are requested', () {
      const rect = DrawRect(minX: 12, minY: 13, maxX: 38, maxY: 39);

      final snapped = service.snapRect(rect: rect, gridSize: 10);

      expect(snapped, same(rect));
    });

    test(
      'snapRect reuses instance when requested edges are already aligned',
      () {
        const alignedRect = DrawRect(minX: 10, minY: 20, maxX: 40, maxY: 80);

        final snapped = service.snapRect(
          rect: alignedRect,
          gridSize: 10,
          snapMinX: true,
          snapMaxX: true,
          snapMinY: true,
          snapMaxY: true,
        );

        expect(snapped, same(alignedRect));
      },
    );

    test('non-finite numbers do not throw and preserve non-finite values', () {
      expect(() => service.snapValue(double.nan, 10), returnsNormally);
      expect(service.snapValue(double.nan, 10).isNaN, isTrue);
      expect(service.snapValue(double.infinity, 10), double.infinity);
      expect(service.snapValue(12, double.nan), 12);
      expect(service.snapValue(12, double.infinity), 12);
      expect(service.snapValue(double.maxFinite, 1e308), double.maxFinite);

      final snappedPoint = service.snapPoint(
        point: const DrawPoint(x: double.nan, y: 5),
        gridSize: 10,
      );
      expect(snappedPoint.x.isNaN, isTrue);
      expect(snappedPoint.y, 10);
    });

    test('snapPoint and snapRect keep original geometry for invalid grid', () {
      const point = DrawPoint(x: 14.9, y: 25.1);
      const rect = DrawRect(minX: 12, minY: 13, maxX: 38, maxY: 39);

      expect(service.snapPoint(point: point, gridSize: double.nan), point);
      expect(
        service.snapRect(
          rect: rect,
          gridSize: double.infinity,
          snapMinX: true,
          snapMaxX: true,
        ),
        rect,
      );
    });
  });
}
