import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';

void main() {
  group('Collection-backed actions', () {
    test('DeleteElements keeps an immutable snapshot of elementIds', () {
      final elementIds = <String>['a'];
      final action = DeleteElements(elementIds: elementIds);

      elementIds.add('b');

      expect(action.elementIds, equals(['a']));
      expect(
        () => action.elementIds.add('c'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('DuplicateElements keeps an immutable snapshot of elementIds', () {
      final elementIds = <String>['a'];
      final action = DuplicateElements(elementIds: elementIds);

      elementIds.add('b');

      expect(action.elementIds, equals(['a']));
      expect(
        () => action.elementIds.add('c'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('ChangeElementsZIndex keeps an immutable snapshot of elementIds', () {
      final elementIds = <String>['a'];
      final action = ChangeElementsZIndex(
        elementIds: elementIds,
        operation: ZIndexOperation.bringToFront,
      );

      elementIds.add('b');

      expect(action.elementIds, equals(['a']));
      expect(
        () => action.elementIds.add('c'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('UpdateElementsStyle keeps an immutable snapshot of elementIds', () {
      final elementIds = <String>['a'];
      final action = UpdateElementsStyle(elementIds: elementIds, opacity: 0.5);

      elementIds.add('b');

      expect(action.elementIds, equals(['a']));
      expect(
        () => action.elementIds.add('c'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'CreateSerialNumberTextElements keeps an immutable snapshot '
      'of elementIds',
      () {
        final elementIds = <String>['a'];
        final action = CreateSerialNumberTextElements(elementIds: elementIds);

        elementIds.add('b');

        expect(action.elementIds, equals(['a']));
        expect(
          () => action.elementIds.add('c'),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });
}
