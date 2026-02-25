import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/core/element_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_creation_strategy.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
import 'package:test/test.dart';

void main() {
  group('Creation strategy type guards', () {
    test('ArrowCreationStrategy.start throws for non-arrow data', () {
      const strategy = ArrowCreationStrategy();

      expect(
        () => strategy.start(
          data: const RectangleData(),
          startPosition: DrawPoint.zero,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('FreeDrawCreationStrategy.update throws for non-free-draw data', () {
      const strategy = FreeDrawCreationStrategy();

      expect(
        () => strategy.update(
          state: DrawState(),
          config: DrawConfig(),
          creatingState: _creatingStateWithData(const RectangleData()),
          currentPosition: const DrawPoint(x: 20, y: 20),
          maintainAspectRatio: false,
          createFromCenter: false,
          snappingMode: SnappingMode.none,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test(
      'SerialNumberCreationStrategy.update throws for non-serial-number data',
      () {
        const strategy = SerialNumberCreationStrategy();

        expect(
          () => strategy.update(
            state: DrawState(),
            config: DrawConfig(),
            creatingState: _creatingStateWithData(const RectangleData()),
            currentPosition: const DrawPoint(x: 30, y: 30),
            maintainAspectRatio: false,
            createFromCenter: false,
            snappingMode: SnappingMode.none,
          ),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}

CreatingState _creatingStateWithData(ElementData data) {
  const rect = DrawRect(maxX: 50, maxY: 50);
  return CreatingState(
    element: ElementState(
      id: 'creation-test-element',
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: data,
    ),
    startPosition: DrawPoint.zero,
    currentRect: rect,
  );
}
