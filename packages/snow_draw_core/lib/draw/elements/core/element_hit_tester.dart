import 'package:meta/meta.dart';

import '../../models/element_state.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';

/// Hit testing interface for a single element type.
@immutable
abstract interface class ElementHitTester {
  const ElementHitTester();

  /// Returns true if [position] hits [element].
  bool hitTest({
    required ElementState element,
    required DrawPoint position,
    double tolerance = 0,
  });

  /// Returns the element bounds used for selection overlays.
  DrawRect getBounds(ElementState element);
}
