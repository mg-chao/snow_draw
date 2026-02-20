import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/dynamic_layer_split.dart';

void main() {
  test('returns null when no split is needed', () {
    expect(_splitIndex(_stateWith()), isNull);
  });

  test('returns earliest selected element index', () {
    expect(_splitIndex(_stateWith(selectedIds: const {'e2', 'e3'})), 1);
  });

  test('highlight above selection does not force full-scene lifting', () {
    expect(
      _splitIndex(
        _stateWith(
          selectedIds: const {'e2'},
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: RectangleData(),
            ),
            ElementState(
              id: 'e2',
              rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: RectangleData(),
            ),
            ElementState(
              id: 'h1',
              rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 2,
              data: HighlightData(),
            ),
          ],
        ),
      ),
      1,
    );
  });

  test('selected highlight keeps dynamic split scoped to its z-index', () {
    expect(
      _splitIndex(
        _stateWith(
          selectedIds: const {'h1'},
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: RectangleData(),
            ),
            ElementState(
              id: 'h1',
              rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: HighlightData(),
            ),
            ElementState(
              id: 'e3',
              rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 2,
              data: RectangleData(),
            ),
          ],
        ),
      ),
      1,
    );
  });

  test('keeps earliest selected index when no highlight in dynamic range', () {
    expect(
      _splitIndex(
        _stateWith(
          selectedIds: const {'e2'},
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: HighlightData(),
            ),
            ElementState(
              id: 'e2',
              rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: RectangleData(),
            ),
            ElementState(
              id: 'e3',
              rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 2,
              data: RectangleData(),
            ),
          ],
        ),
      ),
      1,
    );
  });

  test('highlight creation keeps committed scene on static layer', () {
    final interaction = CreatingState(
      element: const ElementState(
        id: 'h_new',
        rect: DrawRect(minX: 10, minY: 10, maxX: 20, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 99,
        data: HighlightData(),
      ),
      startPosition: const DrawPoint(x: 10, y: 10),
      currentRect: const DrawRect(minX: 10, minY: 10, maxX: 20, maxY: 20),
    );
    expect(_splitIndex(_stateWith(interaction: interaction)), isNull);
  });

  test('creating filter lifts all document elements', () {
    final interaction = CreatingState(
      element: const ElementState(
        id: 'f_new',
        rect: DrawRect(minX: 10, minY: 10, maxX: 20, maxY: 20),
        rotation: 0,
        opacity: 1,
        zIndex: 99,
        data: FilterData(),
      ),
      startPosition: const DrawPoint(x: 10, y: 10),
      currentRect: const DrawRect(minX: 10, minY: 10, maxX: 20, maxY: 20),
    );
    expect(_splitIndex(_stateWith(interaction: interaction)), 0);
  });

  test('selecting filter lifts all document elements', () {
    expect(
      _splitIndex(
        _stateWith(
          selectedIds: const {'f1'},
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: RectangleData(),
            ),
            ElementState(
              id: 'f1',
              rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: FilterData(),
            ),
            ElementState(
              id: 'e3',
              rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 2,
              data: RectangleData(),
            ),
          ],
        ),
      ),
      0,
    );
  });

  test('selected range including filter lifts all document elements', () {
    expect(
      _splitIndex(
        _stateWith(
          selectedIds: const {'e1'},
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: RectangleData(),
            ),
            ElementState(
              id: 'f1',
              rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: FilterData(),
            ),
            ElementState(
              id: 'e3',
              rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 2,
              data: RectangleData(),
            ),
          ],
        ),
      ),
      0,
    );
  });

  test('transparent filter does not force full-scene lifting', () {
    expect(
      _splitIndex(
        _stateWith(
          selectedIds: const {'e2'},
          elements: const [
            ElementState(
              id: 'e1',
              rect: DrawRect(maxX: 10, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 0,
              data: RectangleData(),
            ),
            ElementState(
              id: 'e2',
              rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
              rotation: 0,
              opacity: 1,
              zIndex: 1,
              data: RectangleData(),
            ),
            ElementState(
              id: 'f1',
              rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
              rotation: 0,
              opacity: 0,
              zIndex: 2,
              data: FilterData(),
            ),
          ],
        ),
      ),
      1,
    );
  });

  test('keeps static scene when creating new text', () {
    const interaction = TextEditingState(
      elementId: 't_new',
      draftData: TextData(text: 'draft'),
      rect: DrawRect(minX: 5, minY: 5, maxX: 25, maxY: 15),
      isNew: true,
      opacity: 1,
      rotation: 0,
    );
    expect(_splitIndex(_stateWith(interaction: interaction)), isNull);
  });
}

int? _splitIndex(DrawState state) =>
    resolveDynamicLayerStartIndex(DrawStateView.fromState(state));

const _defaultElements = <ElementState>[
  ElementState(
    id: 'e1',
    rect: DrawRect(maxX: 10, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: RectangleData(),
  ),
  ElementState(
    id: 'e2',
    rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: RectangleData(),
  ),
  ElementState(
    id: 'e3',
    rect: DrawRect(minX: 40, maxX: 50, maxY: 10),
    rotation: 0,
    opacity: 1,
    zIndex: 2,
    data: RectangleData(),
  ),
];

DrawState _stateWith({
  Set<String> selectedIds = const <String>{},
  InteractionState interaction = const IdleState(),
  List<ElementState> elements = _defaultElements,
}) {
  final initial = DrawState.initial();
  return initial.copyWith(
    domain: initial.domain.copyWith(
      document: initial.domain.document.copyWith(elements: elements),
      selection: initial.domain.selection.withSelectedIds(selectedIds),
    ),
    application: initial.application.copyWith(interaction: interaction),
  );
}
