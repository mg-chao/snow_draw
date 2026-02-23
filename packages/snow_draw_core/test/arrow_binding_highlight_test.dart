import 'package:test/test.dart';
import 'package:snow_draw_core/draw/edit/arrow/arrow_point_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_target_cache.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_points.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/edit_transform.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/arrow_binding_highlight.dart';

void main() {
  const endBinding = ArrowBinding(
    elementId: 'rect',
    anchor: DrawPoint(x: 1, y: 0.5),
  );

  test('resolveArrowPointEditHighlightBinding uses initial endpoint index', () {
    final context = _buildTurningContext(pointIndex: 3);
    const data = ArrowData(
      points: [
        DrawPoint.zero,
        DrawPoint(x: 0.3, y: 0),
        DrawPoint(x: 0.3, y: 0.4),
        DrawPoint(x: 0.6, y: 0.4),
        DrawPoint(x: 0.8, y: 0.6),
      ],
      arrowType: ArrowType.elbow,
    );

    final result = resolveArrowPointEditHighlightBinding(
      context: context,
      data: data,
      transform: _buildTransform(context: context, endBinding: endBinding),
    );

    expect(result, endBinding);
  });

  test(
    'resolveArrowPointEditHighlightBinding ignores non-endpoint handles',
    () {
      final context = _buildTurningContext(pointIndex: 1);
      final data = ArrowData(
        points: context.initialPoints,
        arrowType: ArrowType.elbow,
      );

      final result = resolveArrowPointEditHighlightBinding(
        context: context,
        data: data,
        transform: _buildTransform(context: context, endBinding: endBinding),
      );

      expect(result, isNull);
    },
  );
}

const _elementRect = DrawRect(maxX: 100, maxY: 100);
const List<DrawPoint> _initialPoints = [
  DrawPoint.zero,
  DrawPoint(x: 0.2, y: 0),
  DrawPoint(x: 0.2, y: 0.3),
  DrawPoint(x: 0.4, y: 0.3),
];
const _baseElement = ElementState(
  id: 'arrow',
  rect: _elementRect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: ArrowData(points: _initialPoints, arrowType: ArrowType.elbow),
);

ArrowPointEditContext _buildTurningContext({required int pointIndex}) =>
    ArrowPointEditContext(
      startPosition: DrawPoint.zero,
      startBounds: _elementRect,
      selectedIdsAtStart: const {'arrow'},
      selectionVersion: 0,
      elementsVersion: 0,
      elementId: 'arrow',
      elementRect: _elementRect,
      rotation: 0,
      initialPoints: _initialPoints,
      initialFixedSegments: const [],
      arrowType: ArrowType.elbow,
      pointKind: ArrowPointKind.turning,
      pointIndex: pointIndex,
      dragOffset: DrawPoint.zero,
      baseElement: _baseElement,
      elementSpace: null,
      releaseFixedSegment: false,
      deletePointOnStart: false,
      startArrowhead: ArrowheadStyle.none,
      endArrowhead: ArrowheadStyle.standard,
      initialStartBinding: null,
      initialEndBinding: null,
      hasBindableTargets: false,
      bindingTargetCache: ArrowBindingTargetCache(),
    );

ArrowPointTransform _buildTransform({
  required ArrowPointEditContext context,
  required ArrowBinding endBinding,
}) => ArrowPointTransform(
  currentPosition: DrawPoint.zero,
  points: context.initialPoints,
  endBinding: endBinding,
);
