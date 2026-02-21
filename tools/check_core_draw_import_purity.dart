import 'dart:io';

const _allowlistPath = 'tools/core_draw_purity_allowlist.txt';
const _scanRootPath = 'packages/snow_draw_core/lib';

void main() {
  final root = Directory(_scanRootPath);
  if (!root.existsSync()) {
    stderr.writeln('Missing scan root: $_scanRootPath');
    exitCode = 1;
    return;
  }

  final allowlistFile = File(_allowlistPath);
  if (!allowlistFile.existsSync()) {
    stderr.writeln('Missing allowlist file: $_allowlistPath');
    stderr.writeln(
      'Create it with one entry per line: '
      'path:line:dart:ui|path:line:package:flutter',
    );
    exitCode = 1;
    return;
  }

  final allowlist = _readAllowlist(allowlistFile);
  final violations = _scanViolations(root);

  final newViolations = violations.difference(allowlist).toList()..sort();
  final staleAllowlist = allowlist.difference(violations).toList()..sort();

  if (newViolations.isNotEmpty) {
    stderr.writeln(
      'Found new Flutter/UI imports in $_scanRootPath '
      '(not present in $_allowlistPath):',
    );
    for (final entry in newViolations) {
      stderr.writeln('  $entry');
    }
    stderr.writeln('');
    stderr.writeln(
      'If this is intentional during migration, add entries to $_allowlistPath.',
    );
    exitCode = 1;
    return;
  }

  if (staleAllowlist.isNotEmpty) {
    stdout.writeln('Allowlist entries no longer needed (cleanup suggested):');
    for (final entry in staleAllowlist) {
      stdout.writeln('  $entry');
    }
  }

  stdout.writeln(
    'Core import purity check passed. '
    '${violations.length} baseline entries tracked.',
  );
}

Set<String> _readAllowlist(File file) {
  final entries = <String>{};
  for (final rawLine in file.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.isEmpty || line.startsWith('#')) {
      continue;
    }
    entries.add(line);
  }
  return entries;
}

Set<String> _scanViolations(Directory root) {
  final violations = <String>{};

  for (final entity in root.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    final relativePath = entity.path.replaceAll(r'\', '/');
    final lines = entity.readAsLinesSync();
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      final dependency = _matchDependency(line);
      if (dependency == null) {
        continue;
      }
      violations.add('$relativePath:${index + 1}:$dependency');
    }
  }
  return violations;
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
