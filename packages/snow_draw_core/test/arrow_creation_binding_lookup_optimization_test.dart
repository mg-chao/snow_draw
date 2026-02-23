import 'package:test/test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/utils/snapping_mode.dart';

const _strategy = ArrowCreationStrategy();

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
      final state = _stateWith(
        _CountingDocumentState(elements: const [target], counter: counter),
      );

      const start = DrawPoint(x: 100, y: 100);
      var creating = _creatingState(
        elementId: 'arrow',
        startPosition: start,
        startResult: _strategy.start(
          data: const ArrowData(),
          startPosition: start,
        ),
      );

      counter.reset();
      final firstUpdate = _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 160, y: 140),
      );
      creating = _applyUpdate(creating, firstUpdate);
      final callsAfterFirstUpdate = counter.value;

      _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 162, y: 141),
      );
      final callsAfterSecondUpdate = counter.value;

      expect(callsAfterFirstUpdate, greaterThan(0));
      expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
    });

    test('arrow creation reuses target cache for medium pointer moves', () {
      const target = ElementState(
        id: 'target',
        rect: DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final counter = _HitTestCounter();
      final state = _stateWith(
        _CountingDocumentState(elements: const [target], counter: counter),
      );

      const start = DrawPoint(x: 80, y: 80);
      var creating = _creatingState(
        elementId: 'arrow',
        startPosition: start,
        startResult: _strategy.start(
          data: const ArrowData(),
          startPosition: start,
        ),
      );

      counter.reset();
      final firstUpdate = _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 209, y: 160),
      );
      creating = _applyUpdate(creating, firstUpdate);
      final callsAfterFirstUpdate = counter.value;

      _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 217, y: 160),
      );
      final callsAfterSecondUpdate = counter.value;

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
        final state = _stateWith(
          _CountingDocumentState(
            elements: const [nonBindable],
            counter: counter,
          ),
        );

        const start = DrawPoint(x: 100, y: 100);
        final creating = _creatingState(
          elementId: 'arrow',
          startPosition: start,
          startResult: _strategy.start(
            data: const ArrowData(),
            startPosition: start,
          ),
        );

        counter.reset();
        _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 180, y: 180),
        );

        expect(counter.value, 0);
      },
    );

    test(
      'keeps preferred binding without re-query after large pointer move',
      () {
        const target = ElementState(
          id: 'target',
          rect: DrawRect(minX: 140, minY: 140, maxX: 280, maxY: 280),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        );
        final counter = _HitTestCounter();
        final state = _stateWith(
          _CountingDocumentState(elements: const [target], counter: counter),
        );

        const start = DrawPoint(x: 30, y: 30);
        var creating = _creatingState(
          elementId: 'arrow',
          startPosition: start,
          startResult: _strategy.start(
            data: const ArrowData(),
            startPosition: start,
          ),
        );

        counter.reset();
        final firstUpdate = _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 180, y: 180),
        );
        creating = _applyUpdate(creating, firstUpdate);
        final callsAfterFirstUpdate = counter.value;

        _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 220, y: 220),
        );
        final callsAfterSecondUpdate = counter.value;

        expect(callsAfterFirstUpdate, greaterThan(0));
        expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
      },
    );

    test('re-evaluates cached start binding when binding config changes', () {
      const target = ElementState(
        id: 'target',
        rect: DrawRect(minX: 80, minY: 80, maxX: 220, maxY: 220),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final state = _stateWith(DocumentState(elements: const [target]));

      const start = DrawPoint(x: 100, y: 100);
      var creating = _creatingState(
        elementId: 'arrow',
        startPosition: start,
        startResult: _strategy.start(
          data: const ArrowData(),
          startPosition: start,
        ),
      );

      final firstUpdate = _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 170, y: 170),
      );
      creating = _applyUpdate(creating, firstUpdate);
      final firstData = firstUpdate.data as ArrowData;
      expect(firstData.startBinding, isNotNull);

      final secondUpdate = _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 172, y: 172),
      );
      creating = _applyUpdate(creating, secondUpdate);
      final secondData = secondUpdate.data as ArrowData;
      expect(secondData.startBinding, isNotNull);

      final bindingDisabledConfig = DrawConfig.defaultConfig.copyWith(
        snap: DrawConfig.defaultConfig.snap.copyWith(enableArrowBinding: false),
      );
      final thirdUpdate = _updateCreation(
        state: state,
        config: bindingDisabledConfig,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 174, y: 174),
      );
      final thirdData = thirdUpdate.data as ArrowData;

      expect(thirdData.startBinding, isNull);
    });

    test('line creation reuses target cache for medium pointer moves', () {
      const target = ElementState(
        id: 'target',
        rect: DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
        rotation: 0,
        opacity: 1,
        zIndex: 0,
        data: RectangleData(),
      );
      final counter = _HitTestCounter();
      final state = _stateWith(
        _CountingDocumentState(elements: const [target], counter: counter),
      );

      const start = DrawPoint(x: 80, y: 80);
      var creating = _creatingState(
        elementId: 'line',
        startPosition: start,
        startResult: _strategy.start(
          data: const LineData(),
          startPosition: start,
        ),
      );

      counter.reset();
      final firstUpdate = _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 209, y: 160),
      );
      creating = _applyUpdate(creating, firstUpdate);
      final callsAfterFirstUpdate = counter.value;

      _updateCreation(
        state: state,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 217, y: 160),
      );
      final callsAfterSecondUpdate = counter.value;

      expect(callsAfterFirstUpdate, greaterThan(0));
      expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
    });

    test(
      'line creation re-evaluates candidate when prior lookup had no match',
      () {
        const target = ElementState(
          id: 'target',
          rect: DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        );
        final counter = _HitTestCounter();
        final state = _stateWith(
          _CountingDocumentState(elements: const [target], counter: counter),
        );

        const start = DrawPoint(x: 80, y: 80);
        var creating = _creatingState(
          elementId: 'line',
          startPosition: start,
          startResult: _strategy.start(
            data: const LineData(),
            startPosition: start,
          ),
        );

        counter.reset();
        final firstUpdate = _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 186, y: 170),
        );
        creating = _applyUpdate(creating, firstUpdate);
        final firstData = firstUpdate.data as LineData;
        final callsAfterFirstUpdate = counter.value;

        final secondUpdate = _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 190, y: 170),
        );
        final secondData = secondUpdate.data as LineData;
        final callsAfterSecondUpdate = counter.value;

        expect(firstData.endBinding, isNull);
        expect(secondData.endBinding, isNotNull);
        expect(callsAfterFirstUpdate, greaterThan(0));
        expect(callsAfterSecondUpdate - callsAfterFirstUpdate, 0);
      },
    );

    test(
      'line creation refreshes empty target cache when entering bind range',
      () {
        const target = ElementState(
          id: 'target',
          rect: DrawRect(minX: 200, minY: 120, maxX: 280, maxY: 220),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        );
        final counter = _HitTestCounter();
        final state = _stateWith(
          _CountingDocumentState(elements: const [target], counter: counter),
        );

        const start = DrawPoint(x: 80, y: 80);
        var creating = _creatingState(
          elementId: 'line',
          startPosition: start,
          startResult: _strategy.start(
            data: const LineData(),
            startPosition: start,
          ),
        );

        counter.reset();
        final firstUpdate = _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 180, y: 170),
        );
        creating = _applyUpdate(creating, firstUpdate);
        final callsAfterFirstUpdate = counter.value;

        final secondUpdate = _updateCreation(
          state: state,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 192, y: 170),
        );
        final callsAfterSecondUpdate = counter.value;
        final secondData = secondUpdate.data as LineData;

        expect(callsAfterFirstUpdate, greaterThan(0));
        expect(callsAfterSecondUpdate - callsAfterFirstUpdate, greaterThan(0));
        expect(secondData.endBinding, isNotNull);
      },
    );
  });
}

