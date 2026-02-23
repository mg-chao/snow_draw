import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:test/test.dart';

void main() {
  test(
    'plans finish-text-edit then clear-selection for text editing state',
    () {
      final interaction = TextEditingState(
        elementId: 'text-1',
        draftData: const TextData(text: 'draft'),
        rect: const DrawRect(maxX: 100, maxY: 40),
        isNew: false,
        opacity: 1,
        rotation: 0,
      );

      final actions = resolveToolChangeResetActions(
        interaction: interaction,
        includeClearSelection: true,
      );

      expect(actions, hasLength(2));
      final finish = actions.first as FinishTextEdit;
      expect(finish.elementId, 'text-1');
      expect(finish.text, 'draft');
      expect(finish.isNew, isFalse);
      expect(actions.last, isA<ClearSelection>());
    },
  );

  test('omits clear-selection when includeClearSelection is false', () {
    final actions = resolveToolChangeResetActions(
      interaction: CreatingState(
        element: const ElementState(
          id: 'draft',
          rect: DrawRect(maxX: 20, maxY: 20),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        startPosition: DrawPoint.zero,
        currentRect: DrawRect(maxX: 20, maxY: 20),
      ),
      includeClearSelection: false,
    );

    expect(actions, hasLength(1));
    expect(actions.single, isA<CancelCreateElement>());
  });
}
