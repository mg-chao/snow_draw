import '../../config/draw_config.dart';

/// Scales [selectionConfig] for input hit-testing under [scaleFactor].
SelectionConfig scaleSelectionConfigForInput({
  required SelectionConfig selectionConfig,
  required double scaleFactor,
}) {
  final effectiveScale = scaleFactor == 0 ? 1.0 : scaleFactor;
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
