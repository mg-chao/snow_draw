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
import 'package:snow_draw_engine/draw/types/element_style.dart';
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

    test('normalizes elbow path when arrowhead style changes', () {
      final state = _stateWithNonOrthogonalElbowArrow();
      final beforeArrow = state.domain.document.getElementById('ea1');
      expect(beforeArrow, isNotNull);
      final beforeData = beforeArrow!.data as ArrowData;
      final beforePoints = _arrowWorldPoints(beforeArrow);
      expect(_isOrthogonalPath(beforePoints), isFalse);

      final next = handleUpdateElementsStyle(
        state,
        UpdateElementsStyle(
          elementIds: const ['ea1'],
          endArrowhead: ArrowheadStyle.standard,
        ),
        DrawContext.withDefaults(),
      );

      final nextArrow = next.domain.document.getElementById('ea1');
      expect(nextArrow, isNotNull);
      final nextData = nextArrow!.data as ArrowData;
      final nextPoints = _arrowWorldPoints(nextArrow);

      expect(beforeData.arrowType, ArrowType.elbow);
      expect(beforeData.endArrowhead, ArrowheadStyle.none);
      expect(nextData.arrowType, ArrowType.elbow);
      expect(nextData.endArrowhead, ArrowheadStyle.standard);
      expect(_pathDelta(beforePoints, nextPoints), greaterThan(0));
      expect(_isOrthogonalPath(nextPoints), isTrue);
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

DrawState _stateWithNonOrthogonalElbowArrow() {
  final worldPoints = <DrawPoint>[
    const DrawPoint(x: 100, y: 100),
    const DrawPoint(x: 220, y: 160),
    const DrawPoint(x: 320, y: 220),
  ];
  final rect = DrawRect.fromPointCloud(worldPoints);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: worldPoints,
    rect: rect,
  );
  final arrow = ElementState(
    id: 'ea1',
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: ArrowData(
      points: normalized,
      arrowType: ArrowType.elbow,
      endArrowhead: ArrowheadStyle.none,
    ),
  );

  return DrawState(
    domain: DomainState(document: DocumentState(elements: [arrow])),
  );
}

double _arrowEndX(DrawState state, String arrowId) {
  final arrow = state.domain.document.getElementById(arrowId)!;
  final points = _arrowWorldPoints(arrow);
  return points.last.x;
}

List<DrawPoint> _arrowWorldPoints(ElementState arrow) {
  final data = arrow.data as ArrowData;
  return ArrowGeometry.resolveWorldPoints(
    rect: arrow.rect,
    normalizedPoints: data.points,
  );
}

bool _isOrthogonalPath(List<DrawPoint> points) {
  for (var index = 1; index < points.length; index++) {
    final prev = points[index - 1];
    final next = points[index];
    final sameX = (prev.x - next.x).abs() <= 1e-6;
    final sameY = (prev.y - next.y).abs() <= 1e-6;
    if (!sameX && !sameY) {
      return false;
    }
  }
  return true;
}

double _pathDelta(List<DrawPoint> before, List<DrawPoint> after) {
  if (before.length != after.length) {
    return double.infinity;
  }
  var delta = 0.0;
  for (var index = 0; index < before.length; index++) {
    delta += (before[index].x - after[index].x).abs();
    delta += (before[index].y - after[index].y).abs();
  }
  return delta;
}
