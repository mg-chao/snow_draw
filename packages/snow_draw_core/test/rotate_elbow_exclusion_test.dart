import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/edit/apply/edit_apply.dart';
import 'package:snow_draw_core/draw/elements/core/element_registry.dart';
import 'package:snow_draw_core/draw/elements/registration.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_data.dart';
import 'package:snow_draw_core/draw/elements/types/arrow/arrow_geometry.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/domain_state.dart';
import 'package:snow_draw_core/draw/models/draw_state.dart';
import 'package:snow_draw_core/draw/models/draw_state_view.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/element_geometry.dart';
import 'package:snow_draw_core/draw/types/element_style.dart';
import 'package:snow_draw_core/draw/utils/hit_test.dart';
import 'elbow_test_utils.dart';

void main() {
  test('applyRotateToElements skips elbow arrows but rotates others', () {
    final elbowPoints = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 20, y: 0),
      const DrawPoint(x: 20, y: 20),
    ];
    final elbowArrow = _elbowArrowElement(id: 'elbow', points: elbowPoints);
    final rectElement = _rectangleElement(
      id: 'rect',
      rect: const DrawRect(minX: 8, minY: -2, maxX: 12, maxY: 2),
    );

    final snapshots = <String, ElementRotateSnapshot>{
      elbowArrow.id: ElementRotateSnapshot(
        center: elbowArrow.center,
        rotation: elbowArrow.rotation,
      ),
      rectElement.id: ElementRotateSnapshot(
        center: rectElement.center,
        rotation: rectElement.rotation,
      ),
    };

    final result = EditApply.applyRotateToElements(
      snapshots: snapshots,
      selectedIds: {elbowArrow.id, rectElement.id},
      pivot: DrawPoint.zero,
      deltaAngle: math.pi / 2,
      currentElementsById: {
        elbowArrow.id: elbowArrow,
        rectElement.id: rectElement,
      },
    );

    expect(result.containsKey(elbowArrow.id), isFalse);

    final updatedRect = result[rectElement.id];
    expect(updatedRect, isNotNull);
    expect(updatedRect!.rotation, closeTo(math.pi / 2, 1e-6));
    expect(updatedRect.rect.center.x, closeTo(0, 1e-6));
    expect(updatedRect.rect.center.y, closeTo(10, 1e-6));
  });

  test('hitTest ignores rotate handle for single elbow arrow', () {
    final elbowPoints = <DrawPoint>[
      DrawPoint.zero,
      const DrawPoint(x: 100, y: 0),
      const DrawPoint(x: 100, y: 80),
    ];
    final elbowArrow = _elbowArrowElement(id: 'elbow', points: elbowPoints);
    final domain = DomainState(
      document: DocumentState(elements: [elbowArrow]),
    ).withSelected(elbowArrow.id);
    final state = DrawState(domain: domain);
    final stateView = DrawStateView.fromState(state);
    final registry = DefaultElementRegistry();
    registerBuiltInElements(registry);
    final selectionConfig = DrawConfig.defaultConfig.selection;
    final rotateHandlePosition = DrawPoint(
      x: elbowArrow.rect.centerX,
      y:
          elbowArrow.rect.minY -
          selectionConfig.padding -
          selectionConfig.rotateHandleOffset,
    );

    final result = hitTest.test(
      stateView: stateView,
      position: rotateHandlePosition,
      config: selectionConfig,
      registry: registry,
    );

    expect(result.isHandleHit, isFalse);
    expect(result.handleType, isNot(HandleType.rotate));
  });
}

ElementState _elbowArrowElement({
  required String id,
  required List<DrawPoint> points,
}) {
  final rect = elbowRectForPoints(points);
  final normalized = ArrowGeometry.normalizePoints(
    worldPoints: points,
    rect: rect,
  );
  final data = ArrowData(points: normalized, arrowType: ArrowType.elbow);
  return ElementState(
    id: id,
    rect: rect,
    rotation: 0,
    opacity: 1,
    zIndex: 0,
    data: data,
  );
}

ElementState _rectangleElement({
  required String id,
  required DrawRect rect,
}) => ElementState(
  id: id,
  rect: rect,
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: const RectangleData(),
);
