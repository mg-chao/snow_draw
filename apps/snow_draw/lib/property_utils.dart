import 'package:flutter/material.dart';
import 'style_toolbar_state.dart';

/// Utility functions for property value operations
class PropertyUtils {
  PropertyUtils._();

  /// Merge multiple MixedValue instances using an equality function
  static MixedValue<T> mergeMixedValues<T>(
    List<MixedValue<T>> values,
    bool Function(T, T) equals, {
    bool treatNullAsValue = false,
  }) {
    if (values.isEmpty) {
      return MixedValue<T>(value: null, isMixed: true);
    }

    T? firstValue;
    var hasFirstValue = false;
    var hasNullValue = false;

    for (final candidate in values) {
      if (candidate.isMixed) {
        return MixedValue<T>(value: null, isMixed: true);
      }

      final value = candidate.value;
      if (value == null) {
        if (!treatNullAsValue || hasFirstValue) {
          return MixedValue<T>(value: null, isMixed: true);
        }
        hasNullValue = true;
        continue;
      }

      if (hasNullValue) {
        return MixedValue<T>(value: null, isMixed: true);
      }

      if (!hasFirstValue) {
        firstValue = value;
        hasFirstValue = true;
        continue;
      }

      if (!equals(firstValue as T, value)) {
        return MixedValue<T>(value: null, isMixed: true);
      }
    }

    if (!hasFirstValue) {
      return treatNullAsValue
          ? MixedValue<T>(value: null, isMixed: false)
          : MixedValue<T>(value: null, isMixed: true);
    }

    return MixedValue<T>(value: firstValue, isMixed: false);
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
