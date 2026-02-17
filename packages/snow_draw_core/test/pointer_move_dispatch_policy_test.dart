import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_target_cache.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_creation_strategy.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/elements/types/line/line_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_context.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/ui/canvas/pointer_move_dispatch_policy.dart';

void main() {
  group('PointerMoveDispatchPolicy.shouldCoalesce', () {
    test('line creation bypasses frame coalescing', () {
      final interaction = CreatingState(
        element: _lineElement(id: 'line'),
        startPosition: const DrawPoint(x: 10, y: 10),
        currentRect: const DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
        creationMode: const PointCreationMode(
          fixedPoints: [DrawPoint(x: 10, y: 10)],
          currentPoint: DrawPoint(x: 50, y: 50),
        ),
      );

      expect(
        PointerMoveDispatchPolicy.shouldCoalesce(
          interaction: interaction,
          currentToolTypeId: LineData.typeIdToken,
          isShiftPressed: false,
        ),
        isFalse,
      );
    });

    test('line arrow-point edit bypasses frame coalescing', () {
      final baseElement = _lineElement(id: 'line');
      final context = ArrowPointEditContext(
        startPosition: const DrawPoint(x: 20, y: 20),
        startBounds: const DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
        selectedIdsAtStart: const {'line'},
        selectionVersion: 1,
        elementsVersion: 1,
        elementId: 'line',
        elementRect: baseElement.rect,
        rotation: 0,
        initialPoints: const [DrawPoint(x: 10, y: 10), DrawPoint(x: 50, y: 50)],
        initialFixedSegments: const [],
        arrowType: ArrowType.curved,
        pointKind: ArrowPointKind.turning,
        pointIndex: 0,
        dragOffset: DrawPoint.zero,
        baseElement: baseElement,
        elementSpace: null,
        releaseFixedSegment: false,
        deletePointOnStart: false,
        bindingTargetCache: ArrowBindingTargetCache(),
        startArrowhead: ArrowheadStyle.none,
        endArrowhead: ArrowheadStyle.none,
        initialStartBinding: null,
        initialEndBinding: null,
        hasBindableTargets: false,
        isLineElement: true,
      );
      final interaction = EditingState(
        operationId: EditOperationIds.arrowPoint,
        sessionId: 'edit_1',
        context: context,
        currentTransform: const ArrowPointTransform(
          currentPosition: DrawPoint(x: 20, y: 20),
          points: [DrawPoint(x: 10, y: 10), DrawPoint(x: 50, y: 50)],
        ),
      );

      expect(
        PointerMoveDispatchPolicy.shouldCoalesce(
          interaction: interaction,
          currentToolTypeId: LineData.typeIdToken,
          isShiftPressed: false,
        ),
        isFalse,
      );
    });

    test('rectangle creation keeps frame coalescing', () {
      final interaction = CreatingState(
        element: const ElementState(
          id: 'rect',
          rect: DrawRect(maxX: 1, maxY: 1),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        startPosition: const DrawPoint(x: 10, y: 10),
        currentRect: const DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
      );

      expect(
        PointerMoveDispatchPolicy.shouldCoalesce(
          interaction: interaction,
          currentToolTypeId: RectangleData.typeIdToken,
          isShiftPressed: false,
        ),
        isTrue,
      );
    });

    test(
      'serial-number creation bypasses frame coalescing in low-latency mode',
      () {
        final interaction = CreatingState(
          element: const ElementState(
            id: 'serial',
            rect: DrawRect(maxX: 1, maxY: 1),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: SerialNumberData(),
          ),
          startPosition: const DrawPoint(x: 10, y: 10),
          currentRect: const DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
        );

        expect(
          PointerMoveDispatchPolicy.shouldCoalesce(
            interaction: interaction,
            currentToolTypeId: SerialNumberData.typeIdToken,
            isShiftPressed: false,
            isLowLatencySerialInteraction: true,
          ),
          isFalse,
        );
      },
    );

    test(
      'single serial-number edit bypasses frame coalescing in low-latency mode',
      () {
        const interaction = EditingState(
          operationId: EditOperationIds.move,
          sessionId: 'edit_serial',
          context: _TestEditContext(
            startPosition: DrawPoint(x: 10, y: 10),
            startBounds: DrawRect(minX: 8, minY: 8, maxX: 40, maxY: 40),
            selectedIdsAtStart: {'serial'},
            selectionVersion: 1,
            elementsVersion: 1,
          ),
          currentTransform: MoveTransform.zero,
        );

        expect(
          PointerMoveDispatchPolicy.shouldCoalesce(
            interaction: interaction,
            currentToolTypeId: SerialNumberData.typeIdToken,
            isShiftPressed: false,
            isLowLatencySerialInteraction: true,
          ),
          isFalse,
        );
      },
    );
  });

  group('PointerMoveDispatchPolicy.shouldBatchFreeDrawSamples', () {
    test('active free-draw tool batches samples without shift', () {
      expect(
        PointerMoveDispatchPolicy.shouldBatchFreeDrawSamples(
          interaction: const IdleState(),
          currentToolTypeId: FreeDrawData.typeIdToken,
          isShiftPressed: false,
        ),
        isTrue,
      );
    });

    test('shift disables free-draw sample batching', () {
      expect(
        PointerMoveDispatchPolicy.shouldBatchFreeDrawSamples(
          interaction: const IdleState(),
          currentToolTypeId: FreeDrawData.typeIdToken,
          isShiftPressed: true,
        ),
        isFalse,
      );
    });

    test(
      'free-draw creation batches samples even when tool already changed',
      () {
        final interaction = CreatingState(
          element: const ElementState(
            id: 'fd',
            rect: DrawRect(maxX: 1, maxY: 1),
            rotation: 0,
            opacity: 1,
            zIndex: 0,
            data: FreeDrawData(),
          ),
          startPosition: const DrawPoint(x: 10, y: 10),
          currentRect: const DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
          creationMode: const FreeDrawCreationMode(),
        );

        expect(
          PointerMoveDispatchPolicy.shouldBatchFreeDrawSamples(
            interaction: interaction,
            currentToolTypeId: null,
            isShiftPressed: false,
          ),
          isTrue,
        );
      },
    );
  });
}

ElementState _lineElement({required String id}) => ElementState(
  id: id,
  rect: const DrawRect(minX: 10, minY: 10, maxX: 50, maxY: 50),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const LineData(),
);

class _TestEditContext extends EditContext {
  const _TestEditContext({
    required super.startPosition,
    required super.startBounds,
    required super.selectedIdsAtStart,
    required super.selectionVersion,
    required super.elementsVersion,
  });
}
