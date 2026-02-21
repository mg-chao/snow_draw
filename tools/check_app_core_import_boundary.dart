import 'dart:io';

const _appRootPath = 'apps/snow_draw';
const _skipDirectoryNames = <String>{'.dart_tool', 'build', '.symlinks'};
final _allowedImportPattern = RegExp(
  r"""^import\s+['"]package:snow_draw_core/snow_draw_core\.dart['"];$""",
);
final _allowedExportPattern = RegExp(
  r"""^export\s+['"]package:snow_draw_core/snow_draw_core\.dart['"];$""",
);

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
      final isImport = line.startsWith('import ');
      final isExport = line.startsWith('export ');
      if (!isImport && !isExport) {
        continue;
      }
      if (!line.contains('package:snow_draw_core/')) {
        continue;
      }
      if ((isImport && _allowedImportPattern.hasMatch(line)) ||
          (isExport && _allowedExportPattern.hasMatch(line))) {
        continue;
      }
      violations.add(
        '$normalizedPath:${index + 1}: app must reference core via '
        'package:snow_draw_core/snow_draw_core.dart',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('App/core import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'App/core import boundary check passed. '
    'App import/export references use the core package entrypoint only.',
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
