import 'dart:io';

const _appPubspecPath = 'apps/snow_draw/pubspec.yaml';

void main() {
  final pubspecFile = File(_appPubspecPath);
  if (!pubspecFile.existsSync()) {
    stderr.writeln('Missing app pubspec: $_appPubspecPath');
    exitCode = 1;
    return;
  }

  final lines = pubspecFile.readAsLinesSync();
  final violations = <String>[];
  String? currentSection;
  var hasCoreDependency = false;
  var hasBackendDependency = false;

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

    if (currentSection == 'dependencies') {
      if (trimmed.startsWith('snow_draw_core:')) {
        hasCoreDependency = true;
      }
      if (trimmed.startsWith('snow_draw_flutter_backend:')) {
        hasBackendDependency = true;
      }
      continue;
    }

    if (currentSection == 'dependency_overrides') {
      if (trimmed.startsWith('snow_draw_flutter_backend:')) {
        violations.add(
          '$_appPubspecPath:$lineNumber: dependency_overrides for '
          'snow_draw_flutter_backend are not allowed',
        );
      }
      if (trimmed.startsWith('snow_draw_core:')) {
        violations.add(
          '$_appPubspecPath:$lineNumber: dependency_overrides for '
          'snow_draw_core are not allowed',
        );
      }
    }
  }

  if (!hasCoreDependency) {
    violations.add(
      '$_appPubspecPath: missing required dependencies.snow_draw_core entry',
    );
  }
  if (!hasBackendDependency) {
    violations.add(
      '$_appPubspecPath: missing required '
      'dependencies.snow_draw_flutter_backend entry',
    );
  }

  if (violations.isNotEmpty) {
    stderr.writeln('App pubspec backend dependency check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'App pubspec backend dependency check passed. '
    'App declares required core/backend dependencies without core/backend '
    'overrides.',
  );
}
