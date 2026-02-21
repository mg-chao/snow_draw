import 'dart:io';

const _appLibPath = 'apps/snow_draw/lib';
const _allowedImport =
    "import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';";

void main() {
  final appLib = Directory(_appLibPath);
  if (!appLib.existsSync()) {
    stderr.writeln('Missing app source directory: $_appLibPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  for (final entity in appLib.listSync(recursive: true)) {
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
