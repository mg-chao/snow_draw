import '../../../core/coordinates/overlay_space.dart';
import '../../../models/edit_enums.dart';
import '../../../types/draw_point.dart';
import '../../../types/draw_rect.dart';
import '../../../utils/transforms/edit_transform_context.dart';

class BoundsResult {
  const BoundsResult({
    required this.bounds,
    required this.flipX,
    required this.flipY,
  });
  final DrawRect bounds;
  final bool flipX;
  final bool flipY;
}

/// Parameters for resize bounds calculation.
class ResizeBoundsParams {
  const ResizeBoundsParams({
    required this.transformContext,
    required this.mode,
    required this.currentPointerWorld,
    required this.handleOffsetLocal,
    required this.selectionPadding,
    required this.maintainAspectRatio,
    required this.resizeFromCenter,
  });
  final EditTransformContext transformContext;
  final ResizeMode mode;
  final DrawPoint currentPointerWorld;
  final DrawPoint handleOffsetLocal;
  final double selectionPadding;
  final bool maintainAspectRatio;
  final bool resizeFromCenter;
}

BoundsResult? calculateResizeBounds(ResizeBoundsParams params) {
  final ctx = params.transformContext;
  final space = ctx.overlaySpace;
  final startRect = ctx.startBounds;
  final startCenterWorld = ctx.center;

  // Transform pointer with handle offset
  final handlePaddedWorld = ctx.transformPointerWithOffset(
    currentPointerWorld: params.currentPointerWorld,
    handleOffsetLocal: params.handleOffsetLocal,
  );

  // Apply padding offset
  final paddingOffsetWorld = ctx.getPaddingOffset(
    mode: params.mode,
    padding: params.selectionPadding,
  );
  final movingBoundPointWorld = handlePaddedWorld - paddingOffsetWorld;

  // Get anchor point
  final anchorWorld = ctx.getAnchorPoint(
    mode: params.mode,
    resizeFromCenter: params.resizeFromCenter,
  );

  final dWorld = movingBoundPointWorld - anchorWorld;
  final dLocal = space.rotateVectorToLocal(dWorld);

  final aspectRatio = ctx.aspectRatio;

  final (expectedDx, expectedDy) = _expectedAnchorToMovingDirectionLocal(
    params.mode,
  );
  final affectsX = _affectsXAxis(params.mode);
  final affectsY = _affectsYAxis(params.mode);

  final flipX =
      !params.resizeFromCenter &&
      affectsX &&
      expectedDx != 0 &&
      dLocal.x != 0 &&
      dLocal.x.sign != expectedDx;
  final flipY =
      !params.resizeFromCenter &&
      affectsY &&
      expectedDy != 0 &&
      dLocal.y != 0 &&
      dLocal.y.sign != expectedDy;

  double newWidth;
  double newHeight;
  DrawPoint newCenterWorld;

  if (params.resizeFromCenter) {
    final result = _calculateFromCenterResize(
      mode: params.mode,
      dLocal: dLocal,
      startRect: startRect,
      startCenterWorld: startCenterWorld,
      maintainAspectRatio: params.maintainAspectRatio,
      aspectRatio: aspectRatio,
    );
    if (result == null) {
      return null;
    }
    newWidth = result.$1;
    newHeight = result.$2;
    newCenterWorld = result.$3;
  } else {
    final result = _calculateFromAnchorResize(
      mode: params.mode,
      dLocal: dLocal,
      startRect: startRect,
      anchorWorld: anchorWorld,
      space: space,
      maintainAspectRatio: params.maintainAspectRatio,
      aspectRatio: aspectRatio,
    );
    if (result == null) {
      return null;
    }
    newWidth = result.$1;
    newHeight = result.$2;
    newCenterWorld = result.$3;
  }

  final newRect = DrawRect(
    minX: newCenterWorld.x - newWidth / 2,
    minY: newCenterWorld.y - newHeight / 2,
    maxX: newCenterWorld.x + newWidth / 2,
    maxY: newCenterWorld.y + newHeight / 2,
  );

  return BoundsResult(bounds: newRect, flipX: flipX, flipY: flipY);
}

(double, double, DrawPoint)? _calculateFromCenterResize({
  required ResizeMode mode,
  required DrawPoint dLocal,
  required DrawRect startRect,
  required DrawPoint startCenterWorld,
  required bool maintainAspectRatio,
  required double? aspectRatio,
}) {
  double newWidth;
  double newHeight;

  if (_isCornerResize(mode)) {
    var hx = dLocal.x.abs();
    var hy = dLocal.y.abs();

    if (maintainAspectRatio && aspectRatio != null) {
      final adx = dLocal.x.abs();
      final ady = dLocal.y.abs();
      final widthBased = ady == 0 || (adx / ady) >= aspectRatio;
      if (widthBased) {
        hx = adx;
        hy = hx / aspectRatio;
      } else {
        hy = ady;
        hx = hy * aspectRatio;
      }
    }

    newWidth = hx * 2;
    newHeight = hy * 2;
  } else {
    switch (mode) {
      case ResizeMode.left:
      case ResizeMode.right:
        newWidth = dLocal.x.abs() * 2;
        if (maintainAspectRatio && aspectRatio != null) {
          newHeight = newWidth / aspectRatio;
        } else {
          newHeight = startRect.height;
        }
      case ResizeMode.top:
      case ResizeMode.bottom:
        newHeight = dLocal.y.abs() * 2;
        if (maintainAspectRatio && aspectRatio != null) {
          newWidth = newHeight * aspectRatio;
        } else {
          newWidth = startRect.width;
        }
      case ResizeMode.topLeft:
      case ResizeMode.topRight:
      case ResizeMode.bottomRight:
      case ResizeMode.bottomLeft:
        return null;
    }
  }

  return (newWidth, newHeight, startCenterWorld);
}

