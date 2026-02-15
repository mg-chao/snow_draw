import 'dart:math' as math;

import 'package:meta/meta.dart';

import '../elements/types/arrow/arrow_binding.dart';
import '../elements/types/arrow/elbow/elbow_fixed_segment.dart';
import '../utils/list_equality.dart';
import 'draw_point.dart';
import 'draw_rect.dart';

/// Editable transform state for an edit session.
@immutable
sealed class EditTransform {
  const EditTransform();

  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot});

  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot});

  bool get isIdentity;
}

@immutable
final class MoveTransform extends EditTransform {
  const MoveTransform({required this.dx, required this.dy});
  final double dx;
  final double dy;

  static const zero = MoveTransform(dx: 0, dy: 0);

  @override
  bool get isIdentity => dx == 0.0 && dy == 0.0;

  @override
  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot}) =>
      point.translate(DrawPoint(x: dx, y: dy));

  @override
  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot}) =>
      rect.translate(DrawPoint(x: dx, y: dy));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MoveTransform && other.dx == dx && other.dy == dy;

  @override
  int get hashCode => Object.hash(dx, dy);
}

@immutable
final class ResizeTransform extends EditTransform {
  const ResizeTransform._({
    required this.currentPosition,
    this.newSelectionBounds,
    this.scaleX,
    this.scaleY,
    this.anchor,
  });

  const ResizeTransform.incomplete({required DrawPoint currentPosition})
    : this._(currentPosition: currentPosition);

  const ResizeTransform.complete({
    required DrawPoint currentPosition,
    required DrawRect newSelectionBounds,
    required double scaleX,
    required double scaleY,
    required DrawPoint anchor,
  }) : this._(
         currentPosition: currentPosition,
         newSelectionBounds: newSelectionBounds,
         scaleX: scaleX,
         scaleY: scaleY,
         anchor: anchor,
       );
  final DrawPoint currentPosition;
  final DrawRect? newSelectionBounds;
  final double? scaleX;
  final double? scaleY;
  final DrawPoint? anchor;

  bool get isComplete => newSelectionBounds != null;

  @override
  bool get isIdentity => !isComplete || (scaleX == 1.0 && scaleY == 1.0);

  @override
  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot}) {
    if (scaleX == null || scaleY == null) {
      return point;
    }
    final p = pivot ?? anchor;
    if (p == null) {
      return point;
    }

    final dx = (point.x - p.x) * scaleX! + p.x;
    final dy = (point.y - p.y) * scaleY! + p.y;
    return DrawPoint(x: dx, y: dy);
  }

  @override
  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot}) {
    if (scaleX == null || scaleY == null) {
      return rect;
    }
    final p = pivot ?? anchor;
    if (p == null) {
      return rect;
    }

    final corners = [
      applyToPoint(
        DrawPoint(x: rect.minX, y: rect.minY),
        pivot: p,
      ),
      applyToPoint(
        DrawPoint(x: rect.maxX, y: rect.minY),
        pivot: p,
      ),
      applyToPoint(
        DrawPoint(x: rect.minX, y: rect.maxY),
        pivot: p,
      ),
      applyToPoint(
        DrawPoint(x: rect.maxX, y: rect.maxY),
        pivot: p,
      ),
    ];
    return _boundingBox(corners);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResizeTransform &&
          other.currentPosition == currentPosition &&
          other.newSelectionBounds == newSelectionBounds &&
          other.scaleX == scaleX &&
          other.scaleY == scaleY &&
          other.anchor == anchor;

  @override
  int get hashCode =>
      Object.hash(currentPosition, newSelectionBounds, scaleX, scaleY, anchor);
}

@immutable
final class RotateTransform extends EditTransform {
  const RotateTransform({
    required this.rawAccumulatedAngle,
    required this.appliedAngle,
    this.lastRawAngle,
  });
  final double rawAccumulatedAngle;
  final double appliedAngle;
  final double? lastRawAngle;

  static const zero = RotateTransform(rawAccumulatedAngle: 0, appliedAngle: 0);

  RotateTransform copyWith({
    double? rawAccumulatedAngle,
    double? appliedAngle,
    double? lastRawAngle,
    bool clearLastRawAngle = false,
  }) => RotateTransform(
    rawAccumulatedAngle: rawAccumulatedAngle ?? this.rawAccumulatedAngle,
    appliedAngle: appliedAngle ?? this.appliedAngle,
    lastRawAngle: clearLastRawAngle
        ? null
        : (lastRawAngle ?? this.lastRawAngle),
  );

  @override
  bool get isIdentity => appliedAngle == 0.0;

