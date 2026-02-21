import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/services/coordinate_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_flutter_backend/extensions/coordinate_service_offset_extensions.dart';

void main() {
  group('CoordinateServiceOffsetExtensions', () {
    test('screenOffsetToWorld and worldPointToScreenOffset are inverses', () {
      const service = CoordinateService(
        camera: CameraState(position: DrawPoint(x: -20, y: 30), zoom: 1.5),
        scaleFactor: 1.5,
      );

      const offset = Offset(25, 60);
      final worldPoint = service.screenOffsetToWorld(offset);

      expect(worldPoint, const DrawPoint(x: 30, y: 20));
      expect(service.worldPointToScreenOffset(worldPoint), offset);
    });
  });
}
