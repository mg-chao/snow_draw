import 'package:meta/meta.dart';

import '../../types/draw_point.dart';
import 'coordinate_space.dart';

/// Coordinate space for multi-select overlay transforms.
///
/// This space represents the rotation of a multi-select overlay around its
/// center. Use this when transforming points relative to a multi-select
/// selection overlay.
///
/// The implementation is identical to ElementSpace, but the separate type
/// provides compile-time type safety to prevent mixing element-local and
/// overlay-local coordinate spaces.
///
/// Example:
/// ```dart
/// final space = OverlaySpace(
///   rotation: overlay.rotation,
///   origin: overlay.center,
/// );
/// final localPoint = space.fromWorld(worldPoint);
/// ```
@immutable
class OverlaySpace extends CoordinateSpace {
  const OverlaySpace({required this.rotation, required this.origin});

  @override
  final double rotation;

  @override
  final DrawPoint origin;

  @override
  DrawPoint fromWorld(DrawPoint worldPoint) =>
      rotatePoint(point: worldPoint, center: origin, angle: -rotation);

  @override
  DrawPoint toWorld(DrawPoint localPoint) =>
      rotatePoint(point: localPoint, center: origin, angle: rotation);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OverlaySpace &&
          other.rotation == rotation &&
          other.origin == origin;

  @override
  int get hashCode => Object.hash(rotation, origin);

  @override
  String toString() => 'OverlaySpace(rotation: $rotation, origin: $origin)';
}