  @override
  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot}) {
    final p = pivot ?? DrawPoint.zero;
    final cosA = math.cos(appliedAngle);
    final sinA = math.sin(appliedAngle);
    final dx = point.x - p.x;
    final dy = point.y - p.y;
    return DrawPoint(
      x: dx * cosA - dy * sinA + p.x,
      y: dx * sinA + dy * cosA + p.y,
    );
  }

  @override
  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot}) {
    final p = pivot ?? DrawPoint.zero;
    final newCenter = applyToPoint(rect.center, pivot: p);
    final halfWidth = rect.width / 2;
    final halfHeight = rect.height / 2;
    return DrawRect(
      minX: newCenter.x - halfWidth,
      minY: newCenter.y - halfHeight,
      maxX: newCenter.x + halfWidth,
      maxY: newCenter.y + halfHeight,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RotateTransform &&
          other.rawAccumulatedAngle == rawAccumulatedAngle &&
          other.appliedAngle == appliedAngle &&
          other.lastRawAngle == lastRawAngle;

  @override
  int get hashCode =>
      Object.hash(rawAccumulatedAngle, appliedAngle, lastRawAngle);
}

@immutable
final class ArrowPointTransform extends EditTransform {
  static const _bindingUnset = Object();
  static const _fixedSegmentsUnset = Object();

  const ArrowPointTransform({
    required this.currentPosition,
    required this.points,
    this.fixedSegments,
    this.startBinding,
    this.endBinding,
    this.activeIndex,
    this.didInsert = false,
    this.shouldDelete = false,
    this.hasChanges = false,
  });

  final DrawPoint currentPosition;
  final List<DrawPoint> points;
  final List<ElbowFixedSegment>? fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final int? activeIndex;
  final bool didInsert;
  final bool shouldDelete;
  final bool hasChanges;

  ArrowPointTransform copyWith({
    DrawPoint? currentPosition,
    List<DrawPoint>? points,
    Object? fixedSegments = _fixedSegmentsUnset,
    Object? startBinding = _bindingUnset,
    Object? endBinding = _bindingUnset,
    int? activeIndex,
    bool? didInsert,
    bool? shouldDelete,
    bool? hasChanges,
  }) => ArrowPointTransform(
    currentPosition: currentPosition ?? this.currentPosition,
    points: points ?? this.points,
    fixedSegments: fixedSegments == _fixedSegmentsUnset
        ? this.fixedSegments
        : fixedSegments as List<ElbowFixedSegment>?,
    startBinding: startBinding == _bindingUnset
        ? this.startBinding
        : startBinding as ArrowBinding?,
    endBinding: endBinding == _bindingUnset
        ? this.endBinding
        : endBinding as ArrowBinding?,
    activeIndex: activeIndex ?? this.activeIndex,
    didInsert: didInsert ?? this.didInsert,
    shouldDelete: shouldDelete ?? this.shouldDelete,
    hasChanges: hasChanges ?? this.hasChanges,
  );

  @override
  bool get isIdentity => !hasChanges;

  @override
  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot}) => point;

  @override
  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot}) => rect;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ArrowPointTransform &&
          other.currentPosition == currentPosition &&
          pointListEquals(other.points, points) &&
          fixedSegmentStructureEquals(other.fixedSegments, fixedSegments) &&
          other.startBinding == startBinding &&
          other.endBinding == endBinding &&
          other.activeIndex == activeIndex &&
          other.didInsert == didInsert &&
          other.shouldDelete == shouldDelete &&
          other.hasChanges == hasChanges;

  @override
  int get hashCode => Object.hash(
    currentPosition,
    Object.hashAll(points),
    fixedSegments == null ? null : Object.hashAll(fixedSegments!),
    startBinding,
    endBinding,
    activeIndex,
    didInsert,
    shouldDelete,
    hasChanges,
  );
}

@immutable
final class CompositeTransform extends EditTransform {
  const CompositeTransform(this.transforms);
  final List<EditTransform> transforms;

  @override
  bool get isIdentity => transforms.every((t) => t.isIdentity);

  @override
  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot}) {
    var result = point;
    for (final transform in transforms) {
      result = transform.applyToPoint(result, pivot: pivot);
    }
    return result;
  }

  @override
  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot}) {
    var result = rect;
    for (final transform in transforms) {
      result = transform.applyToRect(result, pivot: pivot);
    }
    return result;
  }

  CompositeTransform optimize() {
    final optimized = <EditTransform>[
      for (final transform in transforms)
        if (!transform.isIdentity) transform,
    ];
    return CompositeTransform(optimized);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CompositeTransform && _listEquals(other.transforms, transforms);

  @override
  int get hashCode => Object.hashAll(transforms);
}

DrawRect _boundingBox(List<DrawPoint> points) {
  var minX = points.first.x;
  var minY = points.first.y;
  var maxX = points.first.x;
  var maxY = points.first.y;

  for (final point in points.skip(1)) {
    if (point.x < minX) {
      minX = point.x;
    }
    if (point.y < minY) {
      minY = point.y;
    }
    if (point.x > maxX) {
      maxX = point.x;
    }
    if (point.y > maxY) {
      maxY = point.y;
    }
  }

  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

bool _listEquals(List<EditTransform> a, List<EditTransform> b) {
  if (identical(a, b)) {
    return true;
  }
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}
