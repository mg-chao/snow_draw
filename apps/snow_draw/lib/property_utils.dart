import 'package:flutter/material.dart';
import 'style_toolbar_state.dart';

/// Utility functions for property value operations
class PropertyUtils {
  PropertyUtils._();

  /// Merge multiple MixedValue instances using an equality function
  static MixedValue<T> mergeMixedValues<T>(
    List<MixedValue<T>> values,
    bool Function(T, T) equals,
  ) {
    if (values.isEmpty) {
      return const MixedValue(value: null, isMixed: true);
    }

    // If any value is mixed, result is mixed
    if (values.any((v) => v.isMixed)) {
      return const MixedValue(value: null, isMixed: true);
    }

    // Get first non-null value
    final firstValue = values.first.value;
    if (firstValue == null) {
      return const MixedValue(value: null, isMixed: true);
    }

    // Check if all values equal the first
    for (final value in values.skip(1)) {
      if (value.value == null || !equals(firstValue, value.value as T)) {
        return const MixedValue(value: null, isMixed: true);
      }
    }

    return MixedValue(value: firstValue, isMixed: false);
  }

  /// Compare two doubles with tolerance
  static bool doubleEquals(double a, double b) => (a - b).abs() <= 0.01;

  /// Compare two colors
  static bool colorEquals(Color a, Color b) => a == b;

  /// Compare two enums
  static bool enumEquals<T>(T a, T b) => a == b;

  /// Compare two strings
  static bool stringEquals(String a, String b) => a == b;
}
