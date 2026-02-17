import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/types/filter/filter_data.dart';
import 'package:snow_draw_core/draw/elements/types/highlight/highlight_data.dart';
import 'package:snow_draw_core/draw/elements/types/rectangle/rectangle_data.dart';
import 'package:snow_draw_core/draw/models/document_state.dart';
import 'package:snow_draw_core/draw/models/element_state.dart';
import 'package:snow_draw_core/draw/types/draw_rect.dart';

void main() {
  group('DocumentState blend-sensitive range queries', () {
    test('detects blend-sensitive elements at or above index', () {
      final document = DocumentState(
        elements: [
          _rectangle(id: 'rect-1', zIndex: 0),
          _highlight(id: 'hl-1', zIndex: 1),
          _rectangle(id: 'rect-2', zIndex: 2),
          _filter(id: 'filter-1', zIndex: 3),
        ],
      );

      expect(document.hasBlendSensitiveElementFromOrderIndex(0), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(1), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(2), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(4), isFalse);
    });

    test('above-index query excludes the current order index', () {
      final document = DocumentState(
        elements: [
          _highlight(id: 'hl-1', zIndex: 0),
          _rectangle(id: 'rect-1', zIndex: 1),
        ],
      );

      expect(document.hasBlendSensitiveElementAboveOrderIndex(0), isFalse);
      expect(document.hasBlendSensitiveElementAboveOrderIndex(-1), isTrue);
    });

    test('can ignore transparent blend-sensitive elements', () {
      final document = DocumentState(
        elements: [
          _highlight(id: 'hl-1', zIndex: 0, opacity: 0),
          _filter(id: 'filter-1', zIndex: 1, opacity: 0),
          _rectangle(id: 'rect-1', zIndex: 2),
        ],
      );

      expect(document.hasBlendSensitiveElementFromOrderIndex(0), isTrue);
      expect(
        document.hasBlendSensitiveElementFromOrderIndex(
          0,
          includeTransparent: false,
        ),
        isFalse,
      );
    });

    test('handles index bounds safely', () {
      final document = DocumentState(
        elements: [
          _rectangle(id: 'rect-1', zIndex: 0),
          _highlight(id: 'hl-1', zIndex: 1),
        ],
      );

      expect(document.hasBlendSensitiveElementFromOrderIndex(-100), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(100), isFalse);
      expect(document.hasBlendSensitiveElementAboveOrderIndex(100), isFalse);
    });

    test('returns false for empty documents', () {
      final document = DocumentState();

      expect(document.hasBlendSensitiveElementFromOrderIndex(0), isFalse);
      expect(document.hasBlendSensitiveElementAboveOrderIndex(0), isFalse);
      expect(
        document.hasBlendSensitiveElementFromOrderIndex(
          0,
          includeTransparent: false,
        ),
        isFalse,
      );
    });
  });
}

ElementState _rectangle({
  required String id,
  required int zIndex,
  double opacity = 1,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 40, maxY: 30),
  rotation: 0,
  opacity: opacity,
  zIndex: zIndex,
  data: const RectangleData(),
);

ElementState _highlight({
  required String id,
  required int zIndex,
  double opacity = 1,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 40, maxY: 30),
  rotation: 0,
  opacity: opacity,
  zIndex: zIndex,
  data: const HighlightData(),
);

ElementState _filter({
  required String id,
  required int zIndex,
  double opacity = 1,
}) => ElementState(
  id: id,
  rect: const DrawRect(maxX: 40, maxY: 30),
  rotation: 0,
  opacity: opacity,
  zIndex: zIndex,
  data: const FilterData(),
);
