import 'package:snow_draw_engine/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_engine/draw/models/element_state.dart';
import 'package:snow_draw_engine/draw/types/draw_rect.dart';
import 'package:snow_draw_engine/draw/utils/camera_zoom.dart';
import 'package:snow_draw_engine/draw/utils/visible_elements.dart';
import 'package:test/test.dart';

void main() {
  group('resolveEffectiveZoom', () {
    test('keeps valid positive zoom values', () {
      expect(resolveEffectiveZoom(2.5), 2.5);
    });

    test('falls back to 1.0 for invalid zoom values', () {
      expect(resolveEffectiveZoom(0), 1.0);
      expect(resolveEffectiveZoom(-2), 1.0);
      expect(resolveEffectiveZoom(double.nan), 1.0);
      expect(resolveEffectiveZoom(double.infinity), 1.0);
    });
  });

  group('resolveZoomAdjustedDistance', () {
    test('converts distance using zoom', () {
      expect(
        resolveZoomAdjustedDistance(distance: 20, zoom: 4),
        closeTo(5, 0.0001),
      );
    });

    test('uses fallback zoom when input zoom is invalid', () {
      expect(resolveZoomAdjustedDistance(distance: 20, zoom: 0), 20);
      expect(resolveZoomAdjustedDistance(distance: 20, zoom: -1), 20);
    });
  });

  group('resolveVisibleElements', () {
    test('keeps only visible elements', () {
      final elements = [_element('a', opacity: 1), _element('b', opacity: 0)];

      final visible = resolveVisibleElements(elements);

      expect(visible.map((element) => element.id), ['a']);
    });

    test('excludes provided ids', () {
      final elements = [_element('a', opacity: 1), _element('b', opacity: 1)];

      final visible = resolveVisibleElements(elements, excludedIds: {'a'});

      expect(visible.map((element) => element.id), ['b']);
    });
  });
}

ElementState _element(String id, {required double opacity}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 10, maxY: 10),
  rotation: 0,
  opacity: opacity,
  zIndex: 0,
  data: const RectangleData(),
);
