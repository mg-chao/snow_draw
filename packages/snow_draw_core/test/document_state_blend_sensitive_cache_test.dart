import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_core/draw/elements/core/element_data.dart';
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
        elements: [_rectangle(0), _highlight(1), _rectangle(2), _filter(3)],
      );

      expect(document.hasBlendSensitiveElementFromOrderIndex(0), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(1), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(2), isTrue);
      expect(document.hasBlendSensitiveElementFromOrderIndex(4), isFalse);
    });

    test('above-index query excludes the current order index', () {
      final document = DocumentState(elements: [_highlight(0), _rectangle(1)]);

      expect(document.hasBlendSensitiveElementAboveOrderIndex(0), isFalse);
      expect(document.hasBlendSensitiveElementAboveOrderIndex(-1), isTrue);
    });

    test('can ignore transparent blend-sensitive elements', () {
      final document = DocumentState(
        elements: [
          _highlight(0, opacity: 0),
          _filter(1, opacity: 0),
          _rectangle(2),
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
      final document = DocumentState(elements: [_rectangle(0), _highlight(1)]);

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

  group('DocumentState filter range queries', () {
    test('detects filter elements at or above index', () {
      final document = DocumentState(
        elements: [_rectangle(0), _highlight(1), _filter(2), _rectangle(3)],
      );

      expect(document.hasFilterElementFromOrderIndex(0), isTrue);
      expect(document.hasFilterElementFromOrderIndex(2), isTrue);
      expect(document.hasFilterElementFromOrderIndex(3), isFalse);
      expect(document.hasFilterElementAboveOrderIndex(1), isTrue);
      expect(document.hasFilterElementAboveOrderIndex(2), isFalse);
    });

    test('can ignore transparent filters', () {
      final document = DocumentState(
        elements: [_filter(0, opacity: 0), _rectangle(1)],
      );

      expect(document.hasFilterElementFromOrderIndex(0), isTrue);
      expect(
        document.hasFilterElementFromOrderIndex(0, includeTransparent: false),
        isFalse,
      );
    });
  });
}

const DrawRect _defaultRect = DrawRect(maxX: 40, maxY: 30);

ElementState _rectangle(int zIndex, {double opacity = 1}) => _element(
  id: 'rect-$zIndex',
  zIndex: zIndex,
  opacity: opacity,
  data: const RectangleData(),
);

ElementState _highlight(int zIndex, {double opacity = 1}) => _element(
  id: 'highlight-$zIndex',
  zIndex: zIndex,
  opacity: opacity,
  data: const HighlightData(),
);

ElementState _filter(int zIndex, {double opacity = 1}) => _element(
  id: 'filter-$zIndex',
  zIndex: zIndex,
  opacity: opacity,
  data: const FilterData(),
);

ElementState _element({
  required String id,
  required int zIndex,
  required double opacity,
  required ElementData data,
}) => ElementState(
  id: id,
  rect: _defaultRect,
  rotation: 0,
  opacity: opacity,
  zIndex: zIndex,
  data: data,
);
