import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('melos compatibility script runs required contract tests in order', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    const orderedCommands = <String>[
      'check:compatibility-contracts:',
      'dart test packages/snow_draw_core/test/melos_compatibility_script_wiring_test.dart',
      'dart test packages/snow_draw_core/test/element_serialization_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_default_json_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_type_id_compatibility_test.dart',
      'flutter test packages/snow_draw_flutter_backend/test/built_in_element_visuals_test.dart',
      'packages/snow_draw_flutter_backend/test/built_in_element_visual_icons_compatibility_test.dart',
      'packages/snow_draw_flutter_backend/test/backend_entrypoint_contract_test.dart',
      'packages/snow_draw_flutter_backend/test/built_in_scene_encoder_routing_test.dart',
    ];

    var lastIndex = -1;
    for (final command in orderedCommands) {
      final index = pubspec.indexOf(command);
      expect(
        index,
        greaterThan(lastIndex),
        reason: 'Expected command in order: $command',
      );
      lastIndex = index;
    }
  });
}
