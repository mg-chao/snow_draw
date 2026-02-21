import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/snow_draw_core.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/text_editing_state_change.dart';

void main() {
  group('isTextEditingDraftMutationOnly', () {
    test('returns true when only text draft payload changes', () {
      final base = DrawState();
      final previous = _stateWithTextInteraction(
        base,
        const TextEditingState(
          elementId: 'text-1',
          draftData: TextData(text: 'a'),
          rect: DrawRect(minX: 10, minY: 20, maxX: 80, maxY: 52),
          isNew: false,
          opacity: 1,
          rotation: 0,
        ),
      );
      final next = previous.copyWith(
        application: previous.application.copyWith(
          interaction: const TextEditingState(
            elementId: 'text-1',
            draftData: TextData(text: 'ab'),
            rect: DrawRect(minX: 10, minY: 20, maxX: 98, maxY: 52),
            isNew: false,
            opacity: 1,
            rotation: 0,
          ),
        ),
      );

      expect(
        isTextEditingDraftMutationOnly(previous: previous, next: next),
        isTrue,
      );
    });

    test('returns false when domain changes', () {
      final base = DrawState();
      final previous = _stateWithTextInteraction(
        base,
        const TextEditingState(
          elementId: 'text-1',
          draftData: TextData(text: 'a'),
          rect: DrawRect(maxX: 40, maxY: 30),
          isNew: false,
          opacity: 1,
          rotation: 0,
        ),
      );
      final next = previous.copyWith(
        domain: previous.domain.withSelected('text-1'),
        application: previous.application.copyWith(
          interaction: const TextEditingState(
            elementId: 'text-1',
            draftData: TextData(text: 'ab'),
            rect: DrawRect(maxX: 50, maxY: 30),
            isNew: false,
            opacity: 1,
            rotation: 0,
          ),
        ),
      );

      expect(
        isTextEditingDraftMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when editing session changes', () {
      final base = DrawState();
      final previous = _stateWithTextInteraction(
        base,
        const TextEditingState(
          elementId: 'text-1',
          draftData: TextData(text: 'a'),
          rect: DrawRect(maxX: 40, maxY: 30),
          isNew: false,
          opacity: 1,
          rotation: 0,
          initialCursorPosition: DrawPoint(x: 1, y: 1),
        ),
      );
      final next = previous.copyWith(
        application: previous.application.copyWith(
          interaction: const TextEditingState(
            elementId: 'text-2',
            draftData: TextData(text: 'ab'),
            rect: DrawRect(maxX: 50, maxY: 30),
            isNew: false,
            opacity: 1,
            rotation: 0,
            initialCursorPosition: DrawPoint(x: 1, y: 1),
          ),
        ),
      );

      expect(
        isTextEditingDraftMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });

    test('returns false when only interaction wrapper instance changes', () {
      final base = DrawState();
      const interaction = TextEditingState(
        elementId: 'text-1',
        draftData: TextData(text: 'stable'),
        rect: DrawRect(maxX: 40, maxY: 30),
        isNew: false,
        opacity: 1,
        rotation: 0,
      );
      final previous = _stateWithTextInteraction(base, interaction);
      final next = previous.copyWith(
        application: previous.application.copyWith(
          interaction: interaction.copyWith(),
        ),
      );

      expect(
        isTextEditingDraftMutationOnly(previous: previous, next: next),
        isFalse,
      );
    });
  });

  group('shouldRefreshDynamicLayerForTextEditingDraftMutation', () {
    test('returns true when existing text rect changes', () {
      final base = DrawState();
      final previous = _stateWithTextInteraction(
        base,
        const TextEditingState(
          elementId: 'text-1',
          draftData: TextData(text: 'a'),
          rect: DrawRect(minX: 10, minY: 20, maxX: 80, maxY: 52),
          isNew: false,
          opacity: 1,
          rotation: 0,
        ),
      );
      final next = previous.copyWith(
        application: previous.application.copyWith(
          interaction: const TextEditingState(
            elementId: 'text-1',
            draftData: TextData(text: 'ab'),
            rect: DrawRect(minX: 10, minY: 20, maxX: 98, maxY: 52),
            isNew: false,
            opacity: 1,
            rotation: 0,
          ),
        ),
      );

      expect(
        shouldRefreshDynamicLayerForTextEditingDraftMutation(
          previous: previous,
          next: next,
        ),
        isTrue,
      );
    });

    test('returns false when editing a new text draft', () {
      final base = DrawState();
      final previous = _stateWithTextInteraction(
        base,
        const TextEditingState(
          elementId: 'text-1',
          draftData: TextData(text: 'a'),
          rect: DrawRect(minX: 10, minY: 20, maxX: 80, maxY: 52),
          isNew: true,
          opacity: 1,
          rotation: 0,
        ),
      );
      final next = previous.copyWith(
        application: previous.application.copyWith(
          interaction: const TextEditingState(
            elementId: 'text-1',
            draftData: TextData(text: 'ab'),
            rect: DrawRect(minX: 10, minY: 20, maxX: 98, maxY: 52),
            isNew: true,
            opacity: 1,
            rotation: 0,
          ),
        ),
      );

      expect(
        shouldRefreshDynamicLayerForTextEditingDraftMutation(
          previous: previous,
          next: next,
        ),
        isFalse,
      );
    });

    test('returns false when rect stays the same', () {
      final base = DrawState();
      final previous = _stateWithTextInteraction(
        base,
        const TextEditingState(
          elementId: 'text-1',
          draftData: TextData(text: 'a'),
          rect: DrawRect(minX: 10, minY: 20, maxX: 80, maxY: 52),
          isNew: false,
          opacity: 1,
          rotation: 0,
        ),
      );
      final next = previous.copyWith(
        application: previous.application.copyWith(
          interaction: const TextEditingState(
            elementId: 'text-1',
            draftData: TextData(text: 'b'),
            rect: DrawRect(minX: 10, minY: 20, maxX: 80, maxY: 52),
            isNew: false,
            opacity: 1,
            rotation: 0,
          ),
        ),
      );

      expect(
        shouldRefreshDynamicLayerForTextEditingDraftMutation(
          previous: previous,
          next: next,
        ),
        isFalse,
      );
    });
  });

  test('TextEditingState uses value equality', () {
    const first = TextEditingState(
      elementId: 'text-1',
      draftData: TextData(text: 'hello'),
      rect: DrawRect(maxX: 60, maxY: 24),
      isNew: true,
      opacity: 0.8,
      rotation: 0.2,
      initialCursorPosition: DrawPoint(x: 10, y: 12),
    );
    const second = TextEditingState(
      elementId: 'text-1',
      draftData: TextData(text: 'hello'),
      rect: DrawRect(maxX: 60, maxY: 24),
      isNew: true,
      opacity: 0.8,
      rotation: 0.2,
      initialCursorPosition: DrawPoint(x: 10, y: 12),
    );

    expect(first, equals(second));
    expect(first.hashCode, equals(second.hashCode));
  });
}

DrawState _stateWithTextInteraction(
  DrawState base,
  TextEditingState interaction,
) => base.copyWith(
  application: base.application.copyWith(interaction: interaction),
);
