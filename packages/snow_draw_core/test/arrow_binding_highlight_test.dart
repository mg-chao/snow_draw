import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/arrow_binding_highlight.dart';

void main() {
  test('resolveArrowPointEditHighlightBinding uses initial endpoint index', () {
    final context = _buildContext(
      pointKind: ArrowPointKind.turning,
      pointIndex: 3,
    );
    final binding = ArrowBinding(
      elementId: 'rect',
      anchor: const DrawPoint(x: 1, y: 0.5),
    );
    final data = ArrowData(
      points: const [
        DrawPoint.zero,
        DrawPoint(x: 0.3, y: 0),
        DrawPoint(x: 0.3, y: 0.4),
        DrawPoint(x: 0.6, y: 0.4),
        DrawPoint(x: 0.8, y: 0.6),
      ],
      arrowType: ArrowType.elbow,
    );
    final transform = ArrowPointTransform(
      currentPosition: DrawPoint.zero,
      points: context.initialPoints,
      endBinding: binding,
      hasChanges: true,
    );

    final result = resolveArrowPointEditHighlightBinding(
      context: context,
      data: data,
      transform: transform,
    );

    expect(result, binding);
  });

  test(
    'resolveArrowPointEditHighlightBinding ignores non-endpoint handles',
    () {
      final context = _buildContext(
        pointKind: ArrowPointKind.turning,
        pointIndex: 1,
      );
      final binding = ArrowBinding(
        elementId: 'rect',
        anchor: const DrawPoint(x: 1, y: 0.5),
      );
      final data = ArrowData(
        points: context.initialPoints,
        arrowType: ArrowType.elbow,
      );
      final transform = ArrowPointTransform(
        currentPosition: DrawPoint.zero,
        points: context.initialPoints,
        endBinding: binding,
        hasChanges: true,
      );

      final result = resolveArrowPointEditHighlightBinding(
        context: context,
        data: data,
        transform: transform,
      );

      expect(result, isNull);
    },
  );
}

ArrowPointEditContext _buildContext({
  required ArrowPointKind pointKind,
  required int pointIndex,
}) {
  const elementRect = DrawRect(minX: 0, minY: 0, maxX: 100, maxY: 100);
  const points = [
    DrawPoint.zero,
    DrawPoint(x: 0.2, y: 0),
    DrawPoint(x: 0.2, y: 0.3),
    DrawPoint(x: 0.4, y: 0.3),
  ];
  return ArrowPointEditContext(
    startPosition: DrawPoint.zero,
    startBounds: elementRect,
    selectedIdsAtStart: const {'arrow'},
    selectionVersion: 0,
    elementsVersion: 0,
    elementId: 'arrow',
    elementRect: elementRect,
    rotation: 0,
    initialPoints: points,
    initialFixedSegments: const [],
    arrowType: ArrowType.elbow,
    pointKind: pointKind,
    pointIndex: pointIndex,
    dragOffset: DrawPoint.zero,
    releaseFixedSegment: false,
    deletePointOnStart: false,
    bindingTargetCache: BindingTargetCache(),
  );
}
