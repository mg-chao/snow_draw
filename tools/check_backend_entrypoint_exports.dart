import 'dart:io';

const _backendEntrypointPath =
    'packages/snow_draw_flutter_backend/lib/snow_draw_flutter_backend.dart';

const _requiredExports = <String>{
  'extensions/coordinate_service_offset_extensions.dart',
  'extensions/draw_color_extensions.dart',
  'render/element_renderer.dart',
  'services/font/flutter_system_font_service.dart',
  'services/text/flutter_text_metrics_service.dart',
  'services/text/flutter_text_rendering_cache_invalidation.dart',
  'ui/canvas/draw_canvas.dart',
  'ui/canvas/plugin_draw_canvas.dart',
  'visual/built_in_element_visuals.dart',
  'visual/element_visual_definition.dart',
  'visual/element_visual_registry.dart',
};

final _exportPattern = RegExp(r"""^export\s+['"](.+)['"];$""");

void main() {
  final entrypoint = File(_backendEntrypointPath);
  if (!entrypoint.existsSync()) {
    stderr.writeln('Missing backend entrypoint: $_backendEntrypointPath');
    exitCode = 1;
    return;
  }

  final exports = <String>{};
  final violations = <String>[];
  final lines = entrypoint.readAsLinesSync();
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty || line.startsWith('//')) {
      continue;
    }
    final match = _exportPattern.firstMatch(line);
    if (match == null) {
      violations.add(
        '$_backendEntrypointPath:${index + 1}: '
        'unexpected statement in backend entrypoint: "$line"',
      );
      continue;
    }

    final exportPath = match.group(1)!;
    if (!exports.add(exportPath)) {
      violations.add(
        '$_backendEntrypointPath:${index + 1}: duplicate export "$exportPath"',
      );
    }
    if (exportPath.contains('/legacy/')) {
      violations.add(
        '$_backendEntrypointPath:${index + 1}: '
        'legacy namespace exports are not allowed',
      );
    }
  }

  for (final required in _requiredExports) {
    if (!exports.contains(required)) {
      violations.add(
        '$_backendEntrypointPath: missing required export "$required"',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend entrypoint export guard failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend entrypoint export guard passed. Required public API exports are '
    'present and legacy exports are blocked.',
  );
}
