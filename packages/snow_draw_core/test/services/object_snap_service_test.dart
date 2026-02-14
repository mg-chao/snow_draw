import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/services/object_snap_service.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/types/snap_guides.dart';

void main() {
  group('ObjectSnapService', () {
    ElementState element(String id, DrawRect rect) => ElementState(
      id: id,
      rect: rect,
      rotation: 0,
      opacity: 1,
      zIndex: 0,
      data: const RectangleData(),
    );

    test('returns empty result when both snap modes are disabled', () {
      const service = ObjectSnapService();
      final result = service.snapRect(
        targetRect: const DrawRect(maxX: 10, maxY: 10),
        referenceElements: [
          element('ref', const DrawRect(minX: 20, maxX: 30, maxY: 10)),
        ],
        snapDistance: 10,
        targetAnchorsX: const [SnapAxisAnchor.end],
        targetAnchorsY: const [SnapAxisAnchor.start],
        enablePointSnaps: false,
        enableGapSnaps: false,
      );

      expect(result.hasSnap, isFalse);
      expect(result.dx, 0);
      expect(result.dy, 0);
      expect(result.guides, isEmpty);
    });

    test('returns empty result when no target anchors are provided', () {
      const service = ObjectSnapService();
      final result = service.snapRect(
        targetRect: const DrawRect(maxX: 10, maxY: 10),
        referenceElements: [
          element('ref', const DrawRect(minX: 11, maxX: 21, maxY: 10)),
        ],
        snapDistance: 10,
        targetAnchorsX: const [],
        targetAnchorsY: const [],
      );

      expect(result.hasSnap, isFalse);
      expect(result.dx, 0);
      expect(result.dy, 0);
      expect(result.guides, isEmpty);
    });

    test('snaps end anchor to reference start for point snapping', () {
      const service = ObjectSnapService();
      final result = service.snapRect(
        targetRect: const DrawRect(maxX: 10, maxY: 10),
        referenceElements: [
          element('ref', const DrawRect(minX: 15, maxX: 25, maxY: 10)),
        ],
        snapDistance: 6,
        targetAnchorsX: const [SnapAxisAnchor.end],
        targetAnchorsY: const [],
        enableGapSnaps: false,
      );

      expect(result.hasSnap, isTrue);
      expect(result.dx, 5);
      expect(result.dy, 0);
      expect(
        result.guides.any(
          (guide) =>
              guide.kind == SnapGuideKind.point &&
              guide.axis == SnapGuideAxis.vertical,
        ),
        isTrue,
      );
    });
  });
}
