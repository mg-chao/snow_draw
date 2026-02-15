import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw/property_utils.dart';
import 'package:snow_draw/style_toolbar_state.dart';

void main() {
  group('PropertyUtils.mergeMixedValues', () {
    test('returns mixed when there are no values', () {
      final merged = PropertyUtils.mergeMixedValues<int>(
        const [],
        (a, b) => a == b,
      );

      expect(merged, const MixedValue<int>(value: null, isMixed: true));
    });

    test('returns mixed when any source is already mixed', () {
      final merged = PropertyUtils.mergeMixedValues<int>([
        const MixedValue<int>(value: 2, isMixed: false),
        const MixedValue<int>(value: null, isMixed: true),
      ], (a, b) => a == b);

      expect(merged, const MixedValue<int>(value: null, isMixed: true));
    });

    test('returns non-mixed value when all values are equal', () {
      final merged = PropertyUtils.mergeMixedValues<Color>([
        const MixedValue<Color>(value: Color(0xFF1576FE), isMixed: false),
        const MixedValue<Color>(value: Color(0xFF1576FE), isMixed: false),
      ], PropertyUtils.colorEquals);

      expect(
        merged,
        const MixedValue<Color>(value: Color(0xFF1576FE), isMixed: false),
      );
    });

    test('returns mixed when non-null values differ', () {
      final merged = PropertyUtils.mergeMixedValues<double>([
        const MixedValue<double>(value: 3, isMixed: false),
        const MixedValue<double>(value: 5, isMixed: false),
      ], PropertyUtils.doubleEquals);

      expect(merged, const MixedValue<double>(value: null, isMixed: true));
    });

    test('treats null as mixed when treatNullAsValue is false', () {
      final merged = PropertyUtils.mergeMixedValues<String>([
        const MixedValue<String>(value: null, isMixed: false),
      ], PropertyUtils.stringEquals);

      expect(merged, const MixedValue<String>(value: null, isMixed: true));
    });

    test('treats all null values as a concrete value when opted in', () {
      final merged = PropertyUtils.mergeMixedValues<String>(
        [
          const MixedValue<String>(value: null, isMixed: false),
          const MixedValue<String>(value: null, isMixed: false),
        ],
        PropertyUtils.stringEquals,
        treatNullAsValue: true,
      );

      expect(merged, const MixedValue<String>(value: null, isMixed: false));
    });

    test('treats null and non-null values as mixed when opted in', () {
      final merged = PropertyUtils.mergeMixedValues<String>(
        [
          const MixedValue<String>(value: null, isMixed: false),
          const MixedValue<String>(value: 'Inter', isMixed: false),
        ],
        PropertyUtils.stringEquals,
        treatNullAsValue: true,
      );

      expect(merged, const MixedValue<String>(value: null, isMixed: true));
    });
  });
}
