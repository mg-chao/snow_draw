import 'package:snow_draw_engine/draw/edit/apply/edit_apply.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_engine/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/types/edit_context.dart';
import 'package:snow_draw_engine/draw/types/element_geometry.dart';
import 'package:snow_draw_engine/draw/types/element_style.dart';
import 'package:snow_draw_engine/draw/types/resize_mode.dart';
import 'package:test/test.dart';

void main() {
  group('EditApply elbow resize core integration', () {
    test('horizontal flip mirrors binding anchors and fixed segments', () {
      final arrow = _elbowArrowElement(
        id: 'arrow-flip-x',
        points: const <DrawPoint>[
          DrawPoint(x: 100, y: 150),
          DrawPoint(x: 300, y: 150),
          DrawPoint(x: 300, y: 200),
        ],
        startBinding: const ArrowBinding(
          elementId: 'start-target',
          anchor: DrawPoint(x: 0.25, y: 0.7),
        ),
        endBinding: const ArrowBinding(
          elementId: 'end-target',
          anchor: DrawPoint(x: 0.9, y: 0.3),
        ),
        fixedSegments: const <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 1,
            start: DrawPoint(x: 100, y: 150),
            end: DrawPoint(x: 300, y: 150),
          ),
          ElbowFixedSegment(
            index: 2,
            start: DrawPoint(x: 300, y: 150),
            end: DrawPoint(x: 300, y: 200),
          ),
        ],
      );

      final resized = _applySingleArrowResize(
        element: arrow,
        scaleX: -1,
        scaleY: 1,
        anchor: DrawPoint(x: arrow.rect.minX, y: arrow.rect.minY),
      );
      final data = resized.data as ArrowData;

      expect(data.startBinding, isNotNull);
      expect(data.endBinding, isNotNull);
      expect(data.startBinding!.anchor.x, closeTo(0.75, 1e-9));
      expect(data.startBinding!.anchor.y, closeTo(0.7, 1e-9));
      expect(data.endBinding!.anchor.x, closeTo(0.1, 1e-9));
      expect(data.endBinding!.anchor.y, closeTo(0.3, 1e-9));

      final fixedSegments = data.fixedSegments;
      expect(fixedSegments, isNotNull);
      expect(fixedSegments, hasLength(2));
      expect(
        fixedSegments!.first,
        const ElbowFixedSegment(
          index: 1,
          start: DrawPoint(x: -100, y: 150),
          end: DrawPoint(x: 100, y: 150),
        ),
      );
      expect(
        fixedSegments.last,
        const ElbowFixedSegment(
          index: 2,
          start: DrawPoint(x: 100, y: 150),
          end: DrawPoint(x: 100, y: 200),
        ),
      );
    });

    test('vertical flip mirrors binding anchors and fixed segments', () {
      final arrow = _elbowArrowElement(
        id: 'arrow-flip-y',
        points: const <DrawPoint>[
          DrawPoint(x: 100, y: 100),
          DrawPoint(x: 240, y: 100),
          DrawPoint(x: 240, y: 240),
        ],
        startBinding: const ArrowBinding(
          elementId: 'start-target',
          anchor: DrawPoint(x: 0.4, y: 0.2),
        ),
        endBinding: const ArrowBinding(
          elementId: 'end-target',
          anchor: DrawPoint(x: 0.6, y: 0.85),
        ),
        fixedSegments: const <ElbowFixedSegment>[
          ElbowFixedSegment(
            index: 1,
            start: DrawPoint(x: 100, y: 100),
            end: DrawPoint(x: 240, y: 100),
          ),
          ElbowFixedSegment(
            index: 2,
            start: DrawPoint(x: 240, y: 100),
            end: DrawPoint(x: 240, y: 240),
          ),
        ],
      );

      final resized = _applySingleArrowResize(
        element: arrow,
        scaleX: 1,
        scaleY: -1,
        anchor: DrawPoint(x: arrow.rect.minX, y: arrow.rect.minY),
      );
      final data = resized.data as ArrowData;

      expect(data.startBinding, isNotNull);
      expect(data.endBinding, isNotNull);
      expect(data.startBinding!.anchor.x, closeTo(0.4, 1e-9));
      expect(data.startBinding!.anchor.y, closeTo(0.8, 1e-9));
      expect(data.endBinding!.anchor.x, closeTo(0.6, 1e-9));
      expect(data.endBinding!.anchor.y, closeTo(0.15, 1e-9));

      final fixedSegments = data.fixedSegments;
      expect(fixedSegments, isNotNull);
      expect(fixedSegments, hasLength(2));
      expect(
        fixedSegments!.first,
        const ElbowFixedSegment(
          index: 1,
          start: DrawPoint(x: 100, y: -40),
          end: DrawPoint(x: 240, y: -40),
        ),
      );
      expect(
        fixedSegments.last,
        const ElbowFixedSegment(
          index: 2,
          start: DrawPoint(x: 240, y: -40),
          end: DrawPoint(x: 240, y: 100),
        ),
      );
    });
  });
}

ElementState _applySingleArrowResize({
  required ElementState element,
  required double scaleX,
  required double scaleY,
  required DrawPoint anchor,
}) {
  final snapshots = <String, ElementResizeSnapshot>{
    element.id: ElementResizeSnapshot(rect: element.rect, rotation: 0),
  };
  final context = ResizeEditContext(
    startPosition: anchor,
    startBounds: element.rect,
    selectedIdsAtStart: <String>{element.id},
    selectionVersion: 1,
    elementsVersion: 1,
    resizeMode: ResizeMode.right,
    handleOffset: DrawPoint.zero,
    rotation: 0,
    elementSnapshots: snapshots,
  );
  final updates = EditApply.applyResizeToElements(
    snapshots: snapshots,
    selectedIds: <String>{element.id},
    context: context,
    newSelectionBounds: element.rect,
    scaleX: scaleX,
    scaleY: scaleY,
    anchor: anchor,
    currentElementsById: <String, ElementState>{element.id: element},
  );
  return updates[element.id]!;
}

ElementState _elbowArrowElement({
  required String id,
  required List<DrawPoint> points,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  List<ElbowFixedSegment>? fixedSegments,
}) {
  final rect = DrawRect.fromPointCloud(points);
  final normalizedPoints = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: ArrowData(
      points: normalizedPoints,
      arrowType: ArrowType.elbow,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: fixedSegments,
    ),
  );
}
