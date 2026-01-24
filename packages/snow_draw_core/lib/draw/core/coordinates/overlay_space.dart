import 'dart:math' as math;

import 'package:flutter/foundation.dart';

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

  double get _cos => math.cos(rotation);
  double get _sin => math.sin(rotation);

  @override
  DrawPoint fromWorld(DrawPoint worldPoint) {
    if (rotation == 0) {
      return worldPoint;
    }

    final dx = worldPoint.x - origin.x;
    final dy = worldPoint.y - origin.y;

    // Apply inverse rotation (-rotation) around origin.
    return DrawPoint(
      x: origin.x + dx * _cos + dy * _sin,
      y: origin.y - dx * _sin + dy * _cos,
    );
  }

  @override
  DrawPoint toWorld(DrawPoint localPoint) {
    if (rotation == 0) {
      return localPoint;
    }

    final dx = localPoint.x - origin.x;
    final dy = localPoint.y - origin.y;

    // Apply rotation (+rotation) around origin.
    return DrawPoint(
      x: origin.x + dx * _cos - dy * _sin,
      y: origin.y + dx * _sin + dy * _cos,
    );
  }

  @override
  DrawPoint rotateVectorToWorld(DrawPoint localVector) {
    if (rotation == 0) {
      return localVector;
    }
    return DrawPoint(
      x: localVector.x * _cos - localVector.y * _sin,
      y: localVector.x * _sin + localVector.y * _cos,
    );
  }

  @override
  DrawPoint rotateVectorToLocal(DrawPoint worldVector) {
    if (rotation == 0) {
      return worldVector;
    }

    // Apply inverse rotation (-rotation).
    return DrawPoint(
      x: worldVector.x * _cos + worldVector.y * _sin,
      y: -worldVector.x * _sin + worldVector.y * _cos,
    );
  }

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
