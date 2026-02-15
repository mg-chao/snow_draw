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
  final frozenBySource = HashMap<Object, Object>.identity();
  return _freezePayloadMap(payload, active, frozenBySource);
}

Map<String, dynamic> _freezePayloadMap(
  Map<String, dynamic> payload,
  Set<Object> active,
  Map<Object, Object> frozenBySource,
) => _freezeCollection(
  source: payload,
  active: active,
  frozenBySource: frozenBySource,
  buildFrozen: () {
    final frozen = <String, dynamic>{};
    payload.forEach((key, value) {
      frozen[key] = _freezePayloadValue(value, active, frozenBySource);
    });
    return Map<String, dynamic>.unmodifiable(frozen);
  },
);

Object? _freezePayloadValue(
  Object? value,
  Set<Object> active,
  Map<Object, Object> frozenBySource,
) {
  if (value is Map) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () {
        if (value.isEmpty) {
          return const <Object?, Object?>{};
        }
        final frozen = <Object?, Object?>{};
        value.forEach((key, nestedValue) {
          frozen[_freezePayloadValue(key, active, frozenBySource)] =
              _freezePayloadValue(nestedValue, active, frozenBySource);
        });
        return Map<Object?, Object?>.unmodifiable(frozen);
      },
    );
  }

  if (value is List) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () {
        if (value.isEmpty) {
          return const <Object?>[];
        }
        return List<Object?>.unmodifiable(
          value.map(
            (item) => _freezePayloadValue(item, active, frozenBySource),
          ),
        );
      },
    );
  }

  if (value is Set) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () {
        if (value.isEmpty) {
          return const <Object?>{};
        }
        return Set<Object?>.unmodifiable(
          value.map(
            (item) => _freezePayloadValue(item, active, frozenBySource),
          ),
        );
      },
    );
  }

  if (value is Iterable) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () {
        final frozen = value
            .map((item) => _freezePayloadValue(item, active, frozenBySource))
            .toList(growable: false);
        if (frozen.isEmpty) {
          return const <Object?>[];
        }
        return List<Object?>.unmodifiable(frozen);
      },
    );
  }

  return value;
}

T _freezeCollection<T extends Object>({
  required Object source,
  required Set<Object> active,
  required Map<Object, Object> frozenBySource,
  required T Function() buildFrozen,
}) {
  final cached = frozenBySource[source];
  if (cached != null) {
    return cached as T;
  }

  final frozen = _withCycleGuard(source, active, buildFrozen);
  frozenBySource[source] = frozen;
  return frozen;
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
