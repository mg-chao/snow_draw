import 'dart:io';

const _backendRootPath = 'packages/snow_draw_flutter_backend';
const _backendLibPath = 'packages/snow_draw_flutter_backend/lib';
const _legacyPath = 'packages/snow_draw_flutter_backend/lib/render/legacy';

void main() {
  final backendRoot = Directory(_backendRootPath);
  if (!backendRoot.existsSync()) {
    stderr.writeln('Missing backend package: $_backendRootPath');
    exitCode = 1;
    return;
  }

  final legacyDir = Directory(_legacyPath);
  if (!legacyDir.existsSync()) {
    stderr.writeln('Missing legacy render directory: $_legacyPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[
    ..._scanLegacyImports(backendRoot),
    ..._scanLegacyShimShape(legacyDir),
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
    'No internal legacy imports and legacy files are shim-only.',
  );
}

List<String> _scanLegacyImports(Directory backendRoot) {
  final violations = <String>[];

  for (final entity in backendRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }

    final normalizedPath = entity.path.replaceAll(r'\', '/');
    if (normalizedPath.startsWith(_legacyPath)) {
      continue;
    }

    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index].trimLeft();
      if (!_isDirectiveLine(line)) {
        continue;
      }
      if (line.contains('/render/legacy/') || line.contains('../legacy/')) {
        violations.add(
          '$normalizedPath:${index + 1}: '
          'legacy import/export is not allowed outside $_legacyPath',
        );
      }
    }
  }

  return violations;
}

List<String> _scanLegacyShimShape(Directory legacyDir) {
  final violations = <String>[];
  final files = legacyDir
      .listSync(recursive: false)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .toList(growable: false);

  for (final file in files) {
    final normalizedPath = file.path.replaceAll(r'\', '/');
    final lines = file.readAsLinesSync();
    final meaningful = lines
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty && !line.startsWith('//'))
        .toList(growable: false);

    final exportLines = meaningful
        .where((line) => line.startsWith('export '))
        .toList(growable: false);
    if (exportLines.length != 1) {
      violations.add(
        '$normalizedPath: expected exactly one export directive, found '
        '${exportLines.length}',
      );
      continue;
    }

    final exportLine = exportLines.single;
    if (!exportLine.contains("export '../") || !exportLine.endsWith("';")) {
      violations.add(
        '$normalizedPath: export must target canonical sibling namespace',
      );
    }

    final hasDeprecated = meaningful.any(
      (line) => line.startsWith('@Deprecated('),
    );
    if (!hasDeprecated) {
      violations.add(
        '$normalizedPath: legacy shim must include a @Deprecated annotation',
      );
    }

    final hasLibraryDirective = meaningful.any((line) => line == 'library;');
    if (!hasLibraryDirective) {
      violations.add('$normalizedPath: legacy shim must declare `library;`');
    }

    final bodyTokens = <String>[
      'class ',
      'enum ',
      'mixin ',
      'extension ',
      'typedef ',
      'void ',
      'final class',
    ];
    for (var index = 0; index < lines.length; index++) {
      final sourceLine = lines[index];
      final trimmed = sourceLine.trimLeft();
      if (!_looksLikeCode(trimmed)) {
        continue;
      }
      for (final token in bodyTokens) {
        if (trimmed.contains(token)) {
          violations.add(
            '$normalizedPath:${index + 1}: legacy file must be shim-only, '
            'found "$token"',
          );
          break;
        }
      }
    }
  }

  return violations;
}

bool _isDirectiveLine(String line) =>
    line.startsWith('import ') || line.startsWith('export ');

bool _looksLikeCode(String line) {
  if (line.isEmpty || line.startsWith('//')) {
    return false;
  }
  if (line.startsWith('@')) {
    return false;
  }
  if (_isDirectiveLine(line) || line.startsWith('library')) {
    return false;
  }
  return true;
}
