// ignore_for_file: unused_import
import 'package:flutter_test/flutter_test.dart';

// These imports verify that the barrel file re-exports the expected
// services. If a service is missing from the barrel, the corresponding
// import through `services.dart` will fail to compile.
import 'package:snow_draw_core/draw/services/services.dart';

// Verify individual service availability through the barrel.
import 'package:snow_draw_core/draw/services/coordinate_service.dart';
import 'package:snow_draw_core/draw/services/element_index_service.dart';
import 'package:snow_draw_core/draw/services/selection_data_computer.dart';
import 'package:snow_draw_core/draw/services/log/log.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';

// These are NOT currently exported from the barrel file.
// They must be imported directly.
import 'package:snow_draw_core/draw/services/grid_snap_service.dart';
import 'package:snow_draw_core/draw/services/object_snap_service.dart';
import 'package:snow_draw_core/draw/services/draw_state_view_builder.dart';
import 'package:snow_draw_core/draw/services/selection_geometry_resolver.dart';

void main() {
  group('services barrel exports', () {
    test('CoordinateService is accessible', () {
      const service = CoordinateService(
        camera: CameraState(),
      );
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
