import 'dart:io';

const _appRootPath = 'apps/snow_draw';
const _allowedImport =
    "import 'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';";
const _skipDirectoryNames = <String>{'.dart_tool', 'build', '.symlinks'};

void main() {
  final appRoot = Directory(_appRootPath);
  if (!appRoot.existsSync()) {
    stderr.writeln('Missing app directory: $_appRootPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  for (final entity in appRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final normalizedPath = entity.path.replaceAll(r'\', '/');
    if (_isInsideSkippedDirectory(normalizedPath)) {
      continue;
    }
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

bool _isInsideSkippedDirectory(String normalizedPath) {
  final segments = normalizedPath.split('/');
  for (final segment in segments) {
    if (_skipDirectoryNames.contains(segment)) {
      return true;
    }
  }
  return false;
}
