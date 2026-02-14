import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/preview/edit_preview.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';

void main() {
  group('buildSelectionPreview', () {
    test('uses preview element geometry for selected ids', () {
      const baseElement = ElementState(
        id: 'a',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(),
      );
      const previewElement = ElementState(
        id: 'a',
        rect: DrawRect(minX: 40, minY: 40, maxX: 70, maxY: 70),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(),
      );
      final state = _state(
        elements: const [baseElement],
        selectedIds: const {'a'},
      );
      final context = _moveContext(
        selectedIds: const {'a'},
        startBounds: baseElement.rect,
        elementsVersion: state.domain.document.elementsVersion,
      );

      final preview = buildSelectionPreview(
        state: state,
        context: context,
        previewElementsById: const {'a': previewElement},
      );

      expect(preview, isNotNull);
      expect(preview!.bounds, previewElement.rect);
      expect(preview.center, previewElement.center);
    });

    test('falls back to document element when preview is absent', () {
      const element = ElementState(
        id: 'a',
        rect: DrawRect(minX: 20, minY: 10, maxX: 60, maxY: 40),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: FilterData(),
      );
      final state = _state(elements: const [element], selectedIds: const {'a'});
      final context = _moveContext(
        selectedIds: const {'a'},
        startBounds: element.rect,
        elementsVersion: state.domain.document.elementsVersion,
      );

      final preview = buildSelectionPreview(
        state: state,
        context: context,
        previewElementsById: const {},
      );

      expect(preview, isNotNull);
      expect(preview!.bounds, element.rect);
      expect(preview.center, element.center);
    });

    test('supports selected preview-only ids that are not in document', () {
      const previewElement = ElementState(
        id: 'ghost',
        rect: DrawRect(minX: 5, minY: 5, maxX: 25, maxY: 30),
        rotation: 0,
        opacity: 1,
        zIndex: 3,
        data: FilterData(),
      );
      final state = _state(elements: const [], selectedIds: const {'ghost'});
      final context = _moveContext(
        selectedIds: const {'ghost'},
        startBounds: previewElement.rect,
        elementsVersion: state.domain.document.elementsVersion,
      );

      final preview = buildSelectionPreview(
        state: state,
        context: context,
        previewElementsById: const {'ghost': previewElement},
      );

      expect(preview, isNotNull);
      expect(preview!.bounds, previewElement.rect);
      expect(preview.center, previewElement.center);
    });
  });
}

DrawState _state({
  required List<ElementState> elements,
  required Set<String> selectedIds,
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);

MoveEditContext _moveContext({
  required Set<String> selectedIds,
  required DrawRect startBounds,
  required int elementsVersion,
}) => MoveEditContext(
  startPosition: startBounds.center,
  startBounds: startBounds,
  selectedIdsAtStart: selectedIds,
  selectionVersion: 0,
  elementsVersion: elementsVersion,
  elementSnapshots: const {},
);
