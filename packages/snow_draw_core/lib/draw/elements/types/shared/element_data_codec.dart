import '../../../types/draw_point.dart';

/// Shared decode helpers for element JSON payloads.
final class ElementDataCodec {
  const ElementDataCodec._();

  static T decodeEnumByName<T extends Enum>({
    required List<T> values,
    required Object? raw,
    String? fieldName,
  }) {
    if (raw is! String) {
      throw FormatException(
        'Expected a string enum value for ${fieldName ?? 'field'}',
      );
    }

    for (final value in values) {
      if (value.name == raw) {
        return value;
      }
    }

    throw FormatException(
      'Unsupported enum value "$raw" for ${fieldName ?? 'field'}',
    );
  }

  static Map<String, dynamic> asJsonMap(Object? raw, {String? fieldName}) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is! Map) {
      throw FormatException('Expected a JSON map for ${fieldName ?? 'field'}');
    }

    final map = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        throw FormatException(
          'Expected string keys in JSON map for ${fieldName ?? 'field'}',
        );
      }
      map[key] = entry.value;
    }
    return map;
  }

  static Map<String, dynamic>? asNullableJsonMap(
    Object? raw, {
    String? fieldName,
  }) {
    if (raw == null) {
      return null;
    }
    return asJsonMap(raw, fieldName: fieldName);
  }

  static bool? decodeNullableBool(Object? raw, {required String fieldName}) {
    if (raw == null) {
      return null;
    }
    if (raw is bool) {
      return raw;
    }
    throw FormatException('Expected bool for $fieldName');
  }

  static String decodeString(Object? raw, {required String fieldName}) {
    if (raw is String) {
      return raw;
    }
    throw FormatException('Expected string for $fieldName');
  }

  static String? decodeNullableString(
    Object? raw, {
    required String fieldName,
  }) {
    if (raw == null) {
      return null;
    }
    return decodeString(raw, fieldName: fieldName);
  }

  static bool decodeBool(Object? raw, {required String fieldName}) {
    if (raw is bool) {
      return raw;
    }
    throw FormatException('Expected bool for $fieldName');
  }

  static double decodeDouble(Object? raw, {required String fieldName}) {
    if (raw is num) {
      return raw.toDouble();
    }
    throw FormatException('Expected numeric value for $fieldName');
  }

  static int decodeInt(Object? raw, {required String fieldName}) {
    if (raw is int) {
      return raw;
    }
    throw FormatException('Expected integer value for $fieldName');
  }

  static DrawPoint decodePoint(
    Object? raw, {
    required String fieldName,
    bool allowPressure = false,
    String pressureFieldName = 'p',
  }) {
    final pointMap = asJsonMap(raw, fieldName: fieldName);
    final x = pointMap['x'];
    final y = pointMap['y'];
    if (x is! num || y is! num) {
      throw FormatException('$fieldName must provide numeric x/y');
    }

    if (!allowPressure) {
      return DrawPoint(x: x.toDouble(), y: y.toDouble());
    }

    final pressureValue = pointMap[pressureFieldName];
    if (pressureValue != null && pressureValue is! num) {
      throw FormatException(
        '$fieldName $pressureFieldName must be numeric when provided',
      );
    }
    return DrawPoint(
      x: x.toDouble(),
      y: y.toDouble(),
      pressure: (pressureValue as num?)?.toDouble() ?? 0.0,
    );
  }
}