(double, double, DrawPoint)? _calculateFromAnchorResize({
  required ResizeMode mode,
  required DrawPoint dLocal,
  required DrawRect startRect,
  required DrawPoint anchorWorld,
  required OverlaySpace space,
  required bool maintainAspectRatio,
  required double? aspectRatio,
}) {
  double newWidth;
  double newHeight;
  DrawPoint newCenterWorld;

  if (_isCornerResize(mode)) {
    var dx = dLocal.x;
    var dy = dLocal.y;

    if (maintainAspectRatio && aspectRatio != null) {
      final sx = dx >= 0 ? 1.0 : -1.0;
      final sy = dy >= 0 ? 1.0 : -1.0;
      final adx = dx.abs();
      final ady = dy.abs();
      final widthBased = ady == 0 || (adx / ady) >= aspectRatio;
      if (widthBased) {
        final w = adx;
        final h = w / aspectRatio;
        dx = sx * w;
        dy = sy * h;
      } else {
        final h = ady;
        final w = h * aspectRatio;
        dx = sx * w;
        dy = sy * h;
      }
    }

    final adjustedMovingWorld =
        anchorWorld + space.rotateVectorToWorld(DrawPoint(x: dx, y: dy));
    newCenterWorld = DrawPoint(
      x: (anchorWorld.x + adjustedMovingWorld.x) / 2,
      y: (anchorWorld.y + adjustedMovingWorld.y) / 2,
    );
    newWidth = dx.abs();
    newHeight = dy.abs();
  } else {
    switch (mode) {
      case ResizeMode.left:
      case ResizeMode.right:
        final dx = dLocal.x;
        final adjustedMovingWorld =
            anchorWorld + space.rotateVectorToWorld(DrawPoint(x: dx, y: 0));
        newCenterWorld = DrawPoint(
          x: (anchorWorld.x + adjustedMovingWorld.x) / 2,
          y: (anchorWorld.y + adjustedMovingWorld.y) / 2,
        );
        newWidth = dx.abs();
        if (maintainAspectRatio && aspectRatio != null) {
          newHeight = newWidth / aspectRatio;
        } else {
          newHeight = startRect.height;
        }
      case ResizeMode.top:
      case ResizeMode.bottom:
        final dy = dLocal.y;
        final adjustedMovingWorld =
            anchorWorld + space.rotateVectorToWorld(DrawPoint(x: 0, y: dy));
        newCenterWorld = DrawPoint(
          x: (anchorWorld.x + adjustedMovingWorld.x) / 2,
          y: (anchorWorld.y + adjustedMovingWorld.y) / 2,
        );
        newHeight = dy.abs();
        if (maintainAspectRatio && aspectRatio != null) {
          newWidth = newHeight * aspectRatio;
        } else {
          newWidth = startRect.width;
        }
      case ResizeMode.topLeft:
      case ResizeMode.topRight:
      case ResizeMode.bottomRight:
      case ResizeMode.bottomLeft:
        return null;
    }
  }

  return (newWidth, newHeight, newCenterWorld);
}

bool _isCornerResize(ResizeMode mode) =>
    mode == ResizeMode.topLeft ||
    mode == ResizeMode.topRight ||
    mode == ResizeMode.bottomLeft ||
    mode == ResizeMode.bottomRight;

bool _affectsXAxis(ResizeMode mode) =>
    mode == ResizeMode.left ||
    mode == ResizeMode.right ||
    _isCornerResize(mode);

bool _affectsYAxis(ResizeMode mode) =>
    mode == ResizeMode.top ||
    mode == ResizeMode.bottom ||
    _isCornerResize(mode);

(int expectedDx, int expectedDy) _expectedAnchorToMovingDirectionLocal(
  ResizeMode mode,
) {
  switch (mode) {
    case ResizeMode.topLeft:
      return (-1, -1);
    case ResizeMode.topRight:
      return (1, -1);
    case ResizeMode.bottomRight:
      return (1, 1);
    case ResizeMode.bottomLeft:
      return (-1, 1);
    case ResizeMode.top:
      return (0, -1);
    case ResizeMode.bottom:
      return (0, 1);
    case ResizeMode.left:
      return (-1, 0);
    case ResizeMode.right:
      return (1, 0);
  }
}
