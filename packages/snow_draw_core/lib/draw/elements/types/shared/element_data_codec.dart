/// Shared decode helpers for element JSON payloads.
final class ElementDataCodec {
  const ElementDataCodec._();

  static T decodeEnumByName<T extends Enum>({
    required List<T> values,
    required Object? raw,
    required T fallback,
  }) {
    if (raw is! String) {
      return fallback;
    }
    return values.firstWhere(
      (value) => value.name == raw,
      orElse: () => fallback,
    );
  }

  static Map<String, dynamic>? asJsonMap(Object? raw) {
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    if (raw is! Map) {
      return null;
    }

    final map = <String, dynamic>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is! String) {
        return null;
      }
      map[key] = entry.value;
    }
    return map;
  }
}
