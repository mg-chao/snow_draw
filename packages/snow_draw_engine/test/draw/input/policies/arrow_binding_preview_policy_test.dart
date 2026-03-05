import 'package:snow_draw_engine/draw/config/draw_config.dart';
import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/elements/types/serial_number/serial_number_data.dart';
import 'package:snow_draw_engine/draw/input/policies/arrow_binding_preview_policy.dart';
import 'package:snow_draw_engine/draw/models/document_state.dart';
import 'package:snow_draw_engine/draw/models/domain_state.dart';
import 'package:snow_draw_engine/draw/models/draw_state.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_color.dart';
import 'package:snow_draw_engine/draw/types/draw_point.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/utils/snapping_mode.dart';
import 'package:test/test.dart';

void main() {
  group('arrow_binding_preview_policy', () {
    test('shouldPreviewArrowBinding follows binding-enabled policy', () {
      final enabled = DrawConfig.defaultConfig.snap;
      expect(
        shouldPreviewArrowBinding(
          snapConfig: enabled,
          snappingMode: SnappingMode.none,
        ),
        isTrue,
      );
      expect(
        shouldPreviewArrowBinding(
          snapConfig: enabled,
          snappingMode: SnappingMode.grid,
        ),
        isTrue,
      );

      final objectSnapEnabled = enabled.copyWith(enabled: true);
      expect(
        shouldPreviewArrowBinding(
          snapConfig: objectSnapEnabled,
          snappingMode: SnappingMode.none,
        ),
        isTrue,
      );

      final bindingDisabled = enabled.copyWith(enableArrowBinding: false);
      expect(
        shouldPreviewArrowBinding(
          snapConfig: bindingDisabled,
          snappingMode: SnappingMode.object,
        ),
        isFalse,
      );
    });

    test('resolveArrowBindingTargets returns nearby bindables only', () {
      const nearRect = ElementState(
        id: 'near-rect',
        rect: DrawRect(minX: 80, minY: 80, maxX: 140, maxY: 140),
        rotation: 0,
        opacity: 1,
        zIndex: 1,
        data: RectangleData(),
      );
      const nearSerial = ElementState(
        id: 'near-serial',
        rect: DrawRect(minX: 150, minY: 80, maxX: 190, maxY: 120),
        rotation: 0,
        opacity: 1,
        zIndex: 2,
        data: SerialNumberData(),
      );
      const hiddenRect = ElementState(
        id: 'hidden-rect',
        rect: DrawRect(minX: 90, minY: 150, maxX: 150, maxY: 210),
        rotation: 0,
        opacity: 0,
        zIndex: 3,
        data: RectangleData(),
      );
      const farRect = ElementState(
        id: 'far-rect',
        rect: DrawRect(minX: 320, minY: 320, maxX: 380, maxY: 380),
        rotation: 0,
        opacity: 1,
        zIndex: 4,
        data: RectangleData(),
      );
      final state = DrawState(
        domain: DomainState(
          document: DocumentState(
            elements: const <ElementState>[
              nearRect,
              nearSerial,
              hiddenRect,
              farRect,
            ],
          ),
        ),
      );

      final targets = resolveArrowBindingTargets(
        state: state,
        position: const DrawPoint(x: 120, y: 110),
        distance: 90,
      );

      final ids = targets.map((element) => element.id).toSet();
      expect(ids.contains('near-rect'), isTrue);
      expect(ids.contains('near-serial'), isTrue);
      expect(ids.contains('hidden-rect'), isFalse);
      expect(ids.contains('far-rect'), isFalse);
    });

    test(
      'resolveArrowBindingTargets orders overlaps by z-index and geometry',
      () {
        const bottom = ElementState(
          id: 'bottom',
          rect: DrawRect(minX: 80, minY: 80, maxX: 160, maxY: 160),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        );
        const top = ElementState(
          id: 'top',
          rect: DrawRect(minX: 100, minY: 100, maxX: 180, maxY: 180),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(),
        );
        final state = DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const <ElementState>[bottom, top],
            ),
          ),
        );

        final targets = resolveArrowBindingTargets(
          state: state,
          position: const DrawPoint(x: 120, y: 120),
          distance: 8,
        );

        expect(targets.map((element) => element.id).toList(), <String>[
          'bottom',
          'top',
        ]);
      },
    );

    test(
      'resolveArrowBindingTargets filters fully non-overlapping bindables',
      () {
        const nearby = ElementState(
          id: 'nearby',
          rect: DrawRect(maxX: 40, maxY: 40),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(fillColor: DrawColor(0xFFFFFFFF)),
        );
        const far = ElementState(
          id: 'far',
          rect: DrawRect(minX: 260, minY: 260, maxX: 320, maxY: 320),
          rotation: 0,
          opacity: 1,
          zIndex: 2,
          data: RectangleData(fillColor: DrawColor(0xFFFFFFFF)),
        );
        final state = DrawState(
          domain: DomainState(
            document: DocumentState(
              elements: const <ElementState>[nearby, far],
            ),
          ),
        );

        final targets = resolveArrowBindingTargets(
          state: state,
          position: const DrawPoint(x: 100, y: 100),
          distance: 20,
        );

        expect(targets, isEmpty);
      },
    );
  });
}
