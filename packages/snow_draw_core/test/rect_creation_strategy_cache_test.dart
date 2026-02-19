import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/core/rect_creation_strategy.dart';
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
  group('RectCreationStrategy snap reference caching', () {
    test('reuses cached reference elements across object-snap updates', () {
      const strategy = RectCreationStrategy();
      final state = DrawState(
        domain: DomainState(
          document: DocumentState(
            elements: const [
              ElementState(
                id: 'existing-a',
                rect: DrawRect(minX: 40, minY: 20, maxX: 80, maxY: 60),
                rotation: 0,
                opacity: 1,
                zIndex: 0,
                data: RectangleData(),
              ),
              ElementState(
                id: 'existing-b',
                rect: DrawRect(minX: 120, minY: 30, maxX: 180, maxY: 90),
                rotation: 0,
                opacity: 1,
                zIndex: 1,
                data: RectangleData(),
              ),
            ],
          ),
        ),
      );
      final config = DrawConfig();
      final creating = CreatingState(
        element: const ElementState(
          id: 'creating-rect',
          rect: DrawRect(minX: 10, minY: 10, maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
        startPosition: const DrawPoint(x: 10, y: 10),
        currentRect: const DrawRect(minX: 10, minY: 10, maxX: 10, maxY: 10),
      );

      final firstUpdate = strategy.update(
        state: state,
        config: config,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 70, y: 48),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.object,
      );
      final cachedMode = firstUpdate.creationMode;

      final secondUpdate = strategy.update(
        state: state,
        config: config,
        creatingState: creating.copyWith(
          currentRect: firstUpdate.rect,
          creationMode: cachedMode,
        ),
        currentPosition: const DrawPoint(x: 92, y: 76),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.object,
      );

      expect(identical(secondUpdate.creationMode, cachedMode), isTrue);
    });

    test('refreshes cached references when document elements change', () {
      const strategy = RectCreationStrategy();
      final initialElements = [
        const ElementState(
          id: 'existing-a',
          rect: DrawRect(minX: 40, minY: 20, maxX: 80, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ];
      final initialState = DrawState(
        domain: DomainState(document: DocumentState(elements: initialElements)),
      );
      final creating = CreatingState(
        element: const ElementState(
          id: 'creating-rect',
          rect: DrawRect(minX: 10, minY: 10, maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
        startPosition: const DrawPoint(x: 10, y: 10),
        currentRect: const DrawRect(minX: 10, minY: 10, maxX: 10, maxY: 10),
      );
      final config = DrawConfig();

      final firstUpdate = strategy.update(
        state: initialState,
        config: config,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 70, y: 48),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.object,
      );
      final cachedMode = firstUpdate.creationMode;

      final updatedElements = [
        ...initialElements,
        const ElementState(
          id: 'existing-b',
          rect: DrawRect(minX: 120, minY: 20, maxX: 180, maxY: 60),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        ),
      ];
      final nextState = initialState.copyWith(
        domain: initialState.domain.withElements(updatedElements),
      );
      final secondUpdate = strategy.update(
        state: nextState,
        config: config,
        creatingState: creating.copyWith(
          currentRect: firstUpdate.rect,
          creationMode: cachedMode,
        ),
        currentPosition: const DrawPoint(x: 92, y: 76),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.object,
      );

      expect(identical(secondUpdate.creationMode, cachedMode), isFalse);
    });

    test('keeps plain rect creation mode when object snapping is disabled', () {
      const strategy = RectCreationStrategy();
      final state = DrawState();
      final creating = CreatingState(
        element: const ElementState(
          id: 'creating-rect',
          rect: DrawRect(),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        startPosition: DrawPoint.zero,
        currentRect: const DrawRect(),
      );

      final result = strategy.update(
        state: state,
        config: DrawConfig(),
        creatingState: creating,
        currentPosition: const DrawPoint(x: 20, y: 30),
        maintainAspectRatio: false,
        createFromCenter: false,
        snappingMode: SnappingMode.none,
      );

      expect(result.creationMode, const RectCreationMode());
    });
  });
}
