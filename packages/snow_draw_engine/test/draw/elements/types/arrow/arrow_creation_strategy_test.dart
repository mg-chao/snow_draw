import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
import 'package:test/test.dart';

void main() {
  group('ArrowCreationStrategy core binding integration', () {
    const strategy = ArrowCreationStrategy();

    test('update binds end endpoint to nearby bindable via core', () {
      const startPosition = DrawPoint(x: 20, y: 60);
      const currentPosition = DrawPoint(x: 240, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);
      final creatingState = _startCreatingArrow(
        strategy: strategy,
        startPosition: startPosition,
      );

      final update = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creatingState,
        currentPosition: currentPosition,
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final data = update.data as ArrowData;
      expect(data.endBinding, isNotNull);
      expect(data.endBinding!.elementId, 'rect-target');
    });

    test('update binds start endpoint to nearby bindable via core', () {
      const startPosition = DrawPoint(x: 260, y: 50);
      const currentPosition = DrawPoint(x: 420, y: 50);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);
      final creatingState = _startCreatingArrow(
        strategy: strategy,
        startPosition: startPosition,
      );

      final update = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creatingState,
        currentPosition: currentPosition,
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final data = update.data as ArrowData;
      expect(data.startBinding, isNotNull);
      expect(data.startBinding!.elementId, 'rect-start');
    });

    test('disabling arrow binding keeps endpoints unbound', () {
      const startPosition = DrawPoint(x: 20, y: 60);
      const currentPosition = DrawPoint(x: 240, y: 60);
      final configNoBinding = DrawConfig.defaultConfig.copyWith(
        snap: DrawConfig.defaultConfig.snap.copyWith(enableArrowBinding: false),
      );
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);
      final creatingState = _startCreatingArrow(
        strategy: strategy,
        startPosition: startPosition,
      );

      final update = strategy.update(
        state: state,
        config: configNoBinding,
        creatingState: creatingState,
        currentPosition: currentPosition,
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      final data = update.data as ArrowData;
      expect(data.startBinding, isNull);
      expect(data.endBinding, isNull);
    });

    test('createFromCenter requests inside binding mode via core options', () {
      const startPosition = DrawPoint(x: 20, y: 60);
      const currentPosition = DrawPoint(x: 240, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);
      final creatingState = _startCreatingArrow(
        strategy: strategy,
        startPosition: startPosition,
      );

      final update = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creatingState,
        currentPosition: currentPosition,
        maintainAspectRatio: false,
        createFromCenter: true,
        snappingMode: SnappingMode.none,
      );

      final data = update.data as ArrowData;
      expect(data.endBinding, isNotNull);
      expect(data.endBinding!.mode, ArrowBindingMode.inside);
    });

    test('finish preserves inside binding selected during creation', () {
      const startPosition = DrawPoint(x: 20, y: 60);
      const currentPosition = DrawPoint(x: 240, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);
      final creatingState = _startCreatingArrow(
        strategy: strategy,
        startPosition: startPosition,
      );
      final update = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creatingState,
        currentPosition: currentPosition,
        maintainAspectRatio: false,
        createFromCenter: true,
        snappingMode: SnappingMode.none,
      );
      final nextCreating = creatingState.copyWith(
        element: creatingState.element.copyWith(
          rect: update.rect,
          data: update.data,
        ),
        currentRect: update.rect,
        creationMode: update.creationMode,
      );

      final finish = strategy.finish(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: nextCreating,
      );
      final finishedData = finish.data as ArrowData;

      expect(finish.shouldCommit, isTrue);
      expect(finishedData.endBinding, isNotNull);
      expect(finishedData.endBinding!.mode, ArrowBindingMode.inside);
    });
  });
}

CreatingState _startCreatingArrow({
  required ArrowCreationStrategy strategy,
  required DrawPoint startPosition,
}) {
  final start = strategy.start(
    data: const ArrowData(),
    startPosition: startPosition,
  );
  return CreatingState(
    element: ElementState(
      id: 'draft-arrow',
      rect: start.rect,
      rotation: 0,
      opacity: 1,
      zIndex: 10,
      data: start.data,
    ),
    startPosition: startPosition,
    currentRect: start.rect,
    creationMode: start.creationMode,
  );
}

DrawState _stateWithElements(List<ElementState> elements) => DrawState(
  domain: DomainState(document: DocumentState(elements: elements)),
);

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const RectangleData(),
);
