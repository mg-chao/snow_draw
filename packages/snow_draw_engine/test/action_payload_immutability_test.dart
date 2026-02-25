import 'package:snow_draw_engine/draw/actions/draw_actions.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:test/test.dart';

void main() {
  group('Collection-backed actions', () {
    final elementIdsSnapshotBuilders =
        <String, List<String> Function(List<String>)>{
          'DeleteElements': (elementIds) =>
              DeleteElements(elementIds: elementIds).elementIds,
          'DuplicateElements': (elementIds) =>
              DuplicateElements(elementIds: elementIds).elementIds,
          'ChangeElementsZIndex': (elementIds) => ChangeElementsZIndex(
            elementIds: elementIds,
            operation: ZIndexOperation.bringToFront,
          ).elementIds,
          'UpdateElementsStyle': (elementIds) => UpdateElementsStyle(
            elementIds: elementIds,
            opacity: 0.5,
          ).elementIds,
          'CreateSerialNumberTextElements': (elementIds) =>
              CreateSerialNumberTextElements(elementIds: elementIds).elementIds,
        };

    for (final entry in elementIdsSnapshotBuilders.entries) {
      test('${entry.key} keeps an immutable snapshot of elementIds', () {
        final elementIds = <String>['a'];
        final snapshot = entry.value(elementIds);

        elementIds.add('b');

        expect(snapshot, equals(['a']));
        expect(() => snapshot.add('c'), throwsA(isA<UnsupportedError>()));
      });
    }

    test('UpdateCreatingElement keeps an immutable snapshot of points', () {
      final points = <DrawPoint>[const DrawPoint(x: 1, y: 2)];
      final snapshot = UpdateCreatingElement(positions: points).positions;

      points.add(const DrawPoint(x: 3, y: 4));

      expect(snapshot, hasLength(1));
      expect(
        () => snapshot.add(const DrawPoint(x: 5, y: 6)),
        throwsA(isA<UnsupportedError>()),
      );
    });
  });
}
