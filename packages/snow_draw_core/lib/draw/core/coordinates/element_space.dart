import 'package:flutter/foundation.dart';

import '../../types/draw_point.dart';
import 'coordinate_space.dart';

/// Coordinate space for a single element's local frame.
///
/// This space represents the element's own rotation around its center.
/// Use this when transforming points relative to an individual element.
///
/// Example:
/// ```dart
/// final space = ElementSpace(
///   rotation: element.rotation,
///   origin: element.center,
/// );
/// final localPoint = space.fromWorld(worldPoint);
/// ```
@immutable
class ElementSpace extends CoordinateSpace {
  const ElementSpace({required this.rotation, required this.origin});
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
      other is ElementSpace &&
          other.rotation == rotation &&
          other.origin == origin;

  @override
  int get hashCode => Object.hash(rotation, origin);

  @override
  String toString() => 'ElementSpace(rotation: $rotation, origin: $origin)';
}
