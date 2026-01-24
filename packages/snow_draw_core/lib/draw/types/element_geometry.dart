import 'package:meta/meta.dart';

import 'draw_point.dart';
import 'draw_rect.dart';

/// Element geometry snapshot (move operations only).
///
/// Stores the minimal data needed for moves: element center.
/// Compared to full ElementState (~200B), uses ~16B, saving ~92% memory.
@immutable
class ElementMoveSnapshot {
  const ElementMoveSnapshot({required this.center});
  final DrawPoint center;
}

/// Element geometry snapshot (resize operations).
///
/// Stores data needed for resizing: rect and rotation.
/// Compared to full ElementState (~200B), uses ~40B, saving ~80% memory.
@immutable
class ElementResizeSnapshot {
  const ElementResizeSnapshot({required this.rect, required this.rotation});
  final DrawRect rect;
  final double rotation;

  DrawPoint get center => rect.center;
  double get width => rect.width;
  double get height => rect.height;
}

/// Element rotation snapshot (rotate operations).
///
/// Stores data needed for rotation: center and rotation.
/// Compared to full ElementState (~200B), uses ~24B, saving ~88% memory.
@immutable
class ElementRotateSnapshot {
  const ElementRotateSnapshot({required this.center, required this.rotation});
  final DrawPoint center;
  final double rotation;
}
