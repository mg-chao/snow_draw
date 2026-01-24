import 'dart:math';

import 'package:meta/meta.dart';

import 'draw_point.dart';

@immutable
class DrawRect {
  const DrawRect({this.minX = 0, this.minY = 0, this.maxX = 0, this.maxY = 0});

  factory DrawRect.fromPoints(DrawPoint minPoint, DrawPoint maxPoint) =>
      DrawRect(
        minX: minPoint.x,
        minY: minPoint.y,
        maxX: maxPoint.x,
        maxY: maxPoint.y,
      );

  factory DrawRect.fromPoint(DrawPoint point) =>
      DrawRect(minX: point.x, minY: point.y, maxX: point.x, maxY: point.y);
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  double get width => maxX - minX;
  double get height => maxY - minY;
  double get centerX => (minX + maxX) / 2;
  double get centerY => (minY + maxY) / 2;
  DrawPoint get center => DrawPoint(x: centerX, y: centerY);

  DrawRect copyWith({double? minX, double? minY, double? maxX, double? maxY}) =>
      DrawRect(
        minX: minX ?? this.minX,
        minY: minY ?? this.minY,
        maxX: maxX ?? this.maxX,
        maxY: maxY ?? this.maxY,
      );

  DrawRect translate(DrawPoint position) => DrawRect(
    minX: minX + position.x,
    minY: minY + position.y,
    maxX: maxX + position.x,
    maxY: maxY + position.y,
  );

  /// Returns whether this rectangle contains [point].
  /// Note: this does not account for rotation.
  bool containsPoint(DrawPoint point) =>
      point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY;

  Rectangle<double> toRectangle() => Rectangle(minX, minY, width, height);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DrawRect &&
          other.minX == minX &&
          other.minY == minY &&
          other.maxX == maxX &&
          other.maxY == maxY);

  @override
  int get hashCode => Object.hash(minX, minY, maxX, maxY);

  @override
  String toString() =>
      'DrawRect(minX: $minX, minY: $minY, maxX: $maxX, maxY: $maxY)';
}
