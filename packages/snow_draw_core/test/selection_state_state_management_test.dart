import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';

void main() {
  group('SelectionState state management', () {
    test('withSelectedIds creates a defensive selection snapshot', () {
      final externalIds = <String>{'a'};

      final state = const SelectionState().withSelectedIds(externalIds);
      externalIds.add('b');

      expect(state.selectedIds, {'a'});
      expect(() => state.selectedIds.add('c'), throwsUnsupportedError);
    });

    test('copyWith increments version when selectedIds changes', () {
      const state = SelectionState(selectedIds: {'a'}, selectionVersion: 7);

      final next = state.copyWith(selectedIds: {'b'});

      expect(next.selectionVersion, 8);
      expect(next.selectedIds, {'b'});
    });

    test('copyWith returns the same instance when there are no changes', () {
      const state = SelectionState(selectedIds: {'a'}, selectionVersion: 3);

      final next = state.copyWith();

      expect(next, same(state));
    });

    test(
      'equality short-circuits before deep set comparison when versions differ',
      () {
        final leftIds = _CountingSet(<String>{'a', 'b', 'c'});
        final rightIds = _CountingSet(<String>{'a', 'b', 'c'});
        final left = SelectionState(selectedIds: leftIds, selectionVersion: 1);
        final right = SelectionState(
          selectedIds: rightIds,
          selectionVersion: 2,
        );

        final isEqual = left == right;

        expect(isEqual, isFalse);
        expect(
          rightIds.containsCallCount,
          0,
          reason: 'Different versions should skip O(n) set comparison',
        );
      },
    );
  });
}

class _CountingSet extends SetBase<String> {
  _CountingSet(Set<String> values) : _values = values;

  final Set<String> _values;
  var containsCallCount = 0;

  @override
  bool add(String value) => _values.add(value);

  @override
  bool contains(Object? element) {
    containsCallCount += 1;
    return _values.contains(element);
  }

  @override
  Iterator<String> get iterator => _values.iterator;

  @override
  int get length => _values.length;

  @override
  String? lookup(Object? element) => _values.lookup(element);

  @override
  bool remove(Object? value) => _values.remove(value);

  @override
  void clear() => _values.clear();

  @override
  Set<String> toSet() => _values.toSet();
}
