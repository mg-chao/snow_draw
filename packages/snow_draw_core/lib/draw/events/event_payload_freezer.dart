import 'dart:collection';

/// Returns a recursively unmodifiable snapshot for event payload maps.
///
/// Nested `Map`, `List`, `Set`, and `Iterable` values are copied and wrapped
/// in unmodifiable collections so emitted payloads cannot be mutated later.
///
/// Throws an [ArgumentError] when payload values contain cyclic references.
Map<String, dynamic> freezeEventPayloadMap(Map<String, dynamic> payload) {
  if (payload.isEmpty) {
    return const <String, dynamic>{};
  }

  final active = HashSet<Object>.identity();
  return _withCycleGuard(payload, active, () {
    final frozen = <String, dynamic>{};
    payload.forEach((key, value) {
      frozen[key] = _freezePayloadValue(value, active);
    });
    return Map<String, dynamic>.unmodifiable(frozen);
  });
}

Object? _freezePayloadValue(Object? value, Set<Object> active) {
  if (value is Map) {
    return _withCycleGuard(value, active, () {
      if (value.isEmpty) {
        return const <Object?, Object?>{};
      }
      final frozen = <Object?, Object?>{};
      value.forEach((key, nestedValue) {
        frozen[_freezePayloadValue(key, active)] = _freezePayloadValue(
          nestedValue,
          active,
        );
      });
      return Map<Object?, Object?>.unmodifiable(frozen);
    });
  }

  if (value is List) {
    return _withCycleGuard(value, active, () {
      if (value.isEmpty) {
        return const <Object?>[];
      }
      return List<Object?>.unmodifiable(
        value.map((item) => _freezePayloadValue(item, active)),
      );
    });
  }

  if (value is Set) {
    return _withCycleGuard(value, active, () {
      if (value.isEmpty) {
        return const <Object?>{};
      }
      return Set<Object?>.unmodifiable(
        value.map((item) => _freezePayloadValue(item, active)),
      );
    });
  }

  if (value is Iterable) {
    return _withCycleGuard(value, active, () {
      final frozen = value
          .map((item) => _freezePayloadValue(item, active))
          .toList(growable: false);
      if (frozen.isEmpty) {
        return const <Object?>[];
      }
      return List<Object?>.unmodifiable(frozen);
    });
  }

  return value;
}

T _withCycleGuard<T>(Object source, Set<Object> active, T Function() body) {
  if (!active.add(source)) {
    _throwCycleError(source);
  }
  try {
    return body();
  } finally {
    active.remove(source);
  }
}

Never _throwCycleError(Object source) {
  throw ArgumentError.value(source, 'payload', 'contains a cyclic reference');
}
