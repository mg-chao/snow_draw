import 'dart:io';

const _targetFiles = <String>[
  'packages/snow_draw_flutter_backend/lib/render/arrow/arrow_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/arrow/arrow_visual_cache.dart',
  'packages/snow_draw_flutter_backend/lib/render/element_type_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/filter/filter_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/free_draw/free_draw_path_utils.dart',
  'packages/snow_draw_flutter_backend/lib/render/free_draw/free_draw_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/free_draw/free_draw_visual_cache.dart',
  'packages/snow_draw_flutter_backend/lib/render/geometry/arrow_geometry.dart',
  'packages/snow_draw_flutter_backend/lib/render/highlight/highlight_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/line/line_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/patterns/stroke_pattern_utils.dart',
  'packages/snow_draw_flutter_backend/lib/render/rectangle/rectangle_render_plan.dart',
  'packages/snow_draw_flutter_backend/lib/render/rectangle/rectangle_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/element_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/scene/scene_primitive_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/stroke/two_point_stroke_utils.dart',
  'packages/snow_draw_flutter_backend/lib/render/text/serial_number_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/render/text/text_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/services/font/flutter_system_font_service_io.dart',
  'packages/snow_draw_flutter_backend/lib/services/text/flutter_text_rendering_cache_invalidation.dart',
  'packages/snow_draw_flutter_backend/lib/services/text/flutter_serial_number_layout.dart',
  'packages/snow_draw_flutter_backend/lib/services/text/flutter_text_layout.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/arrow_interaction_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/draw_canvas.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/dynamic_scene_optimization.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/dynamic_layer_split.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_pipeline/filter_segment.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_pipeline/filter_segment_builder.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_pipeline/filter_segment_renderer.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_interaction_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_shader_manager.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_scene_compositor.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/filter_style_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/frame_aligned_pointer_move_dispatcher.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/free_draw_creation_preview_cache.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/grid_shader_painter.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/highlight_interaction_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/highlight_interaction_scene_cache.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/highlight_mask_painter.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/highlight_mask_shader_manager.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/highlight_mask_static_scene_cache.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/highlight_mask_visibility.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/interaction_mutation_refresh_plan.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/pointer_move_dispatch_policy.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/rectangle_shader_manager.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/rectangle_interaction_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/render_keys.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/lightweight_line_edit_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/interaction_dynamic_scene_cache.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/serial_number_connection_painter.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/serial_number_connector_cache.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/serial_number_interaction_classifier.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/serial_number_interaction_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/static_canvas_painter.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/text_editing_state_change.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/visible_element_scene_cache.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/visible_element_scene_resolver.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/watermark_canvas_painter.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/watermark_painter.dart',
  'packages/snow_draw_flutter_backend/lib/ui/canvas/watermark_visibility.dart',
  'packages/snow_draw_flutter_backend/lib/visual/built_in_element_visuals.dart',
  'packages/snow_draw_flutter_backend/lib/visual/element_visual_definition.dart',
  'packages/snow_draw_flutter_backend/lib/visual/element_visual_registry.dart',
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
      violations.add('$targetPath: missing backend boundary file');
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
        '$targetPath:${index + 1}: backend boundary files must reference core '
        'via package:snow_draw_core/snow_draw_core.dart',
      );
    }
  }

  if (violations.isNotEmpty) {
    stderr.writeln('Backend core entrypoint import boundary check failed:');
    for (final violation in violations) {
      stderr.writeln('  $violation');
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'Backend core entrypoint import boundary check passed. '
    'Backend boundary files import core APIs through the core entrypoint only.',
  );
}
