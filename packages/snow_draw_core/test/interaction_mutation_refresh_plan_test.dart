import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/ui/canvas/interaction_mutation_refresh_plan.dart';

void main() {
  group('resolveInteractionMutationRefreshPlan', () {
    test('resolves serial-number creation as dynamic-only', () {
      final base = _baseState(elements: const [_serialElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 24, y: 24),
          currentRect: const DrawRect(minX: 10, minY: 10, maxX: 38, maxY: 38),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 24, y: 24),
          currentRect: const DrawRect(minX: 14, minY: 14, maxX: 42, maxY: 42),
        ),
      );

      final plan = resolveInteractionMutationRefreshPlan(
        previous: previous,
        next: next,
      );

      expect(plan, isNotNull);
      expect(plan!.kind, InteractionMutationKind.serialNumber);
      expect(plan.refreshMode, InteractionMutationRefreshMode.dynamicOnly);
    });

    test('resolves lightweight line creation as dynamic-only', () {
      final base = _baseState(elements: const [_lineElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _lineElement,
          startPosition: const DrawPoint(x: 40, y: 40),
          currentRect: const DrawRect(minX: 40, minY: 40, maxX: 40, maxY: 40),
          creationMode: const PointCreationMode(
            fixedPoints: [DrawPoint(x: 40, y: 40)],
            currentPoint: DrawPoint(x: 40, y: 40),
          ),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _lineElement,
          startPosition: const DrawPoint(x: 40, y: 40),
          currentRect: const DrawRect(minX: 40, minY: 40, maxX: 72, maxY: 64),
          creationMode: const PointCreationMode(
            fixedPoints: [DrawPoint(x: 40, y: 40)],
            currentPoint: DrawPoint(x: 72, y: 64),
          ),
        ),
      );

      final plan = resolveInteractionMutationRefreshPlan(
        previous: previous,
        next: next,
      );

      expect(plan, isNotNull);
      expect(plan!.kind, InteractionMutationKind.lightweightLine);
      expect(plan.refreshMode, InteractionMutationRefreshMode.dynamicOnly);
    });

    test('resolves rectangle creation as dynamic-only', () {
      final base = _baseState(elements: const [_rectangleElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _rectangleElement,
          startPosition: const DrawPoint(x: 30, y: 30),
          currentRect: const DrawRect(minX: 30, minY: 30, maxX: 30, maxY: 30),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _rectangleElement,
          startPosition: const DrawPoint(x: 30, y: 30),
          currentRect: const DrawRect(minX: 30, minY: 30, maxX: 80, maxY: 70),
        ),
      );

      final plan = resolveInteractionMutationRefreshPlan(
        previous: previous,
        next: next,
      );

      expect(plan, isNotNull);
      expect(plan!.kind, InteractionMutationKind.rectangle);
      expect(plan.refreshMode, InteractionMutationRefreshMode.dynamicOnly);
    });

    test('resolves highlight creation as dynamic-only', () {
      final base = _baseState(elements: const [_highlightElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _highlightElement,
          startPosition: const DrawPoint(x: 36, y: 36),
          currentRect: const DrawRect(minX: 36, minY: 36, maxX: 36, maxY: 36),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _highlightElement,
          startPosition: const DrawPoint(x: 36, y: 36),
          currentRect: const DrawRect(minX: 36, minY: 36, maxX: 92, maxY: 54),
        ),
      );

      final plan = resolveInteractionMutationRefreshPlan(
        previous: previous,
        next: next,
      );

      expect(plan, isNotNull);
      expect(plan!.kind, InteractionMutationKind.highlight);
      expect(plan.refreshMode, InteractionMutationRefreshMode.dynamicOnly);
    });

    test('resolves arrow creation as dynamic-only', () {
      final base = _baseState(elements: const [_arrowElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _arrowElement,
          startPosition: const DrawPoint(x: 18, y: 18),
          currentRect: const DrawRect(minX: 18, minY: 18, maxX: 18, maxY: 18),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _arrowElement,
          startPosition: const DrawPoint(x: 18, y: 18),
          currentRect: const DrawRect(minX: 18, minY: 18, maxX: 78, maxY: 48),
        ),
      );

      final plan = resolveInteractionMutationRefreshPlan(
        previous: previous,
        next: next,
      );

      expect(plan, isNotNull);
      expect(plan!.kind, InteractionMutationKind.arrow);
      expect(plan.refreshMode, InteractionMutationRefreshMode.dynamicOnly);
    });

    test('returns null when domain changes', () {
      final base = _baseState(elements: const [_serialElement]);
      final previous = _withInteraction(
        base,
        _creatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 24, y: 24),
          currentRect: const DrawRect(minX: 10, minY: 10, maxX: 38, maxY: 38),
        ),
      );
      final next = _withInteraction(
        base,
        _creatingState(
          element: _serialElement,
          startPosition: const DrawPoint(x: 24, y: 24),
          currentRect: const DrawRect(minX: 14, minY: 14, maxX: 42, maxY: 42),
        ),
      ).copyWith(domain: previous.domain.withSelected('serial'));

      final plan = resolveInteractionMutationRefreshPlan(
        previous: previous,
        next: next,
      );

      expect(plan, isNull);
    });
  });
}

CreatingState _creatingState({
  required ElementState element,
  required DrawPoint startPosition,
  required DrawRect currentRect,
  CreationMode creationMode = const RectCreationMode(),
}) => CreatingState(
  element: element,
  startPosition: startPosition,
  currentRect: currentRect,
  creationMode: creationMode,
);

const _serialElement = ElementState(
  id: 'serial',
  rect: DrawRect(minX: 10, minY: 10, maxX: 38, maxY: 38),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: SerialNumberData(),
);

const _lineElement = ElementState(
  id: 'line',
  rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: LineData(),
);

const _rectangleElement = ElementState(
  id: 'rectangle',
  rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: RectangleData(),
);

const _highlightElement = ElementState(
  id: 'highlight',
  rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: HighlightData(),
);

const _arrowElement = ElementState(
  id: 'arrow',
  rect: DrawRect(minX: 20, minY: 20, maxX: 80, maxY: 80),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: ArrowData(),
);

DrawState _baseState({
  required List<ElementState> elements,
  Set<String> selectedIds = const <String>{},
}) => DrawState(
  domain: DomainState(
    document: DocumentState(elements: elements),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);

DrawState _withInteraction(DrawState base, InteractionState interaction) => base
    .copyWith(application: base.application.copyWith(interaction: interaction));
