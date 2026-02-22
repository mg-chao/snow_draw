import 'dart:io';

const _backendTestRootPath = 'packages/snow_draw_flutter_backend/test';
const _compatibilityBasenames = <String>{
  'built_in_scene_encoder_routing_test.dart',
  'coordinate_service_offset_extensions_test.dart',
};

final _allowedImportPattern = RegExp(
  r"""^import\s+['"]package:snow_draw_flutter_backend/snow_draw_flutter_backend\.dart['"];$""",
);
final _allowedExportPattern = RegExp(
  r"""^export\s+['"]package:snow_draw_flutter_backend/snow_draw_flutter_backend\.dart['"];$""",
);

void main() {
  final backendTestRoot = Directory(_backendTestRootPath);
  if (!backendTestRoot.existsSync()) {
    stderr.writeln('Missing backend test directory: $_backendTestRootPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  final targetFiles = backendTestRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) {
        final normalizedPath = file.path.replaceAll(r'\', '/');
        final basename = _basename(normalizedPath);
        return basename.endsWith('_compatibility_test.dart') ||
            basename.endsWith('_contract_test.dart') ||
            _compatibilityBasenames.contains(basename);
      })
      .toList(growable: false);

  for (final file in targetFiles) {
    final normalizedPath = file.path.replaceAll(r'\', '/');
    final lines = file.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trimLeft();
      final isImport = line.startsWith('import ');
      final isExport = line.startsWith('export ');
      if (!isImport && !isExport) {
        continue;
      }
      if (!line.contains('package:snow_draw_flutter_backend/')) {
        continue;
      }
      if ((isImport && _allowedImportPattern.hasMatch(line)) ||
          (isExport && _allowedExportPattern.hasMatch(line))) {
        continue;
      }

      violations.add(
        '$normalizedPath:${index + 1}: backend compatibility tests must '
        'reference backend via '
        'package:snow_draw_flutter_backend/snow_draw_flutter_backend.dart',
      );
    }
  }

  if (targetFiles.isEmpty) {
    violations.add('$_backendTestRootPath: no compatibility test files found');
  }

  if (violations.isNotEmpty) {
    stderr.writeln(
      'Backend compatibility backend import boundary check failed:',
    );
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend compatibility backend import boundary check passed. '
    'Compatibility tests import backend APIs through the backend '
    'entrypoint only.',
  );
}

String _basename(String normalizedPath) {
  final slashIndex = normalizedPath.lastIndexOf('/');
  if (slashIndex == -1) {
    return normalizedPath;
  }
  return normalizedPath.substring(slashIndex + 1);
}
