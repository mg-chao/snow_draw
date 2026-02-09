import 'package:flutter_test/flutter_test.dart';
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
    final state = _stateWith();
    final view = DrawStateView.fromState(state);

    final splitIndex = resolveDynamicLayerStartIndex(view);
    expect(splitIndex, isNull);
  });

  test('returns earliest selected element index', () {
    final state = _stateWith(selectedIds: const {'e2', 'e3'});
    final view = DrawStateView.fromState(state);

    final splitIndex = resolveDynamicLayerStartIndex(view);
    expect(splitIndex, 1);
  });

  test(
    'lifts all document elements when selected range includes highlight',
    () {
      final state = _stateWith(
        selectedIds: const {'e1'},
        elements: const [
          ElementState(
            id: 'e1',
            rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: RectangleData(),
          ),
          ElementState(
            id: 'h1',
            rect: DrawRect(minX: 20, minY: 0, maxX: 30, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 1,
            data: HighlightData(),
          ),
          ElementState(
            id: 'e3',
            rect: DrawRect(minX: 40, minY: 0, maxX: 50, maxY: 10),
            rotation: 0,
            opacity: 1,
            zIndex: 2,
            data: RectangleData(),
          ),
        ],
      );
      final view = DrawStateView.fromState(state);

      final splitIndex = resolveDynamicLayerStartIndex(view);
      expect(splitIndex, 0);
    },
  );

  test('keeps earliest selected index when no highlight in dynamic range', () {
    final state = _stateWith(
      selectedIds: const {'e2'},
      elements: const [
        ElementState(
          id: 'e1',
          rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(),
        ),
        ElementState(
          id: 'e2',
          rect: DrawRect(minX: 20, minY: 0, maxX: 30, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        ElementState(
          id: 'e3',
          rect: DrawRect(minX: 40, minY: 0, maxX: 50, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
      ],
    );
    final view = DrawStateView.fromState(state);

    final splitIndex = resolveDynamicLayerStartIndex(view);
    expect(splitIndex, 1);
  });

  test('lifts all document elements while creating highlight', () {
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
    final state = _stateWith(interaction: interaction);
    final view = DrawStateView.fromState(state);

    final splitIndex = resolveDynamicLayerStartIndex(view);
    expect(splitIndex, 0);
  });

  test('lifts all document elements while creating new text', () {
    const interaction = TextEditingState(
      elementId: 't_new',
      draftData: TextData(text: 'draft'),
      rect: DrawRect(minX: 5, minY: 5, maxX: 25, maxY: 15),
      isNew: true,
      opacity: 1,
      rotation: 0,
    );
    final state = _stateWith(interaction: interaction);
    final view = DrawStateView.fromState(state);

    final splitIndex = resolveDynamicLayerStartIndex(view);
    expect(splitIndex, 0);
  });
}

DrawState _stateWith({
  Set<String> selectedIds = const <String>{},
  InteractionState interaction = const IdleState(),
  List<ElementState>? elements,
}) {
  const defaultElements = [
    ElementState(
      id: 'e1',
      rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    ),
    ElementState(
      id: 'e2',
      rect: DrawRect(minX: 20, minY: 0, maxX: 30, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 1,
      data: RectangleData(),
    ),
    ElementState(
      id: 'e3',
      rect: DrawRect(minX: 40, minY: 0, maxX: 50, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 2,
      data: RectangleData(),
    ),
  ];

  final initial = DrawState.initial();
  final domain = initial.domain.copyWith(
    document: initial.domain.document.copyWith(
      elements: elements ?? defaultElements,
    ),
    selection: initial.domain.selection.withSelectedIds(selectedIds),
  );
  final application = initial.application.copyWith(interaction: interaction);
  return initial.copyWith(domain: domain, application: application);
}
