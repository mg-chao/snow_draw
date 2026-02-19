import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/draw_actions.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';

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

    test('CreateSerialNumberTextElements keeps an immutable snapshot '
        'of elementIds', () {
      final elementIds = <String>['a'];
      final action = CreateSerialNumberTextElements(elementIds: elementIds);

      elementIds.add('b');

      expect(action.elementIds, equals(['a']));
      expect(
        () => action.elementIds.add('c'),
        throwsA(isA<UnsupportedError>()),
      );
    });

    test(
      'UpdateCreatingElementBatch keeps an immutable snapshot of points',
      () {
        final points = <DrawPoint>[const DrawPoint(x: 1, y: 2)];
        final action = UpdateCreatingElementBatch(positions: points);

        points.add(const DrawPoint(x: 3, y: 4));

        expect(action.positions, hasLength(1));
        expect(
          () => action.positions.add(const DrawPoint(x: 5, y: 6)),
          throwsA(isA<UnsupportedError>()),
        );
      },
    );
  });
}
