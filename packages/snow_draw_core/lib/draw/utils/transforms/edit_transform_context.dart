import '../../core/coordinates/overlay_space.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';
import '../../types/resize_mode.dart';
import 'resize_anchor_point.dart';

/// Coordinate transform helpers used by resize calculations.
class EditTransformContext {
  EditTransformContext({
    required this.startBounds,
    required double rotation,
    required this.center,
  }) : overlaySpace = OverlaySpace(rotation: rotation, origin: center);

  /// Selection bounds at the start of the resize operation.
  final DrawRect startBounds;

  /// Selection center in world coordinates.
  final DrawPoint center;

  /// Selection overlay transform space.
  final OverlaySpace overlaySpace;

  /// Aspect ratio of the start bounds (width / height).
  /// Returns null if width or height is zero.
  double? get aspectRatio => startBounds.width == 0 || startBounds.height == 0
      ? null
      : startBounds.width / startBounds.height;

  /// Transforms pointer position with handle offset applied.
  DrawPoint transformPointerWithOffset({
    required DrawPoint currentPointerWorld,
    required DrawPoint handleOffsetLocal,
  }) =>
      currentPointerWorld + overlaySpace.rotateVectorToWorld(handleOffsetLocal);

  /// Gets the anchor point for a resize operation.
  DrawPoint getAnchorPoint({
    required ResizeMode mode,
    required bool resizeFromCenter,
  }) => resizeFromCenter
      ? center
      : overlaySpace.toWorld(oppositeBoundPointLocal(startBounds, mode));

  /// Gets the padding offset for a resize mode.
  DrawPoint getPaddingOffset({
    required ResizeMode mode,
    required double padding,
  }) => overlaySpace.rotateVectorToWorld(
    _handlePaddingOffsetLocal(mode, padding),
  );

  /// Calculates the padding offset in local coordinates for a resize mode.
  static DrawPoint _handlePaddingOffsetLocal(ResizeMode mode, double padding) =>
      switch (mode) {
        ResizeMode.topLeft => DrawPoint(x: -padding, y: -padding),
        ResizeMode.topRight => DrawPoint(x: padding, y: -padding),
        ResizeMode.bottomRight => DrawPoint(x: padding, y: padding),
        ResizeMode.bottomLeft => DrawPoint(x: -padding, y: padding),
        ResizeMode.top => DrawPoint(x: 0, y: -padding),
        ResizeMode.bottom => DrawPoint(x: 0, y: padding),
        ResizeMode.left => DrawPoint(x: -padding, y: 0),
        ResizeMode.right => DrawPoint(x: padding, y: 0),
      };
}
