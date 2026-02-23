import 'package:snow_draw_core/snow_draw_core.dart';

/// Whether highlight-mask overlay pixels should be painted.
bool isHighlightMaskVisible({
  required bool hasHighlights,
  required HighlightMaskConfig config,
}) => hasHighlights && config.maskOpacity > 0;
