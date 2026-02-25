import 'package:meta/meta.dart';

import 'draw_point.dart';
import 'draw_rect.dart';

/// Geometry snapshot used by move operations.
@immutable
class ElementMoveSnapshot {
  const ElementMoveSnapshot({required this.center});
  final DrawPoint center;
}

/// Geometry snapshot used by resize operations.
@immutable
class ElementResizeSnapshot {
  const ElementResizeSnapshot({required this.rect, required this.rotation});
  final DrawRect rect;
  final double rotation;

  DrawPoint get center => rect.center;
  double get width => rect.width;
  double get height => rect.height;
}

/// Geometry snapshot used by rotate operations.
@immutable
class ElementRotateSnapshot {
  const ElementRotateSnapshot({required this.center, required this.rotation});
  final DrawPoint center;
  final double rotation;
}
