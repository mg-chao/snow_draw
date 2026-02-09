import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  test('collects document highlights in document order', () {
    final state = _buildState(
      elements: const [
        ElementState(
          id: 'h1',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(),
        ),
        ElementState(
          id: 'r1',
          rect: DrawRect(minX: 12, maxX: 22, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        ElementState(
          id: 'h2',
          rect: DrawRect(minX: 24, maxX: 34, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: HighlightData(),
        ),
      ],
    );

    final view = DrawStateView.fromState(state);
    final highlights = view.highlightMaskScene.elements;

    expect(highlights.map((e) => e.id).toList(), ['h1', 'h2']);
    expect(view.highlightMaskScene.hasHighlights, isTrue);
  });

  test('applies preview override precedence over document elements', () {
    const docHighlight = ElementState(
      id: 'e1',
      rect: DrawRect(maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: HighlightData(),
    );
    const previewReplacedAsRectangle = ElementState(
      id: 'e1',
      rect: DrawRect(maxX: 10, maxY: 10),
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: RectangleData(),
    );

    final state = _buildState(elements: const [docHighlight]);
    final view = DrawStateView.withPreview(
      state: state,
      previewElementsById: const {'e1': previewReplacedAsRectangle},
      effectiveSelection: EffectiveSelection.none,
      snapGuides: const [],
    );

    expect(view.highlightMaskScene.elements, isEmpty);
    expect(view.highlightMaskScene.hasHighlights, isFalse);
  });

  test(
    'includes preview-only transient highlights after document highlights',
    () {
      const docHighlight = ElementState(
        id: 'h1',
        rect: DrawRect(maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: HighlightData(),
      );
      const transientPreviewHighlight = ElementState(
        id: 'h_preview',
        rect: DrawRect(minX: 12, maxX: 22, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 99,
        data: HighlightData(),
      );

      final state = _buildState(elements: const [docHighlight]);
      final view = DrawStateView.withPreview(
        state: state,
        previewElementsById: const {'h_preview': transientPreviewHighlight},
        effectiveSelection: EffectiveSelection.none,
        snapGuides: const [],
      );

      expect(
        view.highlightMaskScene.elements.map((element) => element.id).toList(),
        ['h1', 'h_preview'],
      );
    },
  );

  test('includes creating highlight with current rect as last element', () {
    const creatingRect = DrawRect(minX: 30, minY: 40, maxX: 70, maxY: 90);
    final creatingInteraction = CreatingState(
      element: const ElementState(
        id: 'creating',
        rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 5,
        data: HighlightData(),
      ),
      startPosition: const DrawPoint(x: 0, y: 0),
      currentRect: creatingRect,
    );
    final state = _buildState(
      elements: const [
        ElementState(
          id: 'h1',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(),
        ),
      ],
      interaction: creatingInteraction,
    );

    final view = DrawStateView.fromState(state);
    final highlights = view.highlightMaskScene.elements;

    expect(highlights.map((element) => element.id).toList(), [
      'h1',
      'creating',
    ]);
    expect(highlights.last.rect, creatingRect);
  });

  test('excludes creating element when it is not a highlight', () {
    final creatingInteraction = CreatingState(
      element: const ElementState(
        id: 'creating_rect',
        rect: DrawRect(minX: 0, minY: 0, maxX: 10, maxY: 10),
        rotation: 0,
        opacity: 1,
        zIndex: 5,
        data: RectangleData(),
      ),
      startPosition: const DrawPoint(x: 0, y: 0),
      currentRect: const DrawRect(minX: 30, minY: 40, maxX: 70, maxY: 90),
    );
    final state = _buildState(
      elements: const [
        ElementState(
          id: 'h1',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: HighlightData(),
        ),
      ],
      interaction: creatingInteraction,
    );

    final view = DrawStateView.fromState(state);
    expect(view.highlightMaskScene.elements.map((element) => element.id), [
      'h1',
    ]);
  });
}

DrawState _buildState({
  required List<ElementState> elements,
  InteractionState interaction = const IdleState(),
}) {
  final initial = DrawState.initial();
  return initial.copyWith(
    domain: initial.domain.copyWith(
      document: initial.domain.document.copyWith(elements: elements),
    ),
    application: initial.application.copyWith(interaction: interaction),
  );
}
