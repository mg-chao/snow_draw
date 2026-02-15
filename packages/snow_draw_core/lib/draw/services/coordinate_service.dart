import 'dart:ui' show Offset;

import 'package:meta/meta.dart';

import '../models/camera_state.dart';
import '../types/draw_point.dart';

/// Coordinate transformation service.
///
/// Unifies conversions between screen/widget coordinates and world coordinates.
/// World coordinates are what drawing elements use.
@immutable
class CoordinateService {
  const CoordinateService({required this.camera, this.scaleFactor = 1.0})
    : assert(
        scaleFactor > 0 && scaleFactor < double.infinity,
        'scaleFactor must be finite and > 0',
      ),
      _inverseScaleFactor = 1 / scaleFactor;

  factory CoordinateService.fromCamera(
    CameraState camera, {
    double? scaleFactor,
  }) => CoordinateService(
    camera: camera,
    scaleFactor: scaleFactor ?? camera.zoom,
  );
  final CameraState camera;
  final double scaleFactor;
  final double _inverseScaleFactor;

  /// Screen/widget coordinates -> world coordinates.
  DrawPoint screenToWorld(DrawPoint screenPoint) => DrawPoint(
    x: (screenPoint.x - camera.position.x) * _inverseScaleFactor,
    y: (screenPoint.y - camera.position.y) * _inverseScaleFactor,
  );

  /// World coordinates -> screen/widget coordinates.
  DrawPoint worldToScreen(DrawPoint worldPoint) => DrawPoint(
    x: worldPoint.x * scaleFactor + camera.position.x,
    y: worldPoint.y * scaleFactor + camera.position.y,
  );

  /// Convenience: Flutter [Offset] -> world coordinates.
  DrawPoint fromOffset(Offset offset) =>
      screenToWorld(DrawPoint(x: offset.dx, y: offset.dy));

  /// Convenience: world coordinates -> Flutter [Offset].
  Offset toOffset(DrawPoint worldPoint) {
    final screen = worldToScreen(worldPoint);
    return Offset(screen.x, screen.y);
  }

  /// Screen distance -> world distance.
  double screenDistanceToWorld(double screenDistance) =>
      screenDistance * _inverseScaleFactor;

  /// World distance -> screen distance.
  double worldDistanceToScreen(double worldDistance) =>
      worldDistance * scaleFactor;

  CoordinateService copyWith({CameraState? camera, double? scaleFactor}) =>
      CoordinateService(
        camera: camera ?? this.camera,
        scaleFactor: scaleFactor ?? this.scaleFactor,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CoordinateService &&
          other.camera == camera &&
          other.scaleFactor == scaleFactor;

  @override
  int get hashCode => Object.hash(camera, scaleFactor);
}
