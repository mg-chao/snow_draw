import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_operation_id.dart';

void main() {
  group('History finish-edit binding regression', () {
    test(
      'undo and redo keep bound arrow geometry consistent after move edit',
      () async {
        final initialTarget = _rectangle(
          id: 'target',
          rect: const DrawRect(maxX: 40, maxY: 40),
        );
        final initialArrow = _arrow(
          id: 'arrow',
          points: const [DrawPoint(x: 20, y: 20), DrawPoint(x: 120, y: 20)],
          startBinding: const ArrowBinding(
            elementId: 'target',
            anchor: DrawPoint(x: 0.5, y: 0.5),
          ),
        );
        final store = _createStore(
          initialState: DrawState(
            domain: DomainState(
              document: DocumentState(elements: [initialTarget, initialArrow]),
              selection: const SelectionState(selectedIds: {'target'}),
            ),
          ),
        );
        addTearDown(store.dispose);

        await store.dispatch(
          const StartEdit(
            operationId: EditOperationIds.move,
            position: DrawPoint(x: 20, y: 20),
            params: MoveOperationParams(),
          ),
        );
        await store.dispatch(
          const UpdateEdit(currentPosition: DrawPoint(x: 50, y: 20)),
        );
        await store.dispatch(const FinishEdit());

        final movedTarget = store.state.domain.document.getElementById(
          'target',
        );
        final movedArrow = store.state.domain.document.getElementById('arrow');
        expect(movedTarget, isNotNull);
        expect(movedArrow, isNotNull);
        expect(movedTarget, isNot(equals(initialTarget)));
        expect(movedArrow, isNot(equals(initialArrow)));

        await store.dispatch(const Undo());

        final undoTarget = store.state.domain.document.getElementById('target');
        final undoArrow = store.state.domain.document.getElementById('arrow');
        expect(undoTarget, equals(initialTarget));
        expect(undoArrow, equals(initialArrow));

        await store.dispatch(const Redo());

        final redoTarget = store.state.domain.document.getElementById('target');
        final redoArrow = store.state.domain.document.getElementById('arrow');
        expect(redoTarget, equals(movedTarget));
        expect(redoArrow, equals(movedArrow));
      },
    );
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
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

ElementState _arrow({
  required String id,
  required List<DrawPoint> points,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
}) {
  final rect = _rectForPoints(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );

  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: ArrowData(
      points: normalized,
      startBinding: startBinding,
      endBinding: endBinding,
    ),
  );
}

DrawRect _rectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var minY = points.first.y;
  var maxX = points.first.x;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    if (point.x < minX) {
      minX = point.x;
    }
    if (point.y < minY) {
      minY = point.y;
    }
    if (point.x > maxX) {
      maxX = point.x;
    }
    if (point.y > maxY) {
      maxY = point.y;
    }
  }

  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
