// Tests that verify pubspec dependency hygiene for snow_draw_core.
//
// These tests ensure that removing unused dependencies does not break
// any imports or functionality.
import 'package:flutter_test/flutter_test.dart';

// Core dependencies that MUST remain importable:
import 'package:collection/collection.dart';
import 'package:meta/meta.dart';
import 'package:rbush/rbush.dart';

// Flutter SDK dependency:
import 'package:flutter/material.dart';

// Internal package imports that exercise the dependency graph:
import 'package:snow_draw_core/draw/services/services.dart';
import 'package:snow_draw_core/draw/utils/lru_cache.dart';

void main() {
  group('snow_draw_core dependency smoke tests', () {
    test('collection package is usable', () {
      // collection is used throughout the core package.
      final list = [3, 1, 2];
      expect(list.sorted((a, b) => a.compareTo(b)), [1, 2, 3]);
    });

    test('meta package is usable', () {
      // @immutable and @protected come from meta.
      // Verify the annotation type is accessible.
      expect(immutable, isA<Object>());
    });

    test('rbush package is usable', () {
      // Spatial indexing used by ElementIndexService.
      // Just verify the type is accessible.
      expect(RBushBase, isNotNull);
    });

    test('LruCache works correctly', () {
      final cache = LruCache<String, int>(maxEntries: 2);
      cache
        ..put('a', 1)
        ..put('b', 2);
      expect(cache.get('a'), 1);
      expect(cache.get('b'), 2);
      expect(cache.length, 2);

      // Adding a third entry evicts the LRU entry.
      // Order after gets: b (front), a (back) — 'a' is evicted.
      cache.put('c', 3);
      expect(cache.length, 2);
      expect(cache.get('b'), 2);
      expect(cache.get('c'), 3);
      expect(cache.get('a'), isNull);
    });

    test('services barrel exports are accessible', () {
      // Verify the barrel file compiles and key types are available.
      expect(CoordinateService, isNotNull);
      expect(ElementIndexService, isNotNull);
    });
  });
}
