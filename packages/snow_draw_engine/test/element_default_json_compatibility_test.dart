import 'package:snow_draw_engine/draw/elements/core/element_registry.dart';
import 'package:snow_draw_engine/draw/elements/registration.dart';
import 'package:test/test.dart';

void main() {
  group('built-in default JSON compatibility', () {
    test('default element payloads stay stable', () {
      final registry = DefaultElementRegistry();
      registerBuiltInElements(registry);

      for (final entry in _expectedDefaultJson.entries) {
        final typeId = entry.key;
        final expectedJson = entry.value;
        final definition = registry.getDefinitionByValue(typeId);

        expect(definition, isNotNull, reason: 'Missing definition for $typeId');

        final created = definition!.createDefaultData();
        expect(
          created.toJson(),
          equals(expectedJson),
          reason: '$typeId default toJson payload changed unexpectedly',
        );

        final decoded = definition.fromJson(
          Map<String, dynamic>.from(expectedJson),
        );
        expect(
          decoded.toJson(),
          equals(expectedJson),
          reason: '$typeId fromJson compatibility changed unexpectedly',
        );
      }
    });
  });
}

const _expectedDefaultJson = <String, Map<String, dynamic>>{
  'rectangle': {
    'typeId': 'rectangle',
    'cornerRadius': 4.0,
    'fillColor': 0x00000000,
    'color': 0xFF1E1E1E,
    'strokeWidth': 2.0,
    'strokeStyle': 'solid',
    'fillStyle': 'solid',
  },
  'arrow': {
    'typeId': 'arrow',
    'points': [
      {'x': 0.0, 'y': 0.0},
      {'x': 1.0, 'y': 1.0},
    ],
    'color': 0xFF1E1E1E,
    'strokeWidth': 2.0,
    'strokeStyle': 'solid',
    'arrowType': 'straight',
    'startArrowhead': 'none',
    'endArrowhead': 'standard',
    'startBinding': null,
    'endBinding': null,
    'fixedSegments': null,
    'startIsSpecial': null,
    'endIsSpecial': null,
  },
  'line': {
    'typeId': 'line',
    'points': [
      {'x': 0.0, 'y': 0.0},
      {'x': 1.0, 'y': 1.0},
    ],
    'color': 0xFF1E1E1E,
    'fillColor': 0x00000000,
    'strokeWidth': 2.0,
    'strokeStyle': 'solid',
    'fillStyle': 'solid',
    'arrowType': 'curved',
    'startArrowhead': 'none',
    'endArrowhead': 'none',
    'startBinding': null,
    'endBinding': null,
    'fixedSegments': null,
    'startIsSpecial': null,
    'endIsSpecial': null,
  },
  'free_draw': {
    'typeId': 'free_draw',
    'points': [
      {'x': 0.0, 'y': 0.0},
      {'x': 1.0, 'y': 1.0},
    ],
    'color': 0xFF1E1E1E,
    'fillColor': 0x00000000,
    'strokeWidth': 2.0,
    'strokeStyle': 'solid',
    'fillStyle': 'solid',
  },
  'filter': {'typeId': 'filter', 'type': 'mosaic', 'strength': 0.5},
  'highlight': {
    'typeId': 'highlight',
    'shape': 'rectangle',
    'color': 0xFFF5222D,
    'strokeColor': 0xFF000000,
    'strokeWidth': 0.0,
  },
  'text': {
    'typeId': 'text',
    'text': '',
    'color': 0xFF1E1E1E,
    'fontSize': 21.0,
    'fontFamily': '',
    'horizontalAlign': 'left',
    'verticalAlign': 'center',
    'fillColor': 0x00000000,
    'fillStyle': 'solid',
    'strokeColor': 0xFFF8F4EC,
    'strokeWidth': 0.0,
    'cornerRadius': 0.0,
    'autoResize': true,
  },
  'serial_number': {
    'typeId': 'serial_number',
    'number': 1,
    'color': 0xFF1E1E1E,
    'fillColor': 0x00000000,
    'fillStyle': 'solid',
    'fontSize': 16.0,
    'fontFamily': '',
    'strokeWidth': 2.0,
    'strokeStyle': 'solid',
    'textElementId': '',
  },
};
