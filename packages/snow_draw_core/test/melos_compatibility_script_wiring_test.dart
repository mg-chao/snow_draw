import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('melos compatibility script includes required contract tests', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('check:compatibility-contracts:'));
    expect(
      pubspec,
      contains(
        'packages/snow_draw_core/test/element_serialization_compatibility_test.dart',
      ),
    );
    expect(
      pubspec,
      contains(
        'packages/snow_draw_core/test/element_default_json_compatibility_test.dart',
      ),
    );
    expect(
      pubspec,
      contains(
        'packages/snow_draw_core/test/element_type_id_compatibility_test.dart',
      ),
    );
    expect(
      pubspec,
      contains(
        'packages/snow_draw_flutter_backend/test/built_in_element_visuals_test.dart',
      ),
    );
    expect(
      pubspec,
      contains(
        'packages/snow_draw_flutter_backend/test/built_in_element_visual_icons_compatibility_test.dart',
      ),
    );
    expect(
      pubspec,
      contains(
        'packages/snow_draw_flutter_backend/test/backend_entrypoint_contract_test.dart',
      ),
    );
    expect(
      pubspec,
      contains(
        'packages/snow_draw_flutter_backend/test/built_in_scene_encoder_routing_test.dart',
      ),
    );
  });
}
