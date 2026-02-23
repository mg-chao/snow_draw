import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  test('collects document highlights in document order', () {
    final state = _buildState(
      elements: [
        _highlight(id: 'h1'),
        _rectangle(
          id: 'r1',
          rect: const DrawRect(minX: 12, maxX: 22, maxY: 10),
          zIndex: 1,
        ),
        _highlight(
          id: 'h2',
          rect: const DrawRect(minX: 24, maxX: 34, maxY: 10),
          zIndex: 2,
        ),
      ],
    );

    final view = DrawStateView.fromState(state);

    expect(_ids(view.highlightMaskScene.elements), ['h1', 'h2']);
    expect(view.highlightMaskScene.hasHighlights, isTrue);
  });

  test('applies preview override precedence over document elements', () {
    final docHighlight = _highlight(id: 'e1');
    final previewReplacedAsRectangle = _rectangle(id: 'e1');

    final state = _buildState(elements: [docHighlight]);
    final view = _buildPreviewView(
      state: state,
      previewElementsById: {'e1': previewReplacedAsRectangle},
    );

    expect(view.highlightMaskScene.elements, isEmpty);
    expect(view.highlightMaskScene.hasHighlights, isFalse);
  });

  test(
    'includes preview-only transient highlights after document highlights',
    () {
      final transientPreviewHighlight = _highlight(
        id: 'h_preview',
        rect: const DrawRect(minX: 12, maxX: 22, maxY: 10),
        zIndex: 99,
      );

      final state = _buildState(elements: [_highlight(id: 'h1')]);
      final view = _buildPreviewView(
        state: state,
        previewElementsById: {'h_preview': transientPreviewHighlight},
      );

      expect(_ids(view.highlightMaskScene.elements), ['h1', 'h_preview']);
      expect(view.highlightMaskScene.hasHighlights, isTrue);
    },
  );

  test('includes creating highlight with current rect as last element', () {
    const creatingRect = DrawRect(minX: 30, minY: 40, maxX: 70, maxY: 90);
    final creatingInteraction = CreatingState(
      element: _highlight(id: 'creating', zIndex: 5),
      startPosition: DrawPoint.zero,
      currentRect: creatingRect,
    );
    final state = _buildState(
      elements: [_highlight(id: 'h1')],
      interaction: creatingInteraction,
    );

    final view = DrawStateView.fromState(state);
    final highlights = view.highlightMaskScene.elements;

    expect(_ids(highlights), ['h1', 'creating']);
    expect(highlights.last.rect, creatingRect);
    expect(view.highlightMaskScene.hasHighlights, isTrue);
  });

  test(
    'deduplicates creating highlight when preview map already contains it',
    () {
      const creatingId = 'creating';
      const currentRect = DrawRect(minX: 30, minY: 40, maxX: 70, maxY: 90);
      const previewRect = DrawRect(minX: 1, minY: 2, maxX: 3, maxY: 4);
      final creatingInteraction = CreatingState(
        element: _highlight(id: creatingId, zIndex: 5),
        startPosition: DrawPoint.zero,
        currentRect: currentRect,
      );
      final state = _buildState(
        elements: [_highlight(id: 'h1')],
        interaction: creatingInteraction,
      );
      final previewHighlight = _highlight(
        id: creatingId,
        rect: previewRect,
        zIndex: 5,
      );

      final view = _buildPreviewView(
        state: state,
        previewElementsById: {creatingId: previewHighlight},
      );

      final highlights = view.highlightMaskScene.elements;
      expect(_ids(highlights), ['h1', creatingId]);
      expect(
        highlights.where((element) => element.id == creatingId),
        hasLength(1),
      );
      expect(highlights.last.rect, currentRect);
      expect(view.highlightMaskScene.hasHighlights, isTrue);
    },
  );

  test('excludes creating element when it is not a highlight', () {
    final creatingInteraction = CreatingState(
      element: _rectangle(id: 'creating_rect', zIndex: 5),
      startPosition: DrawPoint.zero,
      currentRect: const DrawRect(minX: 30, minY: 40, maxX: 70, maxY: 90),
    );
    final state = _buildState(
      elements: [_highlight(id: 'h1')],
      interaction: creatingInteraction,
    );

    final view = DrawStateView.fromState(state);
    expect(_ids(view.highlightMaskScene.elements), ['h1']);
    expect(view.highlightMaskScene.hasHighlights, isTrue);
  });

  test('keeps edited highlight previews in document order', () {
    final h1 = _highlight(id: 'h1');
    final h2 = _highlight(
      id: 'h2',
      rect: const DrawRect(minX: 20, maxX: 30, maxY: 10),
      zIndex: 1,
    );
    final movedH2 = h2.copyWith(
      rect: const DrawRect(minX: 24, minY: 2, maxX: 34, maxY: 12),
    );

    final state = _buildState(elements: [h1, h2]);
    final view = _buildPreviewView(
      state: state,
      previewElementsById: {h2.id: movedH2},
    );

    expect(_ids(view.highlightMaskScene.elements), ['h1', 'h2']);
    expect(view.highlightMaskScene.elements.last.rect, movedH2.rect);
    expect(view.highlightMaskScene.hasHighlights, isTrue);
  });
}

DrawStateView _buildPreviewView({
  required DrawState state,
  required Map<String, ElementState> previewElementsById,
}) => DrawStateView.withPreview(
  state: state,
  previewElementsById: previewElementsById,
  effectiveSelection: EffectiveSelection.none,
  snapGuides: const [],
);

ElementState _highlight({
  required String id,
  DrawRect rect = const DrawRect(maxX: 10, maxY: 10),
  int zIndex = 0,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const HighlightData(),
);

ElementState _rectangle({
  required String id,
  DrawRect rect = const DrawRect(maxX: 10, maxY: 10),
  int zIndex = 0,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);

List<String> _ids(Iterable<ElementState> elements) =>
    elements.map((element) => element.id).toList();

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
