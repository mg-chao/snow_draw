import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/filter_style_state_change.dart';

void main() {
  test('detects filter style mutation and reports changed ids', () {
    final previous = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(strength: 0.2),
        ),
      ],
    );
    final next = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(strength: 0.9),
        ),
      ],
    );

    final mutation = resolveFilterStyleMutation(previous: previous, next: next);
    expect(mutation, isNotNull);
    expect(mutation!.changedFilterElementIds, {'filter'});
  });

  test('detects filter opacity-only mutation as style update', () {
    final previous = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(),
        ),
      ],
    );
    final next = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 0.45,
          zIndex: 1,
          data: FilterData(),
        ),
      ],
    );

    final mutation = resolveFilterStyleMutation(previous: previous, next: next);
    expect(mutation, isNotNull);
    expect(mutation!.changedFilterElementIds, {'filter'});
  });

  test('returns null when a non-filter element changes', () {
    final previous = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(),
        ),
      ],
    );
    final next = _buildState(
      elements: const [
        ElementState(
          id: 'base',
          rect: DrawRect(maxX: 200, maxY: 200),
          rotation: 0,
          opacity: 0.5,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(),
        ),
      ],
    );

    expect(resolveFilterStyleMutation(previous: previous, next: next), isNull);
  });

  test('returns null when filter geometry changes', () {
    final previous = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(type: CanvasFilterType.grayscale),
        ),
      ],
    );
    final next = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 24, minY: 20, maxX: 84, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(type: CanvasFilterType.grayscale),
        ),
      ],
    );

    expect(resolveFilterStyleMutation(previous: previous, next: next), isNull);
  });

  test('returns null when selection state changes', () {
    final previous = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(strength: 0.2),
        ),
      ],
    );
    final next = _buildState(
      elements: const [
        _baseElement,
        ElementState(
          id: 'filter',
          rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: FilterData(strength: 0.6),
        ),
      ],
      selectedIds: const {},
    );

    expect(resolveFilterStyleMutation(previous: previous, next: next), isNull);
  });
}

const _baseElement = ElementState(
  id: 'base',
  rect: DrawRect(maxX: 200, maxY: 200),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

DrawState _buildState({
  required List<ElementState> elements,
  Set<String> selectedIds = const {'filter'},
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);
