import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/move/move_operation.dart';
import 'package:snow_draw_core/draw/edit/resize/resize_operation.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/resize_mode.dart';

void main() {
  group('Edit system snapshot consistency', () {
    test(
      'move update stays stable when selected geometry drifts mid-session',
      () {
        final selected = _rectangle(
          id: 'selected',
          rect: const DrawRect(maxX: 10, maxY: 10),
        );
        final baseState = _stateWith(
          [selected],
          selectedIds: const {'selected'},
        );

        const operation = MoveOperation();
        const startPosition = DrawPoint(x: 5, y: 5);
        final context = operation.createContext(
          state: baseState,
          position: startPosition,
          params: const MoveOperationParams(),
        );
        final initialTransform = operation.initialTransform(
          state: baseState,
          context: context,
          startPosition: startPosition,
        );
        final config = DrawConfig.defaultConfig.copyWith(
          grid: const GridConfig(enabled: true, size: 10),
        );

        final baseline = operation.update(
          state: baseState,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 11, y: 5),
          modifiers: const EditModifiers(),
          config: config,
        );

        final driftedSelected = selected.copyWith(
          rect: const DrawRect(minX: 103, maxX: 113, maxY: 10),
        );
        final driftedState = _stateWith(
          [driftedSelected],
          selectedIds: const {'selected'},
          elementsVersion: baseState.domain.document.elementsVersion,
        );

        final drifted = operation.update(
          state: driftedState,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 11, y: 5),
          modifiers: const EditModifiers(),
          config: config,
        );

        final baselineTransform = baseline.transform as MoveTransform;
        final driftedTransform = drifted.transform as MoveTransform;
        expect(baselineTransform.dx, 10);
        expect(driftedTransform, equals(baselineTransform));
      },
    );

    test('move object snapping uses start-of-session references', () {
      final selected = _rectangle(
        id: 'selected',
        rect: const DrawRect(maxX: 10, maxY: 10),
      );
      final reference = _rectangle(
        id: 'reference',
        rect: const DrawRect(minX: 30, maxX: 40, maxY: 10),
      );
      final baseState = _stateWith(
        [selected, reference],
        selectedIds: const {'selected'},
      );

      const operation = MoveOperation();
      const startPosition = DrawPoint(x: 5, y: 5);
      final context = operation.createContext(
        state: baseState,
        position: startPosition,
        params: const MoveOperationParams(),
      );
      final initialTransform = operation.initialTransform(
        state: baseState,
        context: context,
        startPosition: startPosition,
      );
      final config = DrawConfig.defaultConfig.copyWith(
        snap: const SnapConfig(
          enabled: true,
          distance: 12,
          enableGapSnaps: false,
        ),
      );

      final baseline = operation.update(
        state: baseState,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 24, y: 5),
        modifiers: const EditModifiers(),
        config: config,
      );

      final movedReference = reference.copyWith(
        rect: const DrawRect(minX: 80, maxX: 90, maxY: 10),
      );
      final driftedState = _stateWith(
        [selected, movedReference],
        selectedIds: const {'selected'},
        elementsVersion: baseState.domain.document.elementsVersion,
      );

      final drifted = operation.update(
        state: driftedState,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 24, y: 5),
        modifiers: const EditModifiers(),
        config: config,
      );

      final baselineTransform = baseline.transform as MoveTransform;
      final driftedTransform = drifted.transform as MoveTransform;
      expect(baselineTransform.dx, isNot(19));
      expect(driftedTransform, equals(baselineTransform));
    });

    test('resize object snapping uses start-of-session references', () {
      final selected = _rectangle(
        id: 'selected',
        rect: const DrawRect(maxX: 10, maxY: 10),
      );
      final reference = _rectangle(
        id: 'reference',
        rect: const DrawRect(minX: 30, maxX: 40, maxY: 10),
      );
      final baseState = _stateWith(
        [selected, reference],
        selectedIds: const {'selected'},
      );

      const operation = ResizeOperation();
      const handlePosition = DrawPoint(x: 10, y: 5);
      final context = operation.createContext(
        state: baseState,
        position: handlePosition,
        params: const ResizeOperationParams(
          resizeMode: ResizeMode.right,
          selectionPadding: 0,
        ),
      );
      final initialTransform = operation.initialTransform(
        state: baseState,
        context: context,
        startPosition: handlePosition,
      );
      final config = DrawConfig.defaultConfig.copyWith(
        snap: const SnapConfig(
          enabled: true,
          distance: 12,
          enableGapSnaps: false,
        ),
      );

      final baseline = operation.update(
        state: baseState,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 23, y: 5),
        modifiers: const EditModifiers(),
        config: config,
      );
      final baselineTransform = baseline.transform as ResizeTransform;
      final baselineBounds = baselineTransform.newSelectionBounds;
      expect(baselineBounds, isNotNull);

      final movedReference = reference.copyWith(
        rect: const DrawRect(minX: 80, maxX: 90, maxY: 10),
      );
      final driftedState = _stateWith(
        [selected, movedReference],
        selectedIds: const {'selected'},
        elementsVersion: baseState.domain.document.elementsVersion,
      );

      final drifted = operation.update(
        state: driftedState,
        context: context,
        transform: initialTransform,
        currentPosition: const DrawPoint(x: 23, y: 5),
        modifiers: const EditModifiers(),
        config: config,
      );
      final driftedTransform = drifted.transform as ResizeTransform;

      expect(driftedTransform.newSelectionBounds, equals(baselineBounds));
    });

    test(
      'resize serial-number aspect ratio lock uses start-of-session selection',
      () {
        const selected = ElementState(
          id: 'selected',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: SerialNumberData(),
        );
        final baseState = _stateWith(
          [selected],
          selectedIds: const {'selected'},
        );

        const operation = ResizeOperation();
        const handlePosition = DrawPoint(x: 10, y: 5);
        final context = operation.createContext(
          state: baseState,
          position: handlePosition,
          params: const ResizeOperationParams(
            resizeMode: ResizeMode.right,
            selectionPadding: 0,
          ),
        );
        final initialTransform = operation.initialTransform(
          state: baseState,
          context: context,
          startPosition: handlePosition,
        );

        final baseline = operation.update(
          state: baseState,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 20, y: 5),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final baselineTransform = baseline.transform as ResizeTransform;
        final baselineBounds = baselineTransform.newSelectionBounds;
        expect(baselineBounds, isNotNull);
        expect(baselineBounds!.width, baselineBounds.height);
        expect(baselineBounds.height, isNot(10));

        final driftedSelected = selected.copyWith(data: const RectangleData());
        final driftedState = _stateWith(
          [driftedSelected],
          selectedIds: const {'selected'},
          elementsVersion: baseState.domain.document.elementsVersion,
        );

        final drifted = operation.update(
          state: driftedState,
          context: context,
          transform: initialTransform,
          currentPosition: const DrawPoint(x: 20, y: 5),
          modifiers: const EditModifiers(),
          config: DrawConfig.defaultConfig,
        );
        final driftedTransform = drifted.transform as ResizeTransform;

        expect(driftedTransform.newSelectionBounds, equals(baselineBounds));
      },
    );
  });
}

ElementState _rectangle({required String id, required DrawRect rect}) =>
    ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

DrawState _stateWith(
  List<ElementState> elements, {
  required Set<String> selectedIds,
  int? elementsVersion,
}) => DrawState(
  domain: DomainState(
    document: elementsVersion == null
        ? DocumentState(elements: elements)
        : DocumentState(elements: elements, elementsVersion: elementsVersion),
    selection: SelectionState(selectedIds: selectedIds),
  ),
);
