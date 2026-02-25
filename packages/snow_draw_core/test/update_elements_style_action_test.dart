import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  group('UpdateElementsStyle computed payload', () {
    test('styleUpdate mirrors style fields and excludes opacity', () {
      final action = UpdateElementsStyle(
        elementIds: const ['a'],
        color: const DrawColor(0xFFFF0000),
        strokeWidth: 3,
        fontSize: 24,
        opacity: 0.5,
      );

      final styleUpdate = action.styleUpdate;
      expect(styleUpdate.color, const DrawColor(0xFFFF0000));
      expect(styleUpdate.strokeWidth, 3);
      expect(styleUpdate.fontSize, 24);
      expect(styleUpdate.isEmpty, isFalse);
      expect(action.hasStyleUpdates, isTrue);
      expect(action.hasUpdates, isTrue);
    });

    test('opacity-only updates are treated as effective updates', () {
      final action = UpdateElementsStyle(
        elementIds: const ['a'],
        opacity: 0.25,
      );

      expect(action.styleUpdate.isEmpty, isTrue);
      expect(action.hasStyleUpdates, isFalse);
      expect(action.hasUpdates, isTrue);
    });

    test('empty payload reports no updates', () {
      final action = UpdateElementsStyle(elementIds: const ['a']);

      expect(action.styleUpdate.isEmpty, isTrue);
      expect(action.hasStyleUpdates, isFalse);
      expect(action.hasUpdates, isFalse);
    });
  });
}
