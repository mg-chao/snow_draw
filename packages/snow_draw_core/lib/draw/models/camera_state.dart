import 'package:meta/meta.dart';

import '../types/draw_point.dart';

@immutable
class CameraState {
  const CameraState({DrawPoint? position, this.zoom = 1.0})
    : position = position ?? DrawPoint.zero;
  final DrawPoint position;
  final double zoom;

  static const initial = CameraState();
  static const minZoom = 0.1;
  static const maxZoom = 30.0;

  static double clampZoom(double zoom) => zoom.clamp(minZoom, maxZoom);

  CameraState copyWith({DrawPoint? position, double? zoom}) =>
      CameraState(position: position ?? this.position, zoom: zoom ?? this.zoom);

  CameraState translated(double dx, double dy) => copyWith(
    position: DrawPoint(x: position.x + dx, y: position.y + dy),
  );

  CameraState movedTo(DrawPoint newPosition) => copyWith(position: newPosition);

  CameraState reset() => CameraState.initial;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraState && other.position == position && other.zoom == zoom;

  @override
  int get hashCode => Object.hash(position, zoom);

  @override
  String toString() => 'CameraState(position: $position, zoom: $zoom)';
}
