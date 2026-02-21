import 'dart:io';

const _targetFiles = <String>[
  'packages/snow_draw_flutter_backend/test/built_in_element_visuals_test.dart',
  'packages/snow_draw_flutter_backend/test/built_in_element_visual_icons_compatibility_test.dart',
  'packages/snow_draw_flutter_backend/test/backend_entrypoint_contract_test.dart',
  'packages/snow_draw_flutter_backend/test/built_in_scene_encoder_routing_test.dart',
  'packages/snow_draw_flutter_backend/test/coordinate_service_offset_extensions_test.dart',
];

final _allowedImportPattern = RegExp(
  r"""^import\s+['"]package:snow_draw_core/snow_draw_core\.dart['"];$""",
);
final _allowedExportPattern = RegExp(
  r"""^export\s+['"]package:snow_draw_core/snow_draw_core\.dart['"];$""",
);

void main() {
  final violations = <String>[];
  for (final targetPath in _targetFiles) {
    final file = File(targetPath);
    if (!file.existsSync()) {
      violations.add('$targetPath: missing compatibility test file');
      continue;
    }

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
        '$targetPath:${index + 1}: backend compatibility tests must '
        'reference core via package:snow_draw_core/snow_draw_core.dart',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend compatibility core import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend compatibility core import boundary check passed. '
    'Compatibility tests import core APIs through the core entrypoint only.',
  );
}
