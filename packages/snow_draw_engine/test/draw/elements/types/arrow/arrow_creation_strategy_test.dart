import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/core/element_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_engine/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/application_state.dart';
import 'package:snow_draw_engine/draw/models/camera_state.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/models/view_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
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

    test(
      'new-arrow start binding defaults to orbit when started outside shape',
      () {
        const startPosition = DrawPoint(x: 218, y: 60);
        const currentPosition = DrawPoint(x: 440, y: 60);
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
        expect(data.startBinding!.mode, ArrowBindingMode.orbit);
      },
    );

    test('initial start binding is deterministic regardless of '
        'first drag distance', () {
      const startPosition = DrawPoint(x: 218, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);

      ArrowBinding resolveStartBindingForEndPoint(DrawPoint currentPosition) {
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
        return data.startBinding!;
      }

      final nearDragStartBinding = resolveStartBindingForEndPoint(
        const DrawPoint(x: 240, y: 60),
      );
      final farDragStartBinding = resolveStartBindingForEndPoint(
        const DrawPoint(x: 620, y: 90),
      );

      expect(nearDragStartBinding, equals(farDragStartBinding));
    });

    test('update binds endpoint to nearby highlight ellipse via core', () {
      const startPosition = DrawPoint(x: 20, y: 140);
      const currentPosition = DrawPoint(x: 220, y: 140);
      final state = _stateWithElements(<ElementState>[
        _highlightElement(
          id: 'highlight-target',
          rect: const DrawRect(minX: 180, minY: 80, maxX: 300, maxY: 220),
          zIndex: 2,
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
      expect(data.endBinding!.elementId, 'highlight-target');
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

    test('finish keeps start inside binding after alt-key release', () {
      const startPosition = DrawPoint(x: 260, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-start',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
        _rectangleElement(
          id: 'rect-end',
          rect: const DrawRect(minX: 420, maxX: 520, maxY: 120),
          zIndex: 2,
        ),
      ]);
      final creatingState = _startCreatingArrow(
        strategy: strategy,
        startPosition: startPosition,
      );

      final insideStartUpdate = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: creatingState,
        currentPosition: const DrawPoint(x: 340, y: 60),
        maintainAspectRatio: false,
        createFromCenter: true,
        snappingMode: SnappingMode.none,
      );
      final insideStartData = insideStartUpdate.data as ArrowData;
      expect(insideStartData.startBinding, isNotNull);
      expect(insideStartData.startBinding!.mode, ArrowBindingMode.inside);

      final insideStartCreating = creatingState.copyWith(
        element: creatingState.element.copyWith(
          rect: insideStartUpdate.rect,
          data: insideStartUpdate.data,
        ),
        currentRect: insideStartUpdate.rect,
        creationMode: insideStartUpdate.creationMode,
      );
      final endUpdate = strategy.update(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: insideStartCreating,
        currentPosition: const DrawPoint(x: 440, y: 60),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );
      final endUpdateData = endUpdate.data as ArrowData;
      expect(endUpdateData.startBinding, isNotNull);
      expect(endUpdateData.startBinding!.mode, ArrowBindingMode.inside);

      final finish = strategy.finish(
        state: state,
        config: DrawConfig.defaultConfig,
        creatingState: insideStartCreating.copyWith(
          element: insideStartCreating.element.copyWith(
            rect: endUpdate.rect,
            data: endUpdate.data,
          ),
          currentRect: endUpdate.rect,
          creationMode: endUpdate.creationMode,
        ),
      );
      final finishedData = finish.data as ArrowData;

      expect(finish.shouldCommit, isTrue);
      expect(finishedData.startBinding, isNotNull);
      expect(finishedData.startBinding!.mode, ArrowBindingMode.inside);
    });

    test('update honors zoom-aware core binding distance', () {
      const startPosition = DrawPoint(x: 20, y: 60);
      const currentPosition = DrawPoint(x: 82, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 100, maxX: 220, maxY: 120),
          zIndex: 1,
        ),
      ], zoom: 0.5);
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

    test('update line-like data binds endpoint via core drag pipeline', () {
      const startPosition = DrawPoint(x: 20, y: 60);
      const currentPosition = DrawPoint(x: 240, y: 60);
      final state = _stateWithElements(<ElementState>[
        _rectangleElement(
          id: 'rect-target',
          rect: const DrawRect(minX: 220, maxX: 320, maxY: 120),
          zIndex: 1,
        ),
      ]);
      final creatingState = _startCreating(
        strategy: strategy,
        startPosition: startPosition,
        data: const LineData(),
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

      final data = update.data as LineData;
      expect(data.endBinding, isNotNull);
      expect(data.endBinding!.elementId, 'rect-target');
    });
  });
}

CreatingState _startCreatingArrow({
  required ArrowCreationStrategy strategy,
  required DrawPoint startPosition,
}) => _startCreating(
  strategy: strategy,
  startPosition: startPosition,
  data: const ArrowData(),
);

CreatingState _startCreating({
  required ArrowCreationStrategy strategy,
  required DrawPoint startPosition,
  required ElementData data,
}) {
  final start = strategy.start(data: data, startPosition: startPosition);
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

DrawState _stateWithElements(List<ElementState> elements, {double zoom = 1}) =>
    DrawState(
      domain: DomainState(document: DocumentState(elements: elements)),
      application: ApplicationState.initial(
        view: ViewState(camera: CameraState(zoom: zoom)),
      ),
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

ElementState _highlightElement({
  required String id,
  required DrawRect rect,
  required int zIndex,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: zIndex,
  data: const HighlightData(shape: HighlightShape.ellipse),
);
