import 'dart:io';

const _compatibilityTests = <String>[
  'packages/snow_draw_flutter_backend/test/backend_entrypoint_contract_test.dart',
  'packages/snow_draw_flutter_backend/test/built_in_render_task_routing_test.dart',
  'packages/snow_draw_flutter_backend/test/coordinate_service_offset_extensions_test.dart',
];

const _allowedBackendImport =
    'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';
final _importPattern = RegExp(r"^\s*import\s+'([^']+)';");

void main() {
  final violations = <String>[];

  for (final testPath in _compatibilityTests) {
    final file = File(testPath);
    if (!file.existsSync()) {
      violations.add('$testPath: missing compatibility test file');
      continue;
    }

    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final match = _importPattern.firstMatch(lines[index]);
      if (match == null) {
        continue;
      }
      final importTarget = match.group(1);
      if (importTarget == null ||
          !importTarget.startsWith('package:snow_draw_flutter_backend/')) {
        continue;
      }
      if (importTarget != _allowedBackendImport) {
        violations.add(
          '$testPath:${index + 1} imports "$importTarget" '
          '(expected "$_allowedBackendImport")',
        );
      }
    }
  }

  if (violations.isEmpty) {
    stdout.writeln(
      'Backend compatibility tests use only the backend entrypoint import.',
    );
    return;
  }

  stderr.writeln('Backend import boundary violations detected:');
  for (final violation in violations) {
    stderr.writeln(' - $violation');
  }
  exitCode = 1;
}
