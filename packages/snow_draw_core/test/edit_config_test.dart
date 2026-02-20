import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/core/edit_config.dart';

void main() {
  group('EditConfig', () {
    test('copyWith returns same instance when values are unchanged', () {
      const config = EditConfig.defaults;

      expect(config.copyWith(), same(config));
      expect(
        config.copyWith(
          dragThreshold: config.dragThreshold,
          selectionPadding: config.selectionPadding,
          handleTolerance: config.handleTolerance,
          minElementSize: config.minElementSize,
          rotationSnapAngle: config.rotationSnapAngle,
          rotationHandleOffset: config.rotationHandleOffset,
        ),
        same(config),
      );
    });

    test('copyWith applies provided fields and keeps others', () {
      const config = EditConfig(
        dragThreshold: 1.5,
        selectionPadding: 2.5,
        handleTolerance: 7,
        minElementSize: 6,
        rotationSnapAngle: 0.3,
        rotationHandleOffset: 14,
      );

      final updated = config.copyWith(
        dragThreshold: 3,
        rotationHandleOffset: 20,
      );

      expect(updated.dragThreshold, 3);
      expect(updated.rotationHandleOffset, 20);
      expect(updated.selectionPadding, config.selectionPadding);
      expect(updated.handleTolerance, config.handleTolerance);
      expect(updated.minElementSize, config.minElementSize);
      expect(updated.rotationSnapAngle, config.rotationSnapAngle);
    });

    test('constructor rejects invalid values', () {
      final invalidConfigs = <EditConfig Function()>[
        () => EditConfig(dragThreshold: -0.1),
        () => EditConfig(selectionPadding: -1),
        () => EditConfig(handleTolerance: 0),
        () => EditConfig(minElementSize: 0),
        () => EditConfig(rotationSnapAngle: -0.01),
        () => EditConfig(rotationHandleOffset: -1),
      ];

      for (final buildConfig in invalidConfigs) {
        _expectAssertion(buildConfig);
      }
    });

    test('copyWith rejects invalid values', () {
      const config = EditConfig.defaults;
      final invalidUpdates = <EditConfig Function()>[
        () => config.copyWith(selectionPadding: -1),
        () => config.copyWith(handleTolerance: 0),
      ];

      for (final updateConfig in invalidUpdates) {
        _expectAssertion(updateConfig);
      }
    });
  });
}

void _expectAssertion(EditConfig Function() action) {
  expect(action, throwsA(isA<AssertionError>()));
}
