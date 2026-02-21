import 'dart:io';

const _scanRoots = <String>['apps', 'packages'];
const _skipDirectoryNames = <String>{'.dart_tool', 'build', '.symlinks'};
const _backendPackagePrefix = 'packages/snow_draw_flutter_backend/';
const _backendImportToken = 'package:snow_draw_flutter_backend/';
const _allowedBackendEntrypointImport =
    'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart';

void main() {
  final violations = <String>[];
  var scannedFileCount = 0;

  for (final rootPath in _scanRoots) {
    final rootDirectory = Directory(rootPath);
    if (!rootDirectory.existsSync()) {
      continue;
    }

    for (final entity in rootDirectory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) {
        continue;
      }

      final normalizedPath = entity.path.replaceAll(r'\', '/');
      if (_isInsideSkippedDirectory(normalizedPath)) {
        continue;
      }
      if (normalizedPath.startsWith(_backendPackagePrefix)) {
        continue;
      }

      scannedFileCount += 1;
      final lines = entity.readAsLinesSync();
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index].trimLeft();
        final isImport = line.startsWith('import ');
        final isExport = line.startsWith('export ');
        if (!isImport && !isExport) {
          continue;
        }
        if (!line.contains(_backendImportToken)) {
          continue;
        }
        if (line.contains(_allowedBackendEntrypointImport)) {
          continue;
        }
        violations.add(
          '$normalizedPath:${index + 1}: use $_allowedBackendEntrypointImport '
          'instead of deep $_backendImportToken* imports',
        );
      }
    }
  }

  if (scannedFileCount == 0) {
    stderr.writeln('No Dart files scanned under: ${_scanRoots.join(', ')}');
    exitCode = 1;
    return;
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Workspace backend deep import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Workspace backend deep import boundary check passed. '
    'No non-backend package uses deep $_backendImportToken* imports.',
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
