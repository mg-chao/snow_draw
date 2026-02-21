import 'dart:io';

const _appSourceRoots = <String>['apps/snow_draw/lib', 'apps/snow_draw/test'];
const _allowedImport =
    "import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';";

void main() {
  final roots = <Directory>[];
  for (final path in _appSourceRoots) {
    final root = Directory(path);
    if (!root.existsSync()) {
      stderr.writeln('Missing app source directory: $path');
      exitCode = 1;
      return;
    }
    roots.add(root);
  }

  final violations = <String>[];
  for (final root in roots) {
    for (final entity in root.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }
      final normalizedPath = entity.path.replaceAll(r'\', '/');
      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trimLeft();
        if (!line.startsWith('import ')) {
          continue;
        }
        if (!line.contains('package:snow_draw_flutter_backend/')) {
          continue;
        }
        if (line == _allowedImport) {
          continue;
        }
        violations.add(
          '$normalizedPath:${index + 1}: app must import backend via '
          'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart',
        );
      }
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('App/backend import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'App/backend import boundary check passed. '
    'App imports backend through the package entrypoint only.',
  );
}
