import 'dart:io';

import 'package:test/test.dart';

String _readWorkspacePubspec() {
  const candidatePaths = <String>[
    'pubspec.yaml',
    '../../pubspec.yaml',
    '../pubspec.yaml',
  ];

  for (final path in candidatePaths) {
    final file = File(path);
    if (!file.existsSync()) {
      continue;
    }
    final content = file.readAsStringSync();
    final isWorkspacePubspec =
        content.contains('melos:') && content.contains('scripts:');
    if (isWorkspacePubspec) {
      return content;
    }
  }

  throw StateError(
    'Unable to locate workspace pubspec.yaml from ${Directory.current.path}.',
  );
}

void main() {
  test('melos compatibility script runs required contract tests in order', () {
    final pubspec = _readWorkspacePubspec();

    const orderedCommands = <String>[
      'check:compatibility-contracts:',
      'dart test packages/snow_draw_core/test/melos_compatibility_script_wiring_test.dart',
      'dart test packages/snow_draw_core/test/engine_entrypoint_contract_test.dart',
      'dart test packages/snow_draw_core/test/element_serialization_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_default_json_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_type_id_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/element_registry_characterization_test.dart',
      'dart test packages/snow_draw_core/test/built_in_render_task_support_test.dart',
      'dart test packages/snow_draw_core/test/draw_config_defaults_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/action_payload_immutability_test.dart',
      'dart test packages/snow_draw_core/test/action_type_name_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/types/draw_color_test.dart',
      'dart test packages/snow_draw_core/test/text_metrics_service_compatibility_test.dart',
      'dart test packages/snow_draw_core/test/draw_context_text_metrics_compatibility_test.dart',
      'dart run melos run check:backend-compatibility-engine-import-boundary',
      'dart run melos run check:backend-compatibility-backend-import-boundary',
      'flutter test packages/snow_draw_flutter_backend/test/backend_entrypoint_contract_test.dart',
      'packages/snow_draw_flutter_backend/test/built_in_render_task_routing_test.dart',
      'packages/snow_draw_flutter_backend/test/coordinate_service_offset_extensions_test.dart',
    ];

    var lastIndex = -1;
    for (final command in orderedCommands) {
      final index = pubspec.indexOf(command, lastIndex + 1);
      expect(
        index,
        greaterThan(lastIndex),
        reason: 'Expected command in order: $command',
      );
      lastIndex = index;
    }

    final backendFlutterInvocationCount = RegExp(
      'flutter test packages/snow_draw_flutter_backend/test/',
    ).allMatches(pubspec).length;
    expect(
      backendFlutterInvocationCount,
      1,
      reason:
          'Expected a single backend flutter test invocation '
          'in compatibility checks',
    );
  });
}
