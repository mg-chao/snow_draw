import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/history_change_set.dart';
import 'package:snow_draw_core/draw/store/history_delta.dart';
import 'package:snow_draw_core/draw/store/snapshot.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('HistoryDelta targeted diff optimization', () {
    test('resolves multiple modified ids without iterating full maps', () {
      final beforeMap = _LookupOnlyMap({
        'a': _element('a', left: 0),
        'b': _element('b', left: 20),
        'c': _element('c', left: 40),
      });
      final afterMap = _LookupOnlyMap({
        'a': _element('a', left: 5),
        'b': _element('b', left: 20),
        'c': _element('c', left: 55),
      });

      final delta = HistoryDelta.fromSnapshots(
        _LookupOnlySnapshot(elementMap: beforeMap),
        _LookupOnlySnapshot(elementMap: afterMap),
        changes: HistoryChangeSet(modifiedIds: const {'a', 'c'}),
      );

      expect(delta.beforeElements.keys.toSet(), equals({'a', 'c'}));
      expect(delta.afterElements.keys.toSet(), equals({'a', 'c'}));
    });

    test('resolves add/remove changes without iterating full maps', () {
      final beforeMap = _LookupOnlyMap({
        'a': _element('a', left: 0),
        'b': _element('b', left: 20),
      });
      final afterMap = _LookupOnlyMap({
        'a': _element('a', left: 8),
        'c': _element('c', left: 40),
      });

      final delta = HistoryDelta.fromSnapshots(
        _LookupOnlySnapshot(elementMap: beforeMap),
        _LookupOnlySnapshot(elementMap: afterMap),
        changes: HistoryChangeSet(
          modifiedIds: const {'a'},
          removedIds: const {'b'},
          addedIds: const {'c'},
        ),
      );

      expect(delta.beforeElements.keys.toSet(), equals({'a', 'b'}));
      expect(delta.afterElements.keys.toSet(), equals({'a', 'c'}));
    });
  });
}

ElementState _element(String id, {required double left}) => ElementState(
  id: id,
  rect: DrawRect(minX: left, maxX: left + 10, maxY: 10),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const FilterData(),
);

class _LookupOnlySnapshot implements HistorySnapshot {
  _LookupOnlySnapshot({required this.elementMap});

  @override
  final Map<String, ElementState> elementMap;

  @override
  List<ElementState> get elements =>
      throw UnsupportedError('elements list should not be used by this test');

  @override
  SelectionState get selection => const SelectionState();

  @override
  bool get includeSelection => false;

  @override
  List<String>? get order => null;
}

class _LookupOnlyMap extends MapBase<String, ElementState> {
  _LookupOnlyMap(this._delegate);

  final Map<String, ElementState> _delegate;

  @override
  ElementState? operator [](Object? key) => _delegate[key];

  @override
  void operator []=(String key, ElementState value) {
    throw UnsupportedError('Map is read-only');
  }

  @override
  void clear() {
    throw UnsupportedError('Map is read-only');
  }

  @override
  Iterable<String> get keys =>
      throw UnsupportedError('Full-map iteration should be avoided');

  @override
  ElementState? remove(Object? key) {
    throw UnsupportedError('Map is read-only');
  }

  @override
  bool containsKey(Object? key) => _delegate.containsKey(key);
}
