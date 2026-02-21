import 'dart:io';

const _coreEntrypointPath = 'packages/snow_draw_core/lib/snow_draw_core.dart';
const _coreLibRootPath = 'packages/snow_draw_core/lib';

const _allowedExports = <String>{
  'draw/actions/actions.dart',
  'draw/config/draw_config.dart',
  'draw/core/draw_context.dart',
  'draw/elements/core/element_data.dart',
  'draw/elements/core/element_definition.dart',
  'draw/elements/core/element_type_id.dart',
  'draw/elements/core/element_registry.dart',
  'draw/elements/core/element_registry_interface.dart',
  'draw/elements/core/element_scene_encoder.dart',
  'draw/elements/text_rendering_cache_invalidation.dart',
  'draw/elements/registration.dart',
  'draw/elements/types/arrow/arrow_data.dart',
  'draw/elements/types/filter/filter_data.dart',
  'draw/elements/types/free_draw/free_draw_data.dart',
  'draw/elements/types/highlight/highlight_data.dart',
  'draw/elements/types/line/line_data.dart',
  'draw/elements/types/rectangle/rectangle_data.dart',
  'draw/elements/types/serial_number/serial_number_data.dart',
  'draw/elements/types/text/text_data.dart',
  'draw/events/error_events.dart',
  'draw/events/event_bus.dart',
  'draw/events/state_events.dart',
  'draw/models/application_state.dart',
  'draw/models/camera_state.dart',
  'draw/models/document_state.dart',
  'draw/models/domain_state.dart',
  'draw/models/draw_state.dart',
  'draw/models/element_state.dart',
  'draw/models/interaction_state.dart',
  'draw/models/selection_state.dart',
  'draw/models/view_state.dart',
  'draw/render/scene/render_scene.dart',
  'draw/render/scene/scene_encoding_not_supported.dart',
  'draw/services/coordinate_service.dart',
  'draw/services/draw_state_view_builder.dart',
  'draw/services/log/log_config.dart',
  'draw/services/log/log_service.dart',
  'draw/services/text/text_metrics_service.dart',
  'draw/store/draw_store.dart',
  'draw/store/draw_store_interface.dart',
  'draw/store/selector.dart',
  'draw/types/draw_color.dart',
  'draw/types/element_style.dart',
  'draw/types/draw_point.dart',
  'draw/types/draw_rect.dart',
  'draw/utils/lru_cache.dart',
  'draw/utils/snapping_mode.dart',
  'utils/id_generator.dart',
};

final _exportPattern = RegExp(r"""^export\s+['"](.+)['"];$""");

void main() {
  final entrypoint = File(_coreEntrypointPath);
  if (!entrypoint.existsSync()) {
    stderr.writeln('Missing core entrypoint: $_coreEntrypointPath');
    exitCode = 1;
    return;
  }

  final exports = <String>{};
  final violations = <String>[];
  final lines = entrypoint.readAsLinesSync();

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index].trim();
    if (line.isEmpty || line.startsWith('//') || line.startsWith('///')) {
      continue;
    }

    final match = _exportPattern.firstMatch(line);
    if (match == null) {
      violations.add(
        '$_coreEntrypointPath:${index + 1}: '
        'unexpected statement in core entrypoint: "$line"',
      );
      continue;
    }

    final exportPath = match.group(1)!;
    if (!exports.add(exportPath)) {
      violations.add(
        '$_coreEntrypointPath:${index + 1}: duplicate export "$exportPath"',
      );
      continue;
    }
    if (exportPath.contains('/ui/')) {
      violations.add(
        '$_coreEntrypointPath:${index + 1}: ui exports are not allowed in '
        'the pure core entrypoint',
      );
    }
    if (exportPath.contains('flutter')) {
      violations.add(
        '$_coreEntrypointPath:${index + 1}: flutter-related exports are not '
        'allowed in the pure core entrypoint',
      );
    }
  }

  for (final allowed in _allowedExports) {
    if (!exports.contains(allowed)) {
      violations.add(
        '$_coreEntrypointPath: missing required export "$allowed"',
      );
    }
  }

  for (final exportPath in exports) {
    final exportFile = File('$_coreLibRootPath/$exportPath');
    if (!exportFile.existsSync()) {
      violations.add(
        '$_coreEntrypointPath: export "$exportPath" points to missing file '
        'at ${exportFile.path.replaceAll(r'\\', '/')}',
      );
      continue;
    }
    if (!_allowedExports.contains(exportPath)) {
      violations.add(
        '$_coreEntrypointPath: unexpected export "$exportPath" is not part '
        'of the core entrypoint contract',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Core entrypoint export guard failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Core entrypoint export guard passed. Required pure-Dart API exports are '
    'present and unexpected exports are denied.',
  );
}
