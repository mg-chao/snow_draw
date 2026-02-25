import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/models/selection_geometry.dart';
import 'package:snow_draw_engine/draw/models/selection_overlay_state.dart';
import 'package:snow_draw_engine/draw/models/selection_state.dart';
import 'package:snow_draw_engine/draw/services/selection_geometry_resolver.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/utils/selection_calculator.dart';
import 'package:test/test.dart';

void main() {
  group('SelectionGeometryResolver', () {
    test('returns none geometry for empty selection', () {
      final geometry = SelectionGeometryResolver.resolve(
        selectedElements: const [],
        selectionOverlay: SelectionOverlayState.empty,
      );

      expect(geometry, equals(SelectionGeometry.none));
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

      final geometry = SelectionGeometryResolver.resolve(
        selectedElements: selected,
        selectionOverlay: SelectionOverlayState.empty,
      );

      expect(geometry.hasSelection, isTrue);
      expect(geometry.isSingleSelect, isTrue);
      expect(geometry.bounds, equals(selected.first.rect));
      expect(geometry.center, equals(selected.first.center));
      expect(geometry.rotation, equals(selected.first.rotation));
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

      final geometry = SelectionGeometryResolver.resolve(
        selectedElements: selected,
        selectionOverlay: overlay,
      );

      expect(geometry.hasSelection, isTrue);
      expect(geometry.isMultiSelect, isTrue);
      expect(geometry.bounds, equals(overlayBounds));
      expect(geometry.center, equals(overlayBounds.center));
      expect(geometry.rotation, equals(0.5));
    });

    test('multi selection falls back to computed bounds', () {
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
      final computedBounds =
          SelectionCalculator.computeSelectionBoundsForElements(selected);

      final geometry = SelectionGeometryResolver.resolve(
        selectedElements: selected,
        selectionOverlay: SelectionOverlayState.empty,
      );

      expect(geometry.hasSelection, isTrue);
      expect(geometry.isMultiSelect, isTrue);
      expect(geometry.bounds, equals(computedBounds));
      expect(geometry.center, equals(computedBounds?.center));
      expect(geometry.rotation, isNull);
    });
  });
}
