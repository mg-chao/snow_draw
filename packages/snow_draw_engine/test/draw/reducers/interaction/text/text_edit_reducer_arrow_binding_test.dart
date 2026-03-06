import 'package:snow_draw_engine/draw/actions/draw_actions.dart';
import 'package:snow_draw_engine/draw/core/draw_context.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/text/text_data.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/interaction_state.dart';
import 'package:snow_draw_engine/draw/reducers/interaction/text/text_edit_reducer.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('text_edit_reducer arrow binding sync', () {
    test('finish text edit recomputes endpoints for bound arrows', () {
      final state = _stateWithTextEditing();
      final beforeArrowEndX = _arrowEndX(state, 'a1');

      final next = const TextEditReducer().reduce(
        state,
        const FinishTextEdit(
          elementId: 't1',
          text: 'This text is long enough to expand auto-resize width',
          isNew: false,
        ),
        DrawContext.withDefaults(),
      );

      final nextText = next!.domain.document.getElementById('t1');
      expect(nextText, isNotNull);
      final nextArrow = next.domain.document.getElementById('a1');
      expect(nextArrow, isNotNull);
      final nextData = nextArrow!.data as ArrowData;
      expect(nextData.endBinding?.elementId, 't1');
      expect(
        (_arrowEndX(next, 'a1') - beforeArrowEndX).abs(),
        greaterThan(0.5),
      );
    });

    test('deleting text via finish clears dependent arrow binding', () {
      final state = _stateWithTextEditing();

      final next = const TextEditReducer().reduce(
        state,
        const FinishTextEdit(elementId: 't1', text: '   ', isNew: false),
        DrawContext.withDefaults(),
      );

      final document = next!.domain.document;
      expect(document.getElementById('t1'), isNull);

      final nextArrow = document.getElementById('a1');
      expect(nextArrow, isNotNull);
      final nextData = nextArrow!.data as ArrowData;
      expect(nextData.endBinding, isNull);
    });
  });
}

DrawState _stateWithTextEditing() {
  const textData = TextData(text: 'A', autoResize: true);
  const textElement = ElementState(
    id: 't1',
    rect: DrawRect(minX: 280, minY: 20, maxX: 340, maxY: 40),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: textData,
  );

  final worldPoints = <DrawPoint>[
    const DrawPoint(x: 40, y: 30),
    const DrawPoint(x: 340, y: 30),
  ];
  final arrowRect = DrawRect.fromPointCloud(worldPoints);
  final normalized = ConnectorGeometry.normalizePoints(
    worldPoints: worldPoints,
    rect: arrowRect,
  );
  final arrow = ElementState(
    id: 'a1',
    rect: arrowRect,
    rotation: 0,
    opacity: 1,
    zIndex: 1,
    data: ArrowData(
      points: normalized,
      endBinding: const ArrowBinding(
        elementId: 't1',
        anchor: DrawPoint(x: 1, y: 0.5),
      ),
    ),
  );

  final base = DrawState(
    domain: DomainState(
      document: DocumentState(elements: [textElement, arrow]),
    ),
  );
  return base.copyWith(
    application: base.application.copyWith(
      interaction: TextEditingState(
        elementId: 't1',
        draftData: textData,
        rect: textElement.rect,
        isNew: false,
        opacity: 1,
        rotation: 0,
      ),
    ),
  );
}

double _arrowEndX(DrawState state, String arrowId) {
  final arrow = state.domain.document.getElementById(arrowId)!;
  final data = arrow.data as ArrowData;
  final points = ConnectorGeometry.resolveWorldPoints(
    rect: arrow.rect,
    normalizedPoints: data.points,
  );
  return points.last.x;
}
