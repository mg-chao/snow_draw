import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/services/object_snap_service.dart';
import 'package:snow_draw_core/draw/types/draw_point.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/snap_guides.dart';

void main() {
  group('ObjectSnapService optimization characterization', () {
    ElementState element(String id, DrawRect rect) => ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

    test('snapMove applies targetOffset when targetElements are provided', () {
      const service = ObjectSnapService();
      const baseTargetRect = DrawRect(maxX: 10, maxY: 10);
      const targetOffset = DrawPoint(x: 4, y: 0);
      const movedTargetRect = DrawRect(minX: 4, maxX: 14, maxY: 10);

      final result = service.snapMove(
        targetRect: movedTargetRect,
        referenceElements: [
          element('ref', const DrawRect(minX: 15, maxX: 25, maxY: 10)),
        ],
        snapDistance: 2,
        targetElements: [element('target', baseTargetRect)],
        targetOffset: targetOffset,
        enableGapSnaps: false,
      );

      expect(result.hasSnap, isTrue);
      expect(result.dx, 1);
      expect(result.dy, 0);
      expect(
        result.guides.any((guide) => guide.kind == SnapGuideKind.point),
        isTrue,
      );
    });

    test('gap snapping remains active when point snapping is disabled '
        'with target elements', () {
      const service = ObjectSnapService();
      const targetRect = DrawRect(minX: 12, maxX: 22, maxY: 10);

      final result = service.snapRect(
        targetRect: targetRect,
        referenceElements: [
          element('left', const DrawRect(maxX: 10, maxY: 10)),
          element('right', const DrawRect(minX: 30, maxX: 40, maxY: 10)),
        ],
        snapDistance: 5,
        targetAnchorsX: const [SnapAxisAnchor.center],
        targetAnchorsY: const [],
        targetElements: [element('target', targetRect)],
        enablePointSnaps: false,
      );

      expect(result.hasSnap, isTrue);
      expect(result.dx, 3);
      expect(result.dy, 0);
      expect(
        result.guides.any(
          (guide) =>
              guide.kind == SnapGuideKind.gap &&
              guide.axis == SnapGuideAxis.horizontal,
        ),
        isTrue,
      );
    });
  });
}
