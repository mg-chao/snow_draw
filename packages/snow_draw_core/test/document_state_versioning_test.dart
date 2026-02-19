import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/config/draw_config.dart';
import 'package:snow_draw_core/draw/elements/types/free_draw/free_draw_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('DocumentState versioning', () {
    test('global elements update bumps elementsVersion', () {
      final base = DocumentState(
        elements: const [_element],
        elementsVersion: 7,
      );
      final next = base.copyWith(
        globalElements: base.globalElements.copyWith(
          watermark: const WatermarkConfig(text: 'INTERNAL'),
        ),
      );

      expect(next.elementsVersion, equals(8));
      expect(next.elements, same(base.elements));
      expect(next.globalElements.watermark.text, equals('INTERNAL'));
    });

    test('element list update bumps elementsVersion', () {
      final base = DocumentState(
        elements: const [_element],
        elementsVersion: 7,
      );
      final next = base.copyWith(
        elements: const [
          _element,
          ElementState(
            id: 'second',
            rect: DrawRect(minX: 30, minY: 30, maxX: 60, maxY: 60),
            rotation: 0,
            opacity: 1,
            zIndex: 1,
            data: FreeDrawData(),
          ),
        ],
      );

      expect(next.elementsVersion, equals(8));
      expect(next.elements.length, equals(2));
    });
  });
}

const _element = ElementState(
  id: 'first',
  rect: DrawRect(maxX: 20, maxY: 20),
  rotation: 0,
  opacity: 1,
  zIndex: 0,
  data: FreeDrawData(),
);
