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
import 'package:snow_draw_engine/draw/reducers/element/style_handler.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:test/test.dart';

void main() {
  group('style_handler arrow binding sync', () {
    test('recomputes bound arrow endpoints after text relayout', () {
      final state = _stateWithBoundArrowToText();
      final beforeText = state.domain.document.getElementById('t1')!;
      final beforeArrowEndX = _arrowEndX(state, 'a1');

      final next = handleUpdateElementsStyle(
        state,
        UpdateElementsStyle(elementIds: ['t1'], fontSize: 72),
        DrawContext.withDefaults(),
      );

      final nextText = next.domain.document.getElementById('t1');
      expect(nextText, isNotNull);
      expect(
        (nextText!.rect.width - beforeText.rect.width).abs(),
        greaterThan(0.5),
      );

      final nextArrow = next.domain.document.getElementById('a1');
      expect(nextArrow, isNotNull);
      final nextData = nextArrow!.data as ArrowData;
      expect(nextData.endBinding?.elementId, 't1');

      final nextArrowEndX = _arrowEndX(next, 'a1');
      expect((nextArrowEndX - beforeArrowEndX).abs(), greaterThan(0.5));
    });
  });
}

DrawState _stateWithBoundArrowToText() {
  const text = ElementState(
    id: 't1',
    rect: DrawRect(minX: 280, minY: 20, maxX: 340, maxY: 40),
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: TextData(text: 'A', autoResize: true),
  );

  final worldPoints = <DrawPoint>[
    const DrawPoint(x: 40, y: 30),
    const DrawPoint(x: 340, y: 30),
  ];
  final arrowRect = DrawRect.fromPointCloud(worldPoints);
  final normalized = ArrowGeometry.normalizePoints(
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

  return DrawState(
    domain: DomainState(document: DocumentState(elements: [text, arrow])),
  );
}

double _arrowEndX(DrawState state, String arrowId) {
  final arrow = state.domain.document.getElementById(arrowId)!;
  final data = arrow.data as ArrowData;
  final points = ArrowGeometry.resolveWorldPoints(
    rect: arrow.rect,
    normalizedPoints: data.points,
  );
  return points.last.x;
}
