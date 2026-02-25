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
  test('melos architecture script runs required guard steps in order', () {
    final pubspec = _readWorkspacePubspec();

    const orderedCommands = <String>[
      'check:architecture:',
      'dart test packages/snow_draw_core/test/melos_architecture_script_wiring_test.dart',
      'dart run melos run check:core-purity',
      'dart run melos run check:core-draw-purity',
      'dart run melos run check:core-ui-boundary',
      'dart run melos run check:core-entrypoint',
      'dart run melos run check:workspace-core-deep-import-boundary',
      'dart run melos run check:workspace-backend-deep-import-boundary',
      'dart run melos run check:backend-legacy',
      'dart run melos run check:backend-app-import-boundary',
      'dart run melos run check:backend-test-app-import-boundary',
      'dart run melos run check:backend-pubspec-boundary',
      'dart run melos run check:backend-dependency-graph',
      'dart run melos run check:backend-core-entrypoint-import-boundary',
      'dart run melos run check:backend-test-core-entrypoint-import-boundary',
      'dart run melos run check:backend-entrypoint',
      'dart run melos run check:ci-workflow',
      'dart run melos run check:app-backend-import-boundary',
      'dart run melos run check:app-core-import-boundary',
      'dart run melos run check:app-pubspec-backend',
      'dart run melos run check:app-dependency-graph',
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
    expect(pubspec, contains('check:core-draw-purity:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_core_draw_import_purity.dart'),
    );
    expect(pubspec, contains('check:core-entrypoint:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_core_entrypoint_exports.dart'),
    );
    expect(pubspec, contains('check:workspace-core-deep-import-boundary:'));
    expect(
      pubspec,
      contains(
        'run: dart run tools/check_workspace_core_deep_import_boundary.dart',
      ),
    );
    expect(pubspec, contains('check:workspace-backend-deep-import-boundary:'));
    expect(
      pubspec,
      contains(
        'run: dart run tools/check_workspace_backend_deep_import_boundary.dart',
      ),
    );
    expect(pubspec, contains('check:backend-app-import-boundary:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_backend_app_import_boundary.dart'),
    );
    expect(pubspec, contains('check:backend-test-app-import-boundary:'));
    expect(
      pubspec,
      contains(
        'run: dart run tools/check_backend_test_app_import_boundary.dart',
      ),
    );
    expect(pubspec, contains('check:backend-pubspec-boundary:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_backend_pubspec_boundary.dart'),
    );
    expect(pubspec, contains('check:backend-dependency-graph:'));
    expect(
      pubspec,
      contains(
        'run: dart run tools/check_backend_dependency_graph_boundary.dart',
      ),
    );
    expect(pubspec, contains('check:backend-core-entrypoint-import-boundary:'));
    expect(
      pubspec,
      contains(
        'run: dart run tools/check_backend_core_entrypoint_import_boundary.dart',
      ),
    );
    expect(
      pubspec,
      contains('check:backend-test-core-entrypoint-import-boundary:'),
    );
    expect(
      pubspec,
      contains(
        'run: dart run '
        'tools/check_backend_test_core_entrypoint_import_boundary.dart',
      ),
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
    expect(pubspec, contains('check:app-core-import-boundary:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_app_core_import_boundary.dart'),
    );
    expect(pubspec, contains('check:app-dependency-graph:'));
    expect(
      pubspec,
      contains('run: dart run tools/check_app_dependency_graph_boundary.dart'),
    );
  });
}
