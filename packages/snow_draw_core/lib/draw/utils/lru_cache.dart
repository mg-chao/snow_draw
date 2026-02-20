/// Generic least-recently-used cache with optional disposal.
///
/// When an eviction callback is provided it is called for every value that
/// leaves the cache: eviction, explicit [remove], [clear], or replacement
/// via [put].
class LruCache<K, V> {
  LruCache({required this.maxEntries, void Function(V value)? onEvict})
    : _onEvict = _eraseOnEvict(onEvict) {
    if (maxEntries < 0) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'Must be >= 0.');
    }
  }

  final int maxEntries;
  final void Function(Object?)? _onEvict;
  final _entries = <K, V>{};

  static void Function(Object?)? _eraseOnEvict<V>(
    void Function(V value)? onEvict,
  ) {
    if (onEvict == null) {
      return null;
    }
    return (Object? value) => onEvict(value as V);
  }

  int get length => _entries.length;

  V? get(K key) {
    if (!_entries.containsKey(key)) {
      return null;
    }
    return _touch(key);
  }

  V getOrCreate(K key, V Function() builder) {
    if (_entries.containsKey(key)) {
      return _touch(key);
    }
    final value = builder();
    put(key, value);
    return value;
  }

  void put(K key, V value) {
    if (_entries.containsKey(key)) {
      final old = _entries.remove(key) as V;
      if (!identical(old, value)) {
        _onEvict?.call(old);
      }
    }

    _entries[key] = value;

    if (_entries.length > maxEntries) {
      final leastRecentlyUsedKey = _entries.keys.first;
      final leastRecentlyUsedValue = _entries.remove(leastRecentlyUsedKey) as V;
      _onEvict?.call(leastRecentlyUsedValue);
    }
  }

  bool remove(K key) {
    if (!_entries.containsKey(key)) {
      return false;
    }
    final value = _entries.remove(key) as V;
    _onEvict?.call(value);
    return true;
  }

  void clear() {
    final onEvict = _onEvict;
    if (onEvict != null) {
      for (final value in _entries.values) {
        onEvict(value);
      }
    }
    _entries.clear();
  }

  V _touch(K key) {
    final value = _entries.remove(key) as V;
    _entries[key] = value;
    return value;
  }
}
