import '../../core/coordinates/overlay_space.dart';
import '../../models/edit_enums.dart';
import '../../types/draw_point.dart';
import '../../types/draw_rect.dart';

/// Unified transform context for element editing operations.
///
/// This class encapsulates all the context needed for coordinate
/// transformations during editing (resize, rotate, move), ensuring consistent
/// handling across single-select and multi-select scenarios, with or without
/// rotation.
///
/// Key benefits:
/// - Centralizes coordinate transformation logic
/// - Eliminates code duplication between different resize paths
/// - Provides a single source of truth for rotation center and bounds
class EditTransformContext {
  const EditTransformContext({
    required this.startBounds,
    required this.rotation,
    required this.center,
    required this.isMultiSelect,
  });

  /// The selection bounds at the start of the edit operation (world
  /// coordinates).
  ///
  /// When [rotation] is non-zero, we often transform points into an
  /// "unrotated world" space (see [toLocal]) to do axis-aligned math. In that
  /// case, this
  /// rect is still expressed in world coordinates, but can be treated as the
  /// axis-aligned reference bounds in the unrotated space.
  final DrawRect startBounds;

  /// The rotation angle of the selection overlay.
  /// For single-select: element's rotation.
  /// For multi-select: the multi-select overlay rotation.
  final double rotation;

  /// The center point of the selection (world coordinates).
  ///
  /// This is the pivot/origin for [rotation] transforms.
  final DrawPoint center;

  /// Whether this is a multi-select operation.
  final bool isMultiSelect;

  /// Whether the selection has rotation applied.
  bool get hasRotation => rotation != 0;

  /// The semantic coordinate space for the selection overlay.
  ///
  /// This space converts between:
  /// - world coordinates (canvas space) and
  /// - the overlay's un-rotated local frame (still expressed in world units).
  OverlaySpace get overlaySpace =>
      OverlaySpace(rotation: rotation, origin: center);

  /// Aspect ratio of the start bounds (width / height).
  /// Returns null if width or height is zero.
  double? get aspectRatio {
    if (startBounds.width == 0 || startBounds.height == 0) {
      return null;
    }
    return startBounds.width / startBounds.height;
  }

  /// Transforms a point from world to "unrotated world".
  ///
  /// The returned point is still expressed in world coordinates; it is simply
  /// rotated around [center] by `-rotation`.
  DrawPoint toLocal(DrawPoint world) => overlaySpace.fromWorld(world);

  /// Transforms a point from "unrotated world" back to world.
  DrawPoint toWorld(DrawPoint local) => overlaySpace.toWorld(local);

  /// Rotates a vector from local to world coordinates (no translation).
  DrawPoint rotateVectorToWorld(DrawPoint localVector) =>
      overlaySpace.rotateVectorToWorld(localVector);

  /// Rotates a vector from world to local coordinates (no translation).
  DrawPoint rotateVectorToLocal(DrawPoint worldVector) =>
      overlaySpace.rotateVectorToLocal(worldVector);

  /// Transforms pointer position with handle offset applied.
  ///
  /// This combines the current pointer position with the handle offset
  /// (which is in local coordinates) to get the effective handle position
  /// in world coordinates.
  DrawPoint transformPointerWithOffset({
    required DrawPoint currentPointerWorld,
    required DrawPoint handleOffsetLocal,
  }) {
    final handleOffsetWorld = overlaySpace.rotateVectorToWorld(
      handleOffsetLocal,
    );
    return currentPointerWorld + handleOffsetWorld;
  }

  /// Gets the anchor point for a resize operation.
  ///
  /// If [resizeFromCenter] is true, returns the center point.
  /// Otherwise, returns the opposite corner/edge point for the given [mode].
  DrawPoint getAnchorPoint({
    required ResizeMode mode,
    required bool resizeFromCenter,
  }) {
    if (resizeFromCenter) {
      return center;
    }
    final anchorLocal = _oppositeBoundPointLocal(startBounds, mode);
    return overlaySpace.toWorld(anchorLocal);
  }

  /// Gets the padding offset for a resize mode.
  ///
  /// This calculates the offset needed to account for selection padding
  /// when determining the actual resize bounds.
  DrawPoint getPaddingOffset({
    required ResizeMode mode,
    required double padding,
  }) {
    final paddingLocal = _handlePaddingOffsetLocal(mode, padding);
    return overlaySpace.rotateVectorToWorld(paddingLocal);
  }

  /// Returns the opposite anchor point for a given resize handle [mode].
  static DrawPoint _oppositeBoundPointLocal(DrawRect rect, ResizeMode mode) {
    switch (mode) {
      case ResizeMode.topLeft:
        return DrawPoint(x: rect.maxX, y: rect.maxY);
      case ResizeMode.topRight:
        return DrawPoint(x: rect.minX, y: rect.maxY);
      case ResizeMode.bottomRight:
        return DrawPoint(x: rect.minX, y: rect.minY);
      case ResizeMode.bottomLeft:
        return DrawPoint(x: rect.maxX, y: rect.minY);
      case ResizeMode.top:
        return DrawPoint(x: rect.centerX, y: rect.maxY);
      case ResizeMode.bottom:
        return DrawPoint(x: rect.centerX, y: rect.minY);
      case ResizeMode.left:
        return DrawPoint(x: rect.maxX, y: rect.centerY);
      case ResizeMode.right:
        return DrawPoint(x: rect.minX, y: rect.centerY);
    }
  }

  /// Calculates the padding offset in local coordinates for a resize mode.
  static DrawPoint _handlePaddingOffsetLocal(ResizeMode mode, double padding) {
    switch (mode) {
      case ResizeMode.topLeft:
        return DrawPoint(x: -padding, y: -padding);
      case ResizeMode.topRight:
        return DrawPoint(x: padding, y: -padding);
      case ResizeMode.bottomRight:
        return DrawPoint(x: padding, y: padding);
      case ResizeMode.bottomLeft:
        return DrawPoint(x: -padding, y: padding);
      case ResizeMode.top:
        return DrawPoint(x: 0, y: -padding);
      case ResizeMode.bottom:
        return DrawPoint(x: 0, y: padding);
      case ResizeMode.left:
        return DrawPoint(x: -padding, y: 0);
      case ResizeMode.right:
        return DrawPoint(x: padding, y: 0);
    }
  }
}
