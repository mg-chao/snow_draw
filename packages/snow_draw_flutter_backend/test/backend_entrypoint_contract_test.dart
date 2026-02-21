import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/models/camera_state.dart';
import 'package:snow_draw_core/draw/services/coordinate_service.dart';
import 'package:snow_draw_core/draw/types/draw_color.dart';
import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';

void main() {
  group('backend entrypoint contract', () {
    test('exports color and coordinate extensions used by app boundary', () {
      final color = const DrawColor(0xFF123456).toFlutterColor();
      expect(color, equals(const Color(0xFF123456)));

      const service = CoordinateService(camera: CameraState.initial);
      final world = service.screenOffsetToWorld(const Offset(10, 20));
      expect(world.x, 10);
      expect(world.y, 20);
      expect(service.worldPointToScreenOffset(world), const Offset(10, 20));
    });

    test('exposes backend visual registry with built-in visuals', () {
      final coreRegistry = DefaultElementRegistry();
      registerBuiltInElements(coreRegistry);

      final visualRegistry = createDefaultElementVisualRegistry();
      for (final typeId in coreRegistry.registeredTypeIds) {
        expect(
          visualRegistry.supportsTypeValue(typeId.value),
          isTrue,
          reason: 'Missing built-in visual for ${typeId.value}',
        );
      }
    });
  });
}
