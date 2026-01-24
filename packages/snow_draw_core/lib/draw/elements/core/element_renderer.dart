import 'dart:ui';

import '../../models/element_state.dart';

/// Renderer interface for a single element type.
abstract class ElementTypeRenderer {
  const ElementTypeRenderer();

  /// Renders [element] onto [canvas].
  void render({
    required Canvas canvas,
    required ElementState element,
    required double scaleFactor,
    Locale? locale,
  });

  /// Renders a type preview (optional), for UI toolbars, etc.
  void renderPreview({required Canvas canvas, required Size size}) {}
}
