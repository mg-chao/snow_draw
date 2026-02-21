import 'dart:io';

const _corePubspecPath = 'packages/snow_draw_core/pubspec.yaml';

void main() {
  final file = File(_corePubspecPath);
  if (!file.existsSync()) {
    stderr.writeln('Missing core pubspec: $_corePubspecPath');
    exitCode = 1;
    return;
  }

  final lines = file.readAsLinesSync();
  final violations = <String>[];
  String? section;

  for (var index = 0; index < lines.length; index++) {
    final lineNumber = index + 1;
    final line = lines[index];
    final trimmed = line.trim();

    if (trimmed.isEmpty || trimmed.startsWith('#')) {
      continue;
    }

    final isTopLevel = line.isNotEmpty && !line.startsWith(' ');
    if (isTopLevel) {
      section = trimmed.endsWith(':')
          ? trimmed.substring(0, trimmed.length - 1)
          : null;
      continue;
    }

    if (section == 'environment' && trimmed.startsWith('flutter:')) {
      violations.add(
        '$_corePubspecPath:$lineNumber: environment.flutter is not allowed',
      );
      continue;
    }

    if (section == 'dependencies' && trimmed.startsWith('flutter:')) {
      violations.add(
        '$_corePubspecPath:$lineNumber: dependencies.flutter is not allowed',
      );
      continue;
    }

    if (section == 'dev_dependencies' &&
        (trimmed.startsWith('flutter:') ||
            trimmed.startsWith('flutter_test:'))) {
      violations.add(
        '$_corePubspecPath:$lineNumber: Flutter dev dependency is not allowed',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Core pubspec purity check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln('Core pubspec purity check passed.');
}
