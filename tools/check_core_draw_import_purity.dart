import 'dart:io';

const _scanRootPath = 'packages/snow_draw_core/lib/draw';

void main() {
  final root = Directory(_scanRootPath);
  if (!root.existsSync()) {
    stderr.writeln('Missing core draw directory: $_scanRootPath');
    exitCode = 1;
    return;
  }

  final violations = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final normalizedPath = entity.path.replaceAll(r'\', '/');
    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final dependency = _matchDependency(lines[index]);
      if (dependency == null) {
        continue;
      }
      violations.add('$normalizedPath:${index + 1}:$dependency');
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Core draw import purity check failed:');
    stderr.writeln('  Flutter/UI imports are forbidden under $_scanRootPath.');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Core draw import purity check passed. '
    'No Flutter/UI imports found under $_scanRootPath.',
  );
}

String? _matchDependency(String line) {
  final trimmed = line.trimLeft();
  if (!(trimmed.startsWith('import ') || trimmed.startsWith('export '))) {
    return null;
  }
  if (trimmed.contains('package:flutter/')) {
    return 'package:flutter';
  }
  if (trimmed.contains("import 'dart:ui") ||
      trimmed.contains('import "dart:ui')) {
    return 'dart:ui';
  }
  return null;
}
