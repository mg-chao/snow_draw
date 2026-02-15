import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

void main() {
  group('LruCache', () {
    test('get returns null for missing key', () {
      final cache = LruCache<String, int>(maxEntries: 4);
      expect(cache.get('missing'), isNull);
    });

    test('put and get round-trip', () {
      final cache = LruCache<String, int>(maxEntries: 4)..put('a', 1);
      expect(cache.get('a'), 1);
      expect(cache.length, 1);
    });

    test('getOrCreate returns existing value', () {
      final cache = LruCache<String, int>(maxEntries: 4)..put('a', 1);
      var called = false;
      final result = cache.getOrCreate('a', () {
        called = true;
        return 99;
      });
      expect(result, 1);
      expect(called, isFalse);
    });

    test('getOrCreate builds and caches on miss', () {
      final cache = LruCache<String, int>(maxEntries: 4);
      final result = cache.getOrCreate('a', () => 42);
      expect(result, 42);
      expect(cache.get('a'), 42);
    });

    test('evicts least-recently-used when full', () {
      final cache = LruCache<String, int>(maxEntries: 3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3)
        // 'a' is the LRU entry.
        ..put('d', 4);
      expect(cache.get('a'), isNull, reason: 'a should be evicted');
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.get('d'), 4);
    });

    test('get promotes entry so it is not evicted', () {
      final cache = LruCache<String, int>(maxEntries: 3)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3)
        // Touch 'a' to promote it.
        ..get('a')
        // Now 'b' is the LRU.
        ..put('d', 4);
      expect(cache.get('a'), 1, reason: 'a was promoted');
      expect(cache.get('b'), isNull, reason: 'b should be evicted');
    });

    test('onEvict is called when entry is evicted', () {
      final evicted = <int>[];
      LruCache<String, int>(maxEntries: 2, onEvict: evicted.add)
        ..put('a', 1)
        ..put('b', 2)
        ..put('c', 3);
      expect(evicted, [1]);
    });

    test('onEvict is called on remove', () {
      final evicted = <int>[];
      LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', 1)
        ..remove('a');
      expect(evicted, [1]);
    });

    test('onEvict is called on clear', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', 1)
        ..put('b', 2)
        ..clear();
      expect(evicted, containsAll([1, 2]));
      expect(cache.length, 0);
    });

    test('put replaces value and calls onEvict for old value', () {
      final evicted = <int>[];
      final cache = LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', 1)
        ..put('a', 2);
      expect(cache.get('a'), 2);
      expect(evicted, [1]);
    });

    test('put with identical value does not call onEvict', () {
      final evicted = <int>[];
      const value = 42;
      LruCache<String, int>(maxEntries: 4, onEvict: evicted.add)
        ..put('a', value)
        ..put('a', value);
      expect(evicted, isEmpty);
    });
  });
}
