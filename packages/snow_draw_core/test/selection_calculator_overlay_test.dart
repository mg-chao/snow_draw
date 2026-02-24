import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/models/selection_overlay_state.dart';
import 'package:snow_draw_core/draw/models/selection_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';
import 'package:snow_draw_core/draw/utils/selection_calculator.dart';
import 'package:test/test.dart';

void main() {
  group('SelectionCalculator overlay helpers', () {
    test('return null geometry for empty selection', () {
      const overlay = SelectionOverlayState.empty;

      expect(
        SelectionCalculator.computeOverlayBoundsForSelection(
          selectedElements: const [],
          selectionOverlay: overlay,
        ),
        isNull,
      );
      expect(
        SelectionCalculator.computeOverlayCenterForSelection(
          selectedElements: const [],
          selectionOverlay: overlay,
        ),
        isNull,
      );
      expect(
        SelectionCalculator.computeOverlayRotationForSelection(
          selectedElements: const [],
          selectionOverlay: overlay,
        ),
        isNull,
      );
    });

    test('single selection uses element geometry', () {
      const selected = [
        ElementState(
          id: 'single',
          rect: DrawRect(minX: 10, minY: 20, maxX: 30, maxY: 50),
          rotation: 0.75,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
      ];

      expect(
        SelectionCalculator.computeOverlayBoundsForSelection(
          selectedElements: selected,
          selectionOverlay: SelectionOverlayState.empty,
        ),
        selected.first.rect,
      );
      expect(
        SelectionCalculator.computeOverlayCenterForSelection(
          selectedElements: selected,
          selectionOverlay: SelectionOverlayState.empty,
        ),
        selected.first.center,
      );
      expect(
        SelectionCalculator.computeOverlayRotationForSelection(
          selectedElements: selected,
          selectionOverlay: SelectionOverlayState.empty,
        ),
        selected.first.rotation,
      );
    });

    test('multi selection prefers overlay bounds and rotation', () {
      const selected = [
        ElementState(
          id: 'a',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'b',
          rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
      ];
      const overlayBounds = DrawRect(minX: -5, minY: -5, maxX: 35, maxY: 15);
      const overlay = SelectionOverlayState(
        multiSelectOverlay: MultiSelectOverlayState(
          bounds: overlayBounds,
          rotation: 0.5,
        ),
      );

      expect(
        SelectionCalculator.computeOverlayBoundsForSelection(
          selectedElements: selected,
          selectionOverlay: overlay,
        ),
        overlayBounds,
      );
      expect(
        SelectionCalculator.computeOverlayCenterForSelection(
          selectedElements: selected,
          selectionOverlay: overlay,
        ),
        overlayBounds.center,
      );
      expect(
        SelectionCalculator.computeOverlayRotationForSelection(
          selectedElements: selected,
          selectionOverlay: overlay,
        ),
        0.5,
      );
    });

    test('multi selection falls back to computed bounds without overlay', () {
      const selected = [
        ElementState(
          id: 'a',
          rect: DrawRect(maxX: 10, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 0,
          data: RectangleData(),
        ),
        ElementState(
          id: 'b',
          rect: DrawRect(minX: 20, maxX: 30, maxY: 10),
          rotation: 0,
          opacity: 1,
          zIndex: 1,
          data: RectangleData(),
        ),
      ];
      final expectedBounds =
          SelectionCalculator.computeSelectionBoundsForElements(selected);

      expect(
        SelectionCalculator.computeOverlayBoundsForSelection(
          selectedElements: selected,
          selectionOverlay: SelectionOverlayState.empty,
        ),
        expectedBounds,
      );
      expect(
        SelectionCalculator.computeOverlayCenterForSelection(
          selectedElements: selected,
          selectionOverlay: SelectionOverlayState.empty,
        ),
        expectedBounds?.center,
      );
      expect(
        SelectionCalculator.computeOverlayRotationForSelection(
          selectedElements: selected,
          selectionOverlay: SelectionOverlayState.empty,
        ),
        isNull,
      );
    });
  });
}
