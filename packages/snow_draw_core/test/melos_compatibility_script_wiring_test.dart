import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('melos compatibility script runs required contract tests in order', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    const orderedCommands = <String>[
      'check:compatibility-contracts:',
      'dart test packages/snow_draw_core/test/melos_compatibility_script_wiring_test.dart',
      'dart test packages/snow_draw_core/test/core_entrypoint_contract_test.dart',
      'dart test packages/snow_draw_core/test/element_serialization_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_default_json_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_type_id_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_registry_characterization_test.dart',
      'dart test packages/snow_draw_core/test/draw_config_defaults_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/action_payload_immutability_test.dart',
      'dart test packages/snow_draw_core/test/types/draw_color_test.dart',
      'dart test packages/snow_draw_core/test/text_metrics_service_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/draw_context_text_metrics_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/scene_encoder_slice_a_test.dart',
      'packages/snow_draw_core/test/scene_encoder_slice_b_test.dart',
      'packages/snow_draw_core/test/scene_encoder_slice_c_test.dart',
      'packages/snow_draw_core/test/scene_encoder_slice_d_test.dart',
      'dart run melos run check:backend-compatibility-core-import-boundary',
      'dart run melos run check:backend-compatibility-backend-import-boundary',
      'flutter test packages/snow_draw_flutter_backend/test/built_in_element_visuals_test.dart',
      'packages/snow_draw_flutter_backend/test/built_in_element_visual_icons_compatibility_test.dart',
      'packages/snow_draw_flutter_backend/test/backend_entrypoint_contract_test.dart',
      'packages/snow_draw_flutter_backend/test/built_in_scene_encoder_routing_test.dart',
      'packages/snow_draw_flutter_backend/test/coordinate_service_offset_extensions_test.dart',
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

    final backendFlutterInvocationCount = RegExp(
      r'flutter test packages/snow_draw_flutter_backend/test/',
    ).allMatches(pubspec).length;
    expect(
      backendFlutterInvocationCount,
      1,
      reason:
          'Expected a single backend flutter test invocation in compatibility checks',
    );
  });
}
