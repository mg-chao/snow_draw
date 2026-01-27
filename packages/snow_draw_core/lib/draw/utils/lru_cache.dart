class LruCache<K, V> {
  LruCache({required this.maxEntries});

  final int maxEntries;
  final _entries = <K, _LruNode<K, V>>{};
  _LruNode<K, V>? _head;
  _LruNode<K, V>? _tail;

  int get length => _entries.length;

  V? get(K key) {
    final node = _entries[key];
    if (node == null) {
      return null;
    }
    _moveToFront(node);
    return node.value;
  }

  V getOrCreate(K key, V Function() builder) {
    final existing = get(key);
    if (existing != null) {
      return existing;
    }
    final value = builder();
    put(key, value);
    return value;
  }

  void put(K key, V value) {
    final existing = _entries[key];
    if (existing != null) {
      existing.value = value;
      _moveToFront(existing);
      return;
    }

    final node = _LruNode(key, value);
    _entries[key] = node;
    _addToFront(node);
    if (_entries.length > maxEntries) {
      _evict();
    }
  }

  bool remove(K key) {
    final node = _entries.remove(key);
    if (node == null) {
      return false;
    }
    _unlink(node);
    return true;
  }

  void clear() {
    _entries.clear();
    _head = null;
    _tail = null;
  }

  void _evict() {
    final tail = _tail;
    if (tail == null) {
      return;
    }
    _entries.remove(tail.key);
    _unlink(tail);
  }

  void _addToFront(_LruNode<K, V> node) {
    node
      ..prev = null
      ..next = _head;
    if (_head != null) {
      _head!.prev = node;
    }
    _head = node;
    _tail ??= node;
  }

  void _moveToFront(_LruNode<K, V> node) {
    if (node == _head) {
      return;
    }
    _unlink(node);
    _addToFront(node);
  }

  void _unlink(_LruNode<K, V> node) {
    final prev = node.prev;
    final next = node.next;
    if (prev != null) {
      prev.next = next;
    } else {
      _head = next;
    }
    if (next != null) {
      next.prev = prev;
    } else {
      _tail = prev;
    }
    node
      ..prev = null
      ..next = null;
  }
}

class _LruNode<K, V> {
  _LruNode(this.key, this.value);

  final K key;
  V value;
  _LruNode<K, V>? prev;
  _LruNode<K, V>? next;
}
