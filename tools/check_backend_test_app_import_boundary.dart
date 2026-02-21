import 'dart:io';

const _backendTestPath = 'packages/snow_draw_flutter_backend/test';

void main() {
  final backendTest = Directory(_backendTestPath);
  if (!backendTest.existsSync()) {
    stderr.writeln('Missing backend test directory: $_backendTestPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  for (final entity in backendTest.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final normalizedPath = entity.path.replaceAll(r'\', '/');
    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trimLeft();
      if (!(line.startsWith('import ') || line.startsWith('export '))) {
        continue;
      }
      if (!line.contains('package:snow_draw/')) {
        continue;
      }
      violations.add(
        '$normalizedPath:${index + 1}: backend tests must not depend on app package imports',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend test/app import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend test/app import boundary check passed. '
    'Backend tests do not import app package namespaces.',
  );
}
