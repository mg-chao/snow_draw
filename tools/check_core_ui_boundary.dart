import 'dart:io';

const _coreUiRootPath = 'packages/snow_draw_core/lib/ui';

void main() {
  final uiRoot = Directory(_coreUiRootPath);
  if (!uiRoot.existsSync()) {
    stdout.writeln(
      'Core UI boundary check passed. '
      'No core UI directory found at $_coreUiRootPath.',
    );
    return;
  }

  final dartFiles = <String>[];
  for (final entity in uiRoot.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) {
      continue;
    }
    dartFiles.add(entity.path.replaceAll(r'\', '/'));
  }

  if (dartFiles.isNotEmpty) {
    dartFiles.sort();
    stderr.writeln('Core UI boundary check failed:');
    stderr.writeln(
      '  Found Dart files under $_coreUiRootPath. '
      'UI/rendering code must live in the backend package.',
    );
    for (final file in dartFiles) {
      stderr.writeln('  $file');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Core UI boundary check passed. '
    'No Dart files exist under $_coreUiRootPath.',
  );
}
