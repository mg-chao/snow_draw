import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
import 'package:test/test.dart';

void main() {
  group('SerialNumberCreationStrategy layout caching', () {
    test(
      'reuses cached creation mode when serial layout inputs are unchanged',
      () {
        const strategy = SerialNumberCreationStrategy();
        final state = DrawState();
        final config = DrawConfig();
        const data = SerialNumberData(number: 12);
        const startPosition = DrawPoint(x: 40, y: 40);

        final startResult = strategy.start(
          data: data,
          startPosition: startPosition,
        );
        final creating = CreatingState(
          element: ElementState(
            id: 'serial-creating',
            rect: const DrawRect(minX: 40, minY: 40, maxX: 40, maxY: 40),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: startResult.data,
          ),
          startPosition: startPosition,
          currentRect: startResult.rect,
          creationMode: startResult.creationMode,
        );

        final firstUpdate = strategy.update(
          state: state,
          config: config,
          creatingState: creating,
          currentPosition: const DrawPoint(x: 60, y: 60),
          maintainAspectRatio: true,
          createFromCenter: true,
          snappingMode: SnappingMode.none,
        );

        final secondUpdate = strategy.update(
          state: state,
          config: config,
          creatingState: creating.copyWith(
            currentRect: firstUpdate.rect,
            creationMode: firstUpdate.creationMode,
          ),
          currentPosition: const DrawPoint(x: 80, y: 80),
          maintainAspectRatio: true,
          createFromCenter: true,
          snappingMode: SnappingMode.none,
        );

        expect(
          identical(secondUpdate.creationMode, firstUpdate.creationMode),
          isTrue,
        );
      },
    );

    test('refreshes cached creation mode when serial font size changes', () {
      const strategy = SerialNumberCreationStrategy();
      final state = DrawState();
      final config = DrawConfig();
      const startPosition = DrawPoint(x: 40, y: 40);

      final startResult = strategy.start(
        data: const SerialNumberData(number: 12),
        startPosition: startPosition,
      );
      final creating = CreatingState(
        element: ElementState(
          id: 'serial-creating',
          rect: const DrawRect(minX: 40, minY: 40, maxX: 40, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: startResult.data,
        ),
        startPosition: startPosition,
        currentRect: startResult.rect,
        creationMode: startResult.creationMode,
      );

      final firstUpdate = strategy.update(
        state: state,
        config: config,
        creatingState: creating,
        currentPosition: const DrawPoint(x: 60, y: 60),
        maintainAspectRatio: true,
        createFromCenter: true,
        snappingMode: SnappingMode.none,
      );

      const changedData = SerialNumberData(number: 12, fontSize: 24);
      final secondUpdate = strategy.update(
        state: state,
        config: config,
        creatingState: creating.copyWith(
          element: creating.element.copyWith(data: changedData),
          currentRect: firstUpdate.rect,
          creationMode: firstUpdate.creationMode,
        ),
        currentPosition: const DrawPoint(x: 80, y: 80),
        maintainAspectRatio: true,
        createFromCenter: true,
        snappingMode: SnappingMode.none,
      );

      expect(
        identical(secondUpdate.creationMode, firstUpdate.creationMode),
        isFalse,
      );
    });
  });
}
