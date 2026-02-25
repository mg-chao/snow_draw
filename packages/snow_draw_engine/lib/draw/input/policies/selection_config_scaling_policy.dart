import '../../config/draw_config.dart';
import '../../utils/camera_zoom.dart';

/// Scales [selectionConfig] for input hit-testing under [scaleFactor].
///
/// Invalid scale factors are treated as `1.0`.
SelectionConfig scaleSelectionConfigForInput({
  required SelectionConfig selectionConfig,
  required double scaleFactor,
}) {
  final effectiveScale = resolveEffectiveZoom(scaleFactor);
  if ((effectiveScale - 1).abs() <= 0.0001) {
    return selectionConfig;
  }

  final interaction = selectionConfig.interaction;
  final render = selectionConfig.render;
  return selectionConfig.copyWith(
    render: render.copyWith(
      strokeWidth: render.strokeWidth / effectiveScale,
      cornerRadius: render.cornerRadius / effectiveScale,
      controlPointSize: render.controlPointSize / effectiveScale,
    ),
    padding: selectionConfig.padding / effectiveScale,
    rotateHandleOffset: selectionConfig.rotateHandleOffset / effectiveScale,
    interaction: interaction.copyWith(
      handleTolerance: interaction.handleTolerance / effectiveScale,
      dragThreshold: interaction.dragThreshold / effectiveScale,
    ),
  );
}
