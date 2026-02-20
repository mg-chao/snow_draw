import 'dart:collection';

/// Returns a recursively unmodifiable snapshot for event payload maps.
///
/// Nested `Map`, `List`, `Set`, and `Iterable` values are copied and wrapped
/// in unmodifiable collections so emitted payloads cannot be mutated later.
///
/// Throws an [ArgumentError] when payload values contain cyclic references.
Map<String, dynamic> freezeEventPayloadMap(Map<String, dynamic> payload) {
  final active = HashSet<Object>.identity();
  final frozenBySource = HashMap<Object, Object>.identity();
  return _freezeRootPayloadMap(payload, active, frozenBySource);
}

Map<String, dynamic> _freezeRootPayloadMap(
  Map<String, dynamic> payload,
  Set<Object> active,
  Map<Object, Object> frozenBySource,
) => _freezeCollection(
  source: payload,
  active: active,
  frozenBySource: frozenBySource,
  buildFrozen: () => Map<String, dynamic>.unmodifiable(
    payload.map(
      (key, value) =>
          MapEntry(key, _freezePayloadValue(value, active, frozenBySource)),
    ),
  ),
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
      buildFrozen: () => Map<Object?, Object?>.unmodifiable(
        value.map(
          (key, nestedValue) => MapEntry(
            _freezePayloadValue(key, active, frozenBySource),
            _freezePayloadValue(nestedValue, active, frozenBySource),
          ),
        ),
      ),
    );
  }

  if (value is List) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () => List<Object?>.unmodifiable(
        value.map((item) => _freezePayloadValue(item, active, frozenBySource)),
      ),
    );
  }

  if (value is Set) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () => Set<Object?>.unmodifiable(
        value.map((item) => _freezePayloadValue(item, active, frozenBySource)),
      ),
    );
  }

  if (value is Iterable) {
    return _freezeCollection(
      source: value,
      active: active,
      frozenBySource: frozenBySource,
      buildFrozen: () => List<Object?>.unmodifiable(
        value.map((item) => _freezePayloadValue(item, active, frozenBySource)),
      ),
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
  if (frozenBySource.containsKey(source)) {
    return frozenBySource[source]! as T;
  }

  if (!active.add(source)) {
    throw ArgumentError.value(source, 'payload', 'contains a cyclic reference');
  }

  try {
    final frozen = buildFrozen();
    frozenBySource[source] = frozen;
    return frozen;
  } finally {
    active.remove(source);
  }
}
