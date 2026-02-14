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

    test('rejects invalid values in constructor and copyWith', () {
      expect(
        () => EditConfig(dragThreshold: -0.1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EditConfig(selectionPadding: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EditConfig(handleTolerance: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EditConfig(minElementSize: 0),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EditConfig(rotationSnapAngle: -0.01),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => EditConfig(rotationHandleOffset: -1),
        throwsA(isA<AssertionError>()),
      );

      const config = EditConfig.defaults;
      expect(
        () => config.copyWith(selectionPadding: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => config.copyWith(handleTolerance: 0),
        throwsA(isA<AssertionError>()),
      );
    });
  });
}