class _CountingDocumentState extends DocumentState {
  _CountingDocumentState({required super.elements, required this.counter});

  final _HitTestCounter counter;

  @override
  void visitArrowBindableElementsAtPoint(
    DrawPoint point,
    double tolerance,
    bool Function(ElementState element) visitor, {
    String? excludedElementId,
  }) {
    counter.value++;
    super.visitArrowBindableElementsAtPoint(
      point,
      tolerance,
      visitor,
      excludedElementId: excludedElementId,
    );
  }
}

class _HitTestCounter {
  var value = 0;

  void reset() => value = 0;
}

DrawState _stateWith(DocumentState document) =>
    DrawState(domain: DomainState(document: document));

CreationUpdateResult _updateCreation({
  required DrawState state,
  required CreatingState creatingState,
  required DrawPoint currentPosition,
  DrawConfig? config,
}) => _strategy.update(
  state: state,
  config: config ?? DrawConfig.defaultConfig,
  creatingState: creatingState,
  currentPosition: currentPosition,
  maintainAspectRatio: false,
  createFromCenter: false,
  snappingMode: SnappingMode.none,
);

CreatingState _creatingState({
  required String elementId,
  required DrawPoint startPosition,
  required CreationUpdateResult startResult,
}) => CreatingState(
  element: ElementState(
    id: elementId,
    rect: startResult.rect,
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
