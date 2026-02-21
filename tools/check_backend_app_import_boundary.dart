import 'dart:io';

const _backendLibPath = 'packages/snow_draw_flutter_backend/lib';

void main() {
  final backendLib = Directory(_backendLibPath);
  if (!backendLib.existsSync()) {
    stderr.writeln('Missing backend library directory: $_backendLibPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  for (final entity in backendLib.listSync(recursive: true)) {
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
        '$normalizedPath:${index + 1}: backend must not depend on app package imports',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend/app import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend/app import boundary check passed. '
    'Backend does not import app package namespaces.',
  );
}
