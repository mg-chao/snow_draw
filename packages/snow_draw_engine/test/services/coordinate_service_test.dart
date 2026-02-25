import 'package:snow_draw_engine/draw/models/camera_state.dart';
import 'package:snow_draw_engine/draw/services/coordinate_service.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('CoordinateService', () {
    test('screenToWorld and worldToScreen are inverse transforms', () {
      const service = CoordinateService(
        camera: CameraState(position: DrawPoint(x: 100, y: -50), zoom: 2),
        scaleFactor: 2,
      );

      const worldPoint = DrawPoint(x: 12.5, y: 8.25);
      final screenPoint = service.worldToScreen(worldPoint);

      expect(screenPoint, const DrawPoint(x: 125, y: -33.5));
      expect(service.screenToWorld(screenPoint), worldPoint);
    });

    test('fromCamera uses camera zoom when scaleFactor is omitted', () {
      const camera = CameraState(position: DrawPoint(x: 40, y: 10), zoom: 2.5);
      final service = CoordinateService.fromCamera(camera);

      expect(service.scaleFactor, 2.5);
      expect(
        service.worldToScreen(const DrawPoint(x: 4, y: 6)),
        const DrawPoint(x: 50, y: 25),
      );
    });

    test('fromCamera still supports an explicit scaleFactor override', () {
      const camera = CameraState(position: DrawPoint(x: 40, y: 10), zoom: 2.5);
      final service = CoordinateService.fromCamera(camera, scaleFactor: 4);

      expect(service.scaleFactor, 4);
      expect(
        service.worldToScreen(const DrawPoint(x: 4, y: 6)),
        const DrawPoint(x: 56, y: 34),
      );
    });

    test('rejects invalid scale factors in debug mode', () {
      const camera = CameraState.initial;

      expect(
        () => CoordinateService(camera: camera, scaleFactor: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CoordinateService(camera: camera, scaleFactor: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CoordinateService(camera: camera, scaleFactor: double.infinity),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => CoordinateService(camera: camera, scaleFactor: double.nan),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
