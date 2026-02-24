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
}
