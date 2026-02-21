import 'dart:io';

const _backendLibRootPath = 'packages/snow_draw_flutter_backend/lib';

final _allowedImportPattern = RegExp(
  r"""^import\s+['"]package:snow_draw_core/snow_draw_core\.dart['"];$""",
);
final _allowedExportPattern = RegExp(
  r"""^export\s+['"]package:snow_draw_core/snow_draw_core\.dart['"];$""",
);

void main() {
  final violations = <String>[];
  final backendLibRoot = Directory(_backendLibRootPath);

  if (!backendLibRoot.existsSync()) {
    stderr.writeln('Missing backend lib root: $_backendLibRootPath');
    exitCode = 1;
    return;
  }

  final backendFiles = backendLibRoot
      .listSync(recursive: true, followLinks: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  for (final file in backendFiles) {
    final normalizedPath = file.path.replaceAll(r'\', '/');
    final lines = file.readAsLinesSync();
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
        '$normalizedPath:${index + 1}: backend files must reference core via '
        'package:snow_draw_core/snow_draw_core.dart',
      );
    }
  }

  if (backendFiles.isEmpty) {
    violations.add('$_backendLibRootPath: no Dart files found');
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend core entrypoint import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend core entrypoint import boundary check passed. Backend files '
    'import core APIs through the core entrypoint only.',
  );
}
