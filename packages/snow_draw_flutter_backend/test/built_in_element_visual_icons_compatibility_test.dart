import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_flutter_backend/visual/built_in_element_visuals.dart';

void main() {
  group('built-in visual icon compatibility', () {
    test('type id to icon mapping stays stable', () {
      final registry = createDefaultElementVisualRegistry();

      const expectedIcons = <String, IconData>{
        'rectangle': Icons.rectangle_outlined,
        'arrow': Icons.arrow_right_alt,
        'line': Icons.show_chart,
        'free_draw': Icons.brush_outlined,
        'filter': Icons.auto_fix_high,
        'highlight': Icons.highlight,
        'text': Icons.text_fields,
        'serial_number': Icons.looks_one_outlined,
      };

      for (final entry in expectedIcons.entries) {
        final typeId = entry.key;
        final expectedIcon = entry.value;
        final visual = registry.getDefinitionByValue(typeId);

        expect(
          visual,
          isNotNull,
          reason: 'Missing visual metadata for element type $typeId',
        );
        expect(
          visual!.icon,
          equals(expectedIcon),
          reason: 'Icon mapping changed for element type $typeId',
        );
      }
    });
  });
}
