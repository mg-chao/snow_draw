import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_layout.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_overlay_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/utils/selection_calculator.dart';

void main() {
  group('UpdateElementsStyle reducer optimizations', () {
    test('no-op opacity update keeps state instance unchanged', () async {
      final element = _buildTextElement(
        id: 'text-1',
        originX: 20,
        originY: 20,
        text: 'hello',
      );
      final store = _createStore(
        initialState: DrawState(
          domain: DomainState(
            document: DocumentState(elements: [element]),
            selection: const SelectionState(selectedIds: {'text-1'}),
          ),
        ),
      );
      addTearDown(store.dispose);

      final before = store.state;

      await store.dispatch(
        UpdateElementsStyle(elementIds: ['text-1'], opacity: 1),
      );

      expect(store.state, same(before));
    });

    test(
      'geometry updates refresh multi-select overlay bounds for selection',
      () async {
        final first = _buildTextElement(
          id: 'text-1',
          originX: 20,
          originY: 20,
          text: 'Alpha',
        );
        final second = _buildTextElement(
          id: 'text-2',
          originX: 220,
          originY: 20,
          text: 'Beta',
        );
        const selectedIds = {'text-1', 'text-2'};
        const initialRotation = 0.5;
        final initialBounds =
            SelectionCalculator.computeSelectionBoundsForElements([
              first,
              second,
            ]);
        final initialState = DrawState(
          domain: DomainState(
            document: DocumentState(elements: [first, second]),
            selection: const SelectionState(selectedIds: selectedIds),
          ),
          application: DrawState().application.copyWith(
            selectionOverlay: SelectionOverlayState(
              multiSelectOverlay: MultiSelectOverlayState(
                bounds: initialBounds!,
                rotation: initialRotation,
              ),
            ),
          ),
        );

        final store = _createStore(initialState: initialState);
        addTearDown(store.dispose);

        final beforeBounds =
            store.state.application.selectionOverlay.multiSelectOverlay!.bounds;

        await store.dispatch(
          UpdateElementsStyle(elementIds: ['text-1'], fontSize: 32),
        );

        final selectedElements = SelectionCalculator.getSelectedElements(
          store.state,
        );
        final expectedBounds =
            SelectionCalculator.computeSelectionBoundsForElements(
              selectedElements,
            );
        final overlay =
            store.state.application.selectionOverlay.multiSelectOverlay;

        expect(expectedBounds, isNotNull);
        expect(expectedBounds, isNot(beforeBounds));
        expect(overlay, isNotNull);
        expect(overlay!.bounds, expectedBounds);
        expect(overlay.rotation, initialRotation);
      },
    );
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

ElementState _buildTextElement({
  required String id,
  required double originX,
  required double originY,
  required String text,
  double fontSize = 16,
}) {
  final data = TextData(text: text, fontSize: fontSize);
  final rect = _resolveAutoResizeTextRect(
    originX: originX,
    originY: originY,
    data: data,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: id == 'text-1' ? 0 : 1,
    data: data,
  );
}

DrawRect _resolveAutoResizeTextRect({
  required double originX,
  required double originY,
  required TextData data,
}) {
  final layout = layoutText(data: data, maxWidth: double.infinity);
  final horizontalPadding = resolveTextLayoutHorizontalPadding(
    layout.lineHeight,
  );
  final width = layout.size.width + horizontalPadding * 2;
  final height = layout.size.height > layout.lineHeight
      ? layout.size.height
      : layout.lineHeight;
  return DrawRect(
    minX: originX,
    minY: originY,
    maxX: originX + width,
    maxY: originY + height,
  );
}
