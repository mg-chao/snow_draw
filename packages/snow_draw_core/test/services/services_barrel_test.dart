import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
// These imports verify that the barrel file re-exports the expected
// services. If a service is missing from the barrel, the corresponding
// import through `services.dart` will fail to compile.
import 'package:snow_draw_core/draw/services/services.dart';

void main() {
  group('services barrel exports', () {
    test('CoordinateService is accessible', () {
      const service = CoordinateService(camera: CameraState.initial);
      expect(service, isNotNull);
    });

    test('ElementIndexService is accessible', () {
      final service = ElementIndexService([]);
      expect(service, isNotNull);
    });

    test('SelectionDataComputer is accessible', () {
      // Static-only class, just verify the type exists.
      expect(SelectionDataComputer, isNotNull);
    });

    test('LogService is accessible', () {
      final service = LogService(config: LogConfig.test);
      expect(service, isNotNull);
      service.dispose();
    });

    test('GridSnapService is accessible', () {
      expect(gridSnapService, isNotNull);
    });

    test('ObjectSnapService is accessible', () {
      expect(objectSnapService, isNotNull);
    });

    test('DrawStateViewBuilder is accessible', () {
      expect(DrawStateViewBuilder, isNotNull);
    });

    test('SelectionGeometryResolver is accessible', () {
      expect(SelectionGeometryResolver, isNotNull);
    });
  });
}
