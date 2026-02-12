import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/core/edit_modifiers.dart';
import 'package:snow_draw_core/draw/edit/core/edit_operation_params.dart';
import 'package:snow_draw_core/draw/edit/move/move_operation.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_binding_resolver.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_editing.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/elbow/elbow_fixed_segment.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/combined_element_lookup.dart';

void main() {
  setUp(() {
    ArrowBindingResolver.instance.invalidate();
  });

  test(
    'moving elbow arrow clears bindings and stops follow-up binding updates',
    () {
      final target = _rectangleElement(
        id: 'target',
        rect: const DrawRect(minX: -10, minY: 140, maxX: 50, maxY: 200),
      );
      const endBinding = ArrowBinding(
        elementId: 'target',
        anchor: DrawPoint(x: 0.5, y: 0),
      );
      final basePoints = <DrawPoint>[
        DrawPoint.zero,
        const DrawPoint(x: 120, y: 0),
        const DrawPoint(x: 120, y: 80),
        const DrawPoint(x: 20, y: 80),
      ];
      final baseFixedSegments = <ElbowFixedSegment>[
        ElbowFixedSegment(index: 2, start: basePoints[1], end: basePoints[2]),
      ];
      final baseArrow = _arrowElement(
        id: 'arrow-base',
        arrowType: ArrowType.elbow,
        points: basePoints,
        fixedSegments: baseFixedSegments,
      );
      final baseData = baseArrow.data as ArrowData;
      final boundPoint =
          ArrowBindingUtils.resolveElbowBoundPoint(
            binding: endBinding,
            target: target,
            hasArrowhead: baseData.endArrowhead != ArrowheadStyle.none,
          ) ??
          basePoints.last;
      final movedPoints = List<DrawPoint>.from(basePoints);
      movedPoints[movedPoints.length - 1] = boundPoint;
      final boundResult = computeElbowEdit(
        element: baseArrow,
        data: baseData.copyWith(endBinding: endBinding),
        lookup: CombinedElementLookup(base: {target.id: target}),
        localPointsOverride: movedPoints,
        fixedSegmentsOverride: baseFixedSegments,
        endBindingOverride: endBinding,
      );
      expect(
        boundResult.localPoints.length,
        greaterThan(basePoints.length),
        reason: 'Test setup should produce a bound-tail elbow path.',
      );

      final arrow = _arrowElement(
        id: 'arrow',
        arrowType: ArrowType.elbow,
        points: boundResult.localPoints,
        endBinding: endBinding,
        fixedSegments: boundResult.fixedSegments,
        endIsSpecial: true,
      );
      final boundData = arrow.data as ArrowData;

      final state = DrawState(
        domain: DomainState(
          document: DocumentState(elements: [target, arrow]),
          selection: const SelectionState(selectedIds: {'arrow'}),
        ),
      );

      const operation = MoveOperation();
      final context = operation.createContext(
        state: state,
        position: arrow.center,
        params: const MoveOperationParams(),
      );
      final initialTransform = operation.initialTransform(
        state: state,
        context: context,
        startPosition: arrow.center,
      );
      final update = operation.update(
        state: state,
        context: context,
        transform: initialTransform,
        currentPosition: arrow.center.translate(const DrawPoint(x: 36, y: 24)),
        modifiers: const EditModifiers(),
        config: DrawConfig.defaultConfig,
      );
      final movedState = operation.finish(
        state: state,
        context: context,
        transform: update.transform,
      );

      final movedArrow = movedState.domain.document.getElementById('arrow');
      expect(movedArrow, isNotNull);
      final movedData = movedArrow!.data as ArrowData;
      expect(movedData.startBinding, isNull);
      expect(movedData.endBinding, isNull);
      expect(movedData.startIsSpecial, isNull);
      expect(movedData.endIsSpecial, isNull);
      expect(
        movedData.points.length,
        lessThan(boundData.points.length),
        reason: 'Unbinding should recompute elbow path and remove bound tail.',
      );

      final movedTarget = target.copyWith(
        rect: target.rect.translate(const DrawPoint(x: 48, y: 0)),
      );
      final bindingUpdates = ArrowBindingResolver.instance.resolve(
        baseElements: movedState.domain.document.elementMap,
        updatedElements: {target.id: movedTarget},
        changedElementIds: {target.id},
        document: movedState.domain.document,
      );
      expect(bindingUpdates.containsKey('arrow'), isFalse);
    },
  );

  test('moving non-elbow arrow also clears bindings', () {
    final target = _rectangleElement(
      id: 'target',
      rect: const DrawRect(minX: 200, minY: 40, maxX: 280, maxY: 120),
    );
    const startBinding = ArrowBinding(
      elementId: 'target',
      anchor: DrawPoint(x: 0, y: 0.5),
    );
    final arrow = _arrowElement(
      id: 'arrow',
      arrowType: ArrowType.straight,
      points: const <DrawPoint>[
        DrawPoint(x: 120, y: 80),
        DrawPoint(x: 180, y: 120),
      ],
      startBinding: startBinding,
      startIsSpecial: true,
    );

    final state = DrawState(
      domain: DomainState(
        document: DocumentState(elements: [target, arrow]),
        selection: const SelectionState(selectedIds: {'arrow'}),
      ),
    );

    const operation = MoveOperation();
    final context = operation.createContext(
      state: state,
      position: arrow.center,
      params: const MoveOperationParams(),
    );
    final initialTransform = operation.initialTransform(
      state: state,
      context: context,
      startPosition: arrow.center,
    );
    final update = operation.update(
      state: state,
      context: context,
      transform: initialTransform,
      currentPosition: arrow.center.translate(const DrawPoint(x: 30, y: 10)),
      modifiers: const EditModifiers(),
      config: DrawConfig.defaultConfig,
    );
    final movedState = operation.finish(
      state: state,
      context: context,
      transform: update.transform,
    );

    final movedArrow = movedState.domain.document.getElementById('arrow');
    expect(movedArrow, isNotNull);
    final movedData = movedArrow!.data as ArrowData;
    expect(movedData.startBinding, isNull);
    expect(movedData.endBinding, isNull);
    expect(movedData.startIsSpecial, isNull);
    expect(movedData.endIsSpecial, isNull);

    final movedTarget = target.copyWith(
      rect: target.rect.translate(const DrawPoint(x: 48, y: 0)),
    );
    final bindingUpdates = ArrowBindingResolver.instance.resolve(
      baseElements: movedState.domain.document.elementMap,
      updatedElements: {target.id: movedTarget},
      changedElementIds: {target.id},
      document: movedState.domain.document,
    );
    expect(bindingUpdates.containsKey('arrow'), isFalse);
  });
}

ElementState _arrowElement({
  required String id,
  required ArrowType arrowType,
  required List<DrawPoint> points,
  ArrowBinding? startBinding,
  ArrowBinding? endBinding,
  List<ElbowFixedSegment>? fixedSegments,
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
      arrowType: arrowType,
      startBinding: startBinding,
      endBinding: endBinding,
      fixedSegments: fixedSegments,
      startIsSpecial: startIsSpecial,
      endIsSpecial: endIsSpecial,
    ),
  );
}

ElementState _rectangleElement({required String id, required DrawRect rect}) =>
    ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

DrawRect _rectForPoints(List<DrawPoint> points) {
  var minX = points.first.x;
  var maxX = points.first.x;
  var minY = points.first.y;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    minX = math.min(minX, point.x);
    maxX = math.max(maxX, point.x);
    minY = math.min(minY, point.y);
    maxY = math.max(maxY, point.y);
  }

  if (minX == maxX) {
    maxX = minX + 1;
  }
  if (minY == maxY) {
    maxY = minY + 1;
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
