import 'package:snow_draw_core/draw/elements/core/element_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/single_selection_profile.dart';
import 'package:test/test.dart';

void main() {
  group('resolveSingleSelectionProfile', () {
    test('returns none for empty or multi selection', () {
      final empty = resolveSingleSelectionProfile(
        selectedIds: const <String>{},
        resolveElementById: (_) => null,
      );
      final multi = resolveSingleSelectionProfile(
        selectedIds: const <String>{'a', 'b'},
        resolveElementById: (_) => null,
      );

      expect(empty, same(SingleSelectionProfile.none));
      expect(multi, same(SingleSelectionProfile.none));
    });

    test('captures arrow-specific flags and corner-handle offset', () {
      final profile = resolveSingleSelectionProfile(
        selectedIds: const {'arrow'},
        resolveElementById: (_) => _element(
          id: 'arrow',
          data: const ArrowData(arrowType: ArrowType.elbow),
        ),
      );

      expect(profile.element?.id, 'arrow');
      expect(profile.isArrow, isTrue);
      expect(profile.isTwoPointArrow, isTrue);
      expect(profile.isElbowArrow, isTrue);
      expect(profile.cornerHandleOffset, 8.0);
      expect(profile.isText, isFalse);
    });

    test('captures text-specific flags', () {
      final profile = resolveSingleSelectionProfile(
        selectedIds: const {'text'},
        resolveElementById: (_) => _element(
          id: 'text',
          data: const TextData(text: 'note'),
        ),
      );

      expect(profile.element?.id, 'text');
      expect(profile.isText, isTrue);
      expect(profile.isArrow, isFalse);
      expect(profile.cornerHandleOffset, 0.0);
    });

    test('returns none when single selected id has no element', () {
      final profile = resolveSingleSelectionProfile(
        selectedIds: const {'missing'},
        resolveElementById: (_) => null,
      );

      expect(profile, same(SingleSelectionProfile.none));
    });
  });
}

ElementState _element({required String id, required ElementData data}) =>
    ElementState(
      id: id,
      rect: const DrawRect(maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: data,
    );
