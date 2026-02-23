import 'package:test/test.dart';
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

    test('precomputed reference AABBs preserve snap output', () {
      const service = ObjectSnapService();
      const targetRect = DrawRect(maxX: 10, maxY: 10);
      final references = [
        element('ref1', const DrawRect(minX: 16, maxX: 26, maxY: 10)),
        element('ref2', const DrawRect(minY: 18, maxY: 28, maxX: 10)),
      ];
      final referenceAabbs = ObjectSnapService.buildReferenceAabbs(references);

      final uncached = service.snapRect(
        targetRect: targetRect,
        referenceElements: references,
        snapDistance: 10,
        targetAnchorsX: const [SnapAxisAnchor.end],
        targetAnchorsY: const [SnapAxisAnchor.end],
      );
      final cached = service.snapRect(
        targetRect: targetRect,
        referenceElements: references,
        referenceAabbs: referenceAabbs,
        snapDistance: 10,
        targetAnchorsX: const [SnapAxisAnchor.end],
        targetAnchorsY: const [SnapAxisAnchor.end],
      );

      expect(cached.dx, uncached.dx);
      expect(cached.dy, uncached.dy);
      expect(cached.guides, uncached.guides);
    });

    test('precomputed reference AABBs preserve snapMove output', () {
      const service = ObjectSnapService();
      const baseTargetRect = DrawRect(maxX: 10, maxY: 10);
      const movedTargetRect = DrawRect(minX: 4, maxX: 14, maxY: 10);
      final references = [
        element('ref1', const DrawRect(minX: 16, maxX: 26, maxY: 10)),
        element('ref2', const DrawRect(minY: 18, maxY: 28, maxX: 10)),
      ];
      final referenceAabbs = ObjectSnapService.buildReferenceAabbs(references);
      final targetElements = [element('target', baseTargetRect)];

      final uncached = service.snapMove(
        targetRect: movedTargetRect,
        referenceElements: references,
        snapDistance: 10,
        targetElements: targetElements,
        targetOffset: const DrawPoint(x: 4, y: 0),
      );
      final cached = service.snapMove(
        targetRect: movedTargetRect,
        referenceElements: references,
        referenceAabbs: referenceAabbs,
        snapDistance: 10,
        targetElements: targetElements,
        targetOffset: const DrawPoint(x: 4, y: 0),
      );

      expect(cached.dx, uncached.dx);
      expect(cached.dy, uncached.dy);
      expect(cached.guides, uncached.guides);
    });
  });
}
