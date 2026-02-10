import 'dart:math';

import 'package:meta/meta.dart';

import 'draw_rect.dart';

@immutable
class DrawPoint {
  const DrawPoint({
    required this.x,
    required this.y,
    this.pressure = 0.0,
    this.timestamp = 0,
  });

  factory DrawPoint.fromPoint(Point<double> point) =>
      DrawPoint(x: point.x, y: point.y);
  final double x;
  final double y;

  /// Stylus / pointer pressure in the range 0..1.
  ///
  /// A value of 0 means pressure is unknown or unavailable.
  final double pressure;

  /// Monotonic timestamp in microseconds, used for velocity calculation.
  ///
  /// A value of 0 means the timestamp is unavailable.
  final int timestamp;

  static const zero = DrawPoint(x: 0, y: 0);

  DrawPoint copyWith({
    double? x,
    double? y,
    double? pressure,
    int? timestamp,
  }) => DrawPoint(
    x: x ?? this.x,
    y: y ?? this.y,
    pressure: pressure ?? this.pressure,
    timestamp: timestamp ?? this.timestamp,
  );

  DrawPoint translate(DrawPoint position) =>
      DrawPoint(x: x + position.x, y: y + position.y);

  DrawPoint operator +(DrawPoint other) =>
      DrawPoint(x: x + other.x, y: y + other.y);

  DrawPoint operator -(DrawPoint other) =>
      DrawPoint(x: x - other.x, y: y - other.y);

  DrawPoint operator -() => DrawPoint(x: -x, y: -y);

  /// Whether this point carries valid pressure data.
  bool get hasPressure => pressure > 0;

  Point<double> toPoint() => Point(x, y);

  DrawRect toRect(DrawPoint other) {
    var minX = x;
    var maxX = other.x;
    var minY = y;
    var maxY = other.y;

    if (minX > maxX) {
      final temp = minX;
      minX = maxX;
      maxX = temp;
    }

    if (minY > maxY) {
      final temp = minY;
      minY = maxY;
      maxY = temp;
    }

    return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
  }

  /// Computes the Euclidean distance to [other].
  double distance(DrawPoint other) => sqrt(distanceSquared(other));

  /// Computes the squared distance to [other], useful for comparisons without
  /// calling `sqrt`.
  double distanceSquared(DrawPoint other) {
    final dx = x - other.x;
    final dy = y - other.y;
    return dx * dx + dy * dy;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DrawPoint &&
          other.x == x &&
          other.y == y &&
          other.pressure == pressure);

  @override
  int get hashCode => Object.hash(x, y, pressure);

  @override
  String toString() =>
      'DrawPoint(x: $x, y: $y${hasPressure ? ', p: $pressure' : ''})';
}
