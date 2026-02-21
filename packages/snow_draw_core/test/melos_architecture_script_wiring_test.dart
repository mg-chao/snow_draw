import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('melos architecture script runs required guard steps in order', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    const orderedCommands = <String>[
      'check:architecture:',
      'dart test packages/snow_draw_core/test/melos_architecture_script_wiring_test.dart',
      'dart run melos run check:core-purity',
      'dart run melos run check:core-ui-boundary',
      'dart run melos run check:backend-legacy',
      'dart run melos run check:backend-app-import-boundary',
      'dart run melos run check:backend-pubspec-boundary',
      'dart run melos run check:backend-entrypoint',
      'dart run melos run check:ci-workflow',
      'dart run melos run check:app-backend-import-boundary',
      'dart run melos run check:app-pubspec-backend',
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

    const orderedCorePurityChecks = <String>[
      'check:core-purity:',
      'dart run tools/check_core_import_purity.dart',
      'dart run tools/check_core_pubspec_purity.dart',
      'dart run tools/check_core_dependency_graph_purity.dart',
    ];

    var corePurityLastIndex = -1;
    for (final check in orderedCorePurityChecks) {
      final index = pubspec.indexOf(check);
      expect(
        index,
        greaterThan(corePurityLastIndex),
        reason: 'Expected core purity check in order: $check',
      );
      corePurityLastIndex = index;
    }

    expect(pubspec, contains('check:core-ui-boundary:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_core_ui_boundary.dart'),
    );
    expect(pubspec, contains('check:backend-app-import-boundary:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_backend_app_import_boundary.dart'),
    );
    expect(pubspec, contains('check:backend-pubspec-boundary:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_backend_pubspec_boundary.dart'),
    );
    expect(pubspec, contains('check:core-purity:'));
    expect(pubspec, contains('tools/check_core_dependency_graph_purity.dart'));
    expect(pubspec, contains('check:ci-workflow:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_ci_workflow_guards.dart'),
    );
    expect(pubspec, contains('check:app-pubspec-backend:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_app_pubspec_backend_dependency.dart'),
    );
  });
}
