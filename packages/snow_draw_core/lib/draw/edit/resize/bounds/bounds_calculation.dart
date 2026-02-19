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

BoundsResult calculateResizeBounds(ResizeBoundsParams params) {
  final ctx = params.transformContext;
  final space = ctx.overlaySpace;
  final startRect = ctx.startBounds;
  final movingBoundPointWorld =
      ctx.transformPointerWithOffset(
        currentPointerWorld: params.currentPointerWorld,
        handleOffsetLocal: params.handleOffsetLocal,
      ) -
      ctx.getPaddingOffset(mode: params.mode, padding: params.selectionPadding);

  final anchorWorld = ctx.getAnchorPoint(
    mode: params.mode,
    resizeFromCenter: params.resizeFromCenter,
  );
  final dLocal = space.rotateVectorToLocal(movingBoundPointWorld - anchorWorld);
  final aspectRatio = ctx.aspectRatio;

  final (expectedDx, expectedDy) = _expectedAnchorToMovingDirectionLocal(
    params.mode,
  );
  final flipX =
      !params.resizeFromCenter &&
      expectedDx != 0 &&
      dLocal.x != 0 &&
      dLocal.x.sign != expectedDx;
  final flipY =
      !params.resizeFromCenter &&
      expectedDy != 0 &&
      dLocal.y != 0 &&
      dLocal.y.sign != expectedDy;

  final (newWidth, newHeight, newCenterWorld) = params.resizeFromCenter
      ? _calculateFromCenterResize(
          mode: params.mode,
          dLocal: dLocal,
          startRect: startRect,
          startCenterWorld: ctx.center,
          maintainAspectRatio: params.maintainAspectRatio,
          aspectRatio: aspectRatio,
        )
      : _calculateFromAnchorResize(
          mode: params.mode,
          dLocal: dLocal,
          startRect: startRect,
          anchorWorld: anchorWorld,
          space: space,
          maintainAspectRatio: params.maintainAspectRatio,
          aspectRatio: aspectRatio,
        );

  return BoundsResult(
    bounds: _rectFromCenter(newCenterWorld, newWidth, newHeight),
    flipX: flipX,
    flipY: flipY,
  );
}

(double, double, DrawPoint) _calculateFromCenterResize({
  required ResizeMode mode,
  required DrawPoint dLocal,
  required DrawRect startRect,
  required DrawPoint startCenterWorld,
  required bool maintainAspectRatio,
  required double? aspectRatio,
}) {
  switch (mode) {
    case ResizeMode.topLeft:
    case ResizeMode.topRight:
    case ResizeMode.bottomRight:
    case ResizeMode.bottomLeft:
      var halfWidth = dLocal.x.abs();
      var halfHeight = dLocal.y.abs();
      if (maintainAspectRatio && aspectRatio != null) {
        (halfWidth, halfHeight) = _lockCornerSizeToAspectRatio(
          width: halfWidth,
          height: halfHeight,
          aspectRatio: aspectRatio,
        );
      }
      return (halfWidth * 2, halfHeight * 2, startCenterWorld);
    case ResizeMode.left:
    case ResizeMode.right:
      final width = dLocal.x.abs() * 2;
      final height = maintainAspectRatio && aspectRatio != null
          ? width / aspectRatio
          : startRect.height;
      return (width, height, startCenterWorld);
    case ResizeMode.top:
    case ResizeMode.bottom:
      final height = dLocal.y.abs() * 2;
      final width = maintainAspectRatio && aspectRatio != null
          ? height * aspectRatio
          : startRect.width;
      return (width, height, startCenterWorld);
  }
}

(double, double, DrawPoint) _calculateFromAnchorResize({
  required ResizeMode mode,
  required DrawPoint dLocal,
  required DrawRect startRect,
  required DrawPoint anchorWorld,
  required OverlaySpace space,
  required bool maintainAspectRatio,
  required double? aspectRatio,
}) {
  switch (mode) {
    case ResizeMode.topLeft:
    case ResizeMode.topRight:
    case ResizeMode.bottomRight:
    case ResizeMode.bottomLeft:
      var dx = dLocal.x;
      var dy = dLocal.y;
      if (maintainAspectRatio && aspectRatio != null) {
        var absWidth = dx.abs();
        var absHeight = dy.abs();
        (absWidth, absHeight) = _lockCornerSizeToAspectRatio(
          width: absWidth,
          height: absHeight,
          aspectRatio: aspectRatio,
        );
        dx = _withSign(absWidth, dx);
        dy = _withSign(absHeight, dy);
      }
      final movingWorld =
          anchorWorld + space.rotateVectorToWorld(DrawPoint(x: dx, y: dy));
      final centerWorld = _midpoint(anchorWorld, movingWorld);
      return (dx.abs(), dy.abs(), centerWorld);
    case ResizeMode.left:
    case ResizeMode.right:
      final dx = dLocal.x;
      final movingWorld =
          anchorWorld + space.rotateVectorToWorld(DrawPoint(x: dx, y: 0));
      final width = dx.abs();
      final height = maintainAspectRatio && aspectRatio != null
          ? width / aspectRatio
          : startRect.height;
      return (width, height, _midpoint(anchorWorld, movingWorld));
    case ResizeMode.top:
    case ResizeMode.bottom:
      final dy = dLocal.y;
      final movingWorld =
          anchorWorld + space.rotateVectorToWorld(DrawPoint(x: 0, y: dy));
      final height = dy.abs();
      final width = maintainAspectRatio && aspectRatio != null
          ? height * aspectRatio
          : startRect.width;
      return (width, height, _midpoint(anchorWorld, movingWorld));
  }
}

(double, double) _lockCornerSizeToAspectRatio({
  required double width,
  required double height,
  required double aspectRatio,
}) {
  if (height == 0 || (width / height) >= aspectRatio) {
    return (width, width / aspectRatio);
  }
  return (height * aspectRatio, height);
}

double _withSign(double magnitude, double value) =>
    value >= 0 ? magnitude : -magnitude;

DrawPoint _midpoint(DrawPoint a, DrawPoint b) =>
    DrawPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2);

DrawRect _rectFromCenter(DrawPoint center, double width, double height) {
  final halfWidth = width / 2;
  final halfHeight = height / 2;
  return DrawRect(
    minX: center.x - halfWidth,
    minY: center.y - halfHeight,
    maxX: center.x + halfWidth,
    maxY: center.y + halfHeight,
  );
}

(int expectedDx, int expectedDy) _expectedAnchorToMovingDirectionLocal(
  ResizeMode mode,
) => switch (mode) {
  ResizeMode.topLeft => (-1, -1),
  ResizeMode.topRight => (1, -1),
  ResizeMode.bottomRight => (1, 1),
  ResizeMode.bottomLeft => (-1, 1),
  ResizeMode.top => (0, -1),
  ResizeMode.bottom => (0, 1),
  ResizeMode.left => (-1, 0),
  ResizeMode.right => (1, 0),
};
