import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/actions/actions.dart';
import 'package:snow_draw_core/draw/core/draw_context.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/interaction_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/store/draw_store.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('FinishTextEdit arrow binding history', () {
    test(
      'deleting text via FinishTextEdit clears arrow bindings to that text',
      () async {
        final store = _createStore(initialState: _stateWithActiveTextDelete());
        addTearDown(store.dispose);

        await store.dispatch(
          const FinishTextEdit(elementId: 'text-1', text: '   ', isNew: false),
        );

        expect(store.state.domain.document.getElementById('text-1'), isNull);
        expect(_arrowData(store).startBinding, isNull);
        expect(_arrowData(store).startIsSpecial, isNull);
      },
    );

    test('undo and redo keep arrow binding cleanup reversible', () async {
      final store = _createStore(initialState: _stateWithActiveTextDelete());
      addTearDown(store.dispose);

      final originalData = _arrowData(store);

      await store.dispatch(
        const FinishTextEdit(elementId: 'text-1', text: '   ', isNew: false),
      );

      expect(store.canUndo, isTrue);
      expect(_arrowData(store).startBinding, isNull);
      expect(_arrowData(store).startIsSpecial, isNull);

      await store.dispatch(const Undo());

      expect(store.state.domain.document.getElementById('text-1'), isNotNull);
      expect(_arrowData(store).startBinding, equals(originalData.startBinding));
      expect(
        _arrowData(store).startIsSpecial,
        equals(originalData.startIsSpecial),
      );

      await store.dispatch(const Redo());

      expect(store.state.domain.document.getElementById('text-1'), isNull);
      expect(_arrowData(store).startBinding, isNull);
      expect(_arrowData(store).startIsSpecial, isNull);
    });
  });
}

DefaultDrawStore _createStore({required DrawState initialState}) {
  final registry = DefaultElementRegistry();
  registerBuiltInElements(registry);
  final context = DrawContext.withDefaults(elementRegistry: registry);
  return DefaultDrawStore(context: context, initialState: initialState);
}

DrawState _stateWithActiveTextDelete() {
  const textRect = DrawRect(minX: 10, minY: 10, maxX: 150, maxY: 70);
  const textElement = ElementState(
    id: 'text-1',
    rect: textRect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: TextData(text: 'before'),
  );
  final arrowElement = _arrow(
    id: 'arrow-1',
    points: const [DrawPoint(x: 40, y: 40), DrawPoint(x: 240, y: 40)],
    startBinding: const ArrowBinding(
      elementId: 'text-1',
      anchor: DrawPoint(x: 0.5, y: 0.5),
    ),
    startIsSpecial: true,
  );

  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: [textElement, arrowElement]),
      selection: const SelectionState(selectedIds: {'text-1'}),
    ),
  );

  return base.copyWith(
    application: base.application.copyWith(
      interaction: const TextEditingState(
        elementId: 'text-1',
        draftData: TextData(text: 'before'),
        rect: textRect,
        isNew: false,
        opacity: 1,
        rotation: 0,
      ),
    ),
  );
}

ArrowData _arrowData(DefaultDrawStore store) {
  final element = store.state.domain.document.getElementById('arrow-1');
  expect(element, isNotNull);
  final data = element!.data;
  expect(data, isA<ArrowData>());
  return data as ArrowData;
}

ElementState _arrow({
  required String id,
  required List<DrawPoint> points,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  bool? startIsSpecial,
  bool? endIsSpecial,
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
      startIsSpecial: startIsSpecial,
      endIsSpecial: endIsSpecial,
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
