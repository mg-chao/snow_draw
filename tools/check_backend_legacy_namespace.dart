import 'dart:io';

const _backendRootPath = 'packages/snow_draw_flutter_backend';
const _legacyPath = 'packages/snow_draw_flutter_backend/lib/render/legacy';

void main() {
  final backendRoot = Directory(_backendRootPath);
  if (!backendRoot.existsSync()) {
    stderr.writeln('Missing backend package: $_backendRootPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[
    ..._scanLegacyImports(backendRoot),
    ..._scanLegacySourceFiles(),
  ];
  if (violations.isNotEmpty) {
    stderr.writeln('Backend legacy namespace guard failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend legacy namespace guard passed. '
    'Legacy imports are blocked and no legacy Dart sources remain.',
  );
}

List<String> _scanLegacyImports(Directory backendRoot) {
  final violations = <String>[];
  for (final entity in backendRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final normalizedPath = entity.path.replaceAll(r'\', '/');
    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index += 1) {
      final line = lines[index].trimLeft();
      if (!_isDirectiveLine(line)) {
        continue;
      }
      if (line.contains('/render/legacy/') || line.contains('../legacy/')) {
        violations.add(
          '$normalizedPath:${index + 1}: '
          'legacy import/export is not allowed',
        );
      }
    }
  }
  return violations;
}

List<String> _scanLegacySourceFiles() {
  final legacyDir = Directory(_legacyPath);
  if (!legacyDir.existsSync()) {
    return const <String>[];
  }

  return legacyDir
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .map(
        (file) =>
            '${file.path.replaceAll(r'\', '/')} '
            'legacy Dart source should be removed',
      )
      .toList(growable: false);
}

bool _isDirectiveLine(String line) =>
    line.startsWith('import ') || line.startsWith('export ');
