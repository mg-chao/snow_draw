import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('melos architecture script runs required guard steps in order', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    const orderedCommands = <String>[
      'check:architecture:',
      'dart test packages/snow_draw_core/test/melos_architecture_script_wiring_test.dart',
      'dart run melos run check:core-purity',
      'dart run melos run check:backend-legacy',
      'dart run melos run check:backend-entrypoint',
      'dart run melos run check:ci-workflow',
      'dart run melos run check:app-backend-import-boundary',
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
