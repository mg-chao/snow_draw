import 'dart:io';

const _backendPubspecPath = 'packages/snow_draw_flutter_backend/pubspec.yaml';
const _forbiddenPackageName = 'snow_draw';
const _requiredCorePackageName = 'snow_draw_core';

void main() {
  final pubspecFile = File(_backendPubspecPath);
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Missing backend pubspec: $_backendPubspecPath');
    exitCode = 1;
    return;
  }

  final lines = pubspecFile.readAsLinesSync();
  final violations = <String>[];
  String? currentSection;
  var hasCoreDependency = false;

  for (var index = 0; index < lines.length; index++) {
    final lineNumber = index + 1;
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    final isTopLevel = line.isNotEmpty && !line.startsWith(' ');
    if (isTopLevel) {
      currentSection = trimmed.endsWith(':')
          ? trimmed.substring(0, trimmed.length - 1)
          : null;
      continue;
    }

    if (!_isDependencySection(currentSection)) {
      continue;
    }

    if (currentSection == 'dependencies' &&
        trimmed.startsWith('$_requiredCorePackageName:')) {
      hasCoreDependency = true;
    }

    if (!trimmed.startsWith('$_forbiddenPackageName:')) {
      continue;
    }
    violations.add(
      '$_backendPubspecPath:$lineNumber: '
      'backend package must not depend on $_forbiddenPackageName',
    );
  }

  if (!hasCoreDependency) {
    violations.add(
      '$_backendPubspecPath: missing required dependencies.'
      '$_requiredCorePackageName entry',
    );
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend pubspec boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend pubspec boundary check passed. '
    'No app package dependencies are declared and core dependency is present.',
  );
}

bool _isDependencySection(String? section) =>
    section == 'dependencies' ||
    section == 'dev_dependencies' ||
    section == 'dependency_overrides';
