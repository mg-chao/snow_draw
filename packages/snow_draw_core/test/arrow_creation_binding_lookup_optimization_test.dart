import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/utils/snapping_mode.dart';

void main() {
  group('ArrowCreationStrategy binding lookup optimization', () {
    test('reuses binding target queries for nearby move updates', () {
      const target = ElementState(
        id: 'target',
        rect: DrawRect(minX: 80, minY: 80, maxX: 220, maxY: 220),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final counter = _HitTestCounter();
      final document = _CountingDocumentState(
        elements: const [target],
        counter: counter,
      );
      final state = _stateWith(document);

      const strategy = ArrowCreationStrategy();
      const start = DrawPoint(x: 100, y: 100);
      const data = ArrowData();
      final startResult = strategy.start(data: data, startPosition: start);
      var creating = _creatingState(
        elementId: 'arrow',
        startPosition: start,
        startResult: startResult,
      );

      counter.reset();
      final firstUpdate = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 160, y: 140),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );
      creating = _applyUpdate(creating, firstUpdate);
      final callsAfterFirstUpdate = counter.value;

      final secondUpdate = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 162, y: 141),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );
      creating = _applyUpdate(creating, secondUpdate);
      final callsAfterSecondUpdate = counter.value;
      expect(creating.currentRect, isNotNull);

      expect(callsAfterFirstUpdate, greaterThan(0));
      expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
    });

    test(
      'skips binding target queries when document has no bindable elements',
      () {
        const nonBindable = ElementState(
          id: 'existing-arrow',
          rect: DrawRect(minX: 20, minY: 20, maxX: 60, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: ArrowData(),
        );
        final counter = _HitTestCounter();
        final document = _CountingDocumentState(
          elements: const [nonBindable],
          counter: counter,
        );
        final state = _stateWith(document);

        const strategy = ArrowCreationStrategy();
        const start = DrawPoint(x: 100, y: 100);
        final startResult = strategy.start(
          data: const ArrowData(),
          startPosition: start,
        );
        final creating = _creatingState(
          elementId: 'arrow',
          startPosition: start,
          startResult: startResult,
        );

        counter.reset();
        strategy.update(
          state: state,
          config: DrawConfig.defaultConfig,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 180, y: 180),
          maintainAspectRatio: false,
          createFromCenter: false,
          snappingMode: SnappingMode.none,
        );

        expect(counter.value, 0);
      },
    );
  });
}

class _CountingDocumentState extends DocumentState {
  _CountingDocumentState({required super.elements, required this.counter});

  final _HitTestCounter counter;

  @override
  void visitElementsAtPointTopDown(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor,
  ) {
    counter.value++;
    super.visitElementsAtPointTopDown(point, tolerance, visitor);
  }
}

class _HitTestCounter {
  var value = 0;

  void reset() {
    value = 0;
  }
}

DrawState _stateWith(DocumentState document) =>
    DrawState(domain: DomainState(document: document));

CreatingState _creatingState({
  required String elementId,
  required DrawPoint startPosition,
  required CreationUpdateResult startResult,
}) => CreatingState(
  element: ElementState(
    id: elementId,
    rect: DrawRect(
      minX: startPosition.x,
      minY: startPosition.y,
      maxX: startPosition.x,
      maxY: startPosition.y,
    ),
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: startResult.data,
  ),
  startPosition: startPosition,
  currentRect: startResult.rect,
  creationMode: startResult.creationMode,
  snapGuides: startResult.snapGuides,
);

CreatingState _applyUpdate(
  CreatingState current,
  CreationUpdateResult update,
) => current.copyWith(
  element: current.element.copyWith(data: update.data),
  currentRect: update.rect,
  creationMode: update.creationMode,
  snapGuides: update.snapGuides,
);
