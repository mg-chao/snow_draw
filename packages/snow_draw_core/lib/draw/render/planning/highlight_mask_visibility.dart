import '../../config/draw_config.dart';

/// Whether highlight-mask overlay pixels should be painted.
bool isHighlightMaskVisible({
  required bool hasHighlights,
  required HighlightMaskConfig config,
}) => hasHighlights && config.maskOpacity > 0;
