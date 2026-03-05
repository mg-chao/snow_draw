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
  }) : assert(
         (newSelectionBounds == null &&
                 scaleX == null &&
                 scaleY == null &&
                 anchor == null) ||
             (newSelectionBounds != null &&
                 scaleX != null &&
                 scaleY != null &&
                 anchor != null),
         'ResizeTransform must be either fully complete or fully incomplete.',
       );

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
  bool get isIdentity => !isComplete || (scaleX! == 1.0 && scaleY! == 1.0);

  @override
  DrawPoint applyToPoint(DrawPoint point, {DrawPoint? pivot}) {
    if (!isComplete) {
      return point;
    }
    return _scalePoint(
      point: point,
      pivot: pivot ?? anchor!,
      scaleX: scaleX!,
      scaleY: scaleY!,
    );
  }

  @override
  DrawRect applyToRect(DrawRect rect, {DrawPoint? pivot}) {
    if (!isComplete) {
      return rect;
    }
    final resolvedPivot = pivot ?? anchor!;
    final sx = scaleX!;
    final sy = scaleY!;
    final topLeft = _scalePoint(
      point: DrawPoint(x: rect.minX, y: rect.minY),
      pivot: resolvedPivot,
      scaleX: sx,
      scaleY: sy,
    );
    final topRight = _scalePoint(
      point: DrawPoint(x: rect.maxX, y: rect.minY),
      pivot: resolvedPivot,
      scaleX: sx,
      scaleY: sy,
    );
    final bottomLeft = _scalePoint(
      point: DrawPoint(x: rect.minX, y: rect.maxY),
      pivot: resolvedPivot,
      scaleX: sx,
      scaleY: sy,
    );
    final bottomRight = _scalePoint(
      point: DrawPoint(x: rect.maxX, y: rect.maxY),
      pivot: resolvedPivot,
      scaleX: sx,
      scaleY: sy,
    );
    return _boundingRect(topLeft, topRight, bottomLeft, bottomRight);
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
  static const _orderedElementIdsUnset = Object();

  const ArrowPointTransform({
    required this.currentPosition,
    required this.points,
    this.fixedSegments,
    this.startBinding,
    this.endBinding,
    this.orderedElementIds,
    this.activeIndex,
    this.didInsert = false,
    this.shouldDelete = false,
    this.hasChanges = false,
    this.allowBindingOnFinalize = true,
  });

  final DrawPoint currentPosition;
  final List<DrawPoint> points;
  final List<ElbowFixedSegment>? fixedSegments;
  final ArrowBinding? startBinding;
  final ArrowBinding? endBinding;
  final List<String>? orderedElementIds;
  final int? activeIndex;
  final bool didInsert;
  final bool shouldDelete;
  final bool hasChanges;
  final bool allowBindingOnFinalize;

  ArrowPointTransform copyWith({
    DrawPoint? currentPosition,
    List<DrawPoint>? points,
    Object? fixedSegments = _fixedSegmentsUnset,
    Object? startBinding = _bindingUnset,
    Object? endBinding = _bindingUnset,
    Object? orderedElementIds = _orderedElementIdsUnset,
    int? activeIndex,
    bool? didInsert,
    bool? shouldDelete,
    bool? hasChanges,
    bool? allowBindingOnFinalize,
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
    orderedElementIds: orderedElementIds == _orderedElementIdsUnset
        ? this.orderedElementIds
        : orderedElementIds as List<String>?,
    activeIndex: activeIndex ?? this.activeIndex,
    didInsert: didInsert ?? this.didInsert,
    shouldDelete: shouldDelete ?? this.shouldDelete,
    hasChanges: hasChanges ?? this.hasChanges,
    allowBindingOnFinalize:
        allowBindingOnFinalize ?? this.allowBindingOnFinalize,
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
          nullableListEquals(other.orderedElementIds, orderedElementIds) &&
          other.activeIndex == activeIndex &&
          other.didInsert == didInsert &&
          other.shouldDelete == shouldDelete &&
          other.hasChanges == hasChanges &&
          other.allowBindingOnFinalize == allowBindingOnFinalize;

  @override
  int get hashCode => Object.hash(
    currentPosition,
    Object.hashAll(points),
    fixedSegments == null ? null : Object.hashAll(fixedSegments!),
    startBinding,
    endBinding,
    orderedElementIds == null ? null : Object.hashAll(orderedElementIds!),
    activeIndex,
    didInsert,
    shouldDelete,
    hasChanges,
    allowBindingOnFinalize,
  );
}

DrawPoint _scalePoint({
  required DrawPoint point,
  required DrawPoint pivot,
  required double scaleX,
  required double scaleY,
}) => DrawPoint(
  x: (point.x - pivot.x) * scaleX + pivot.x,
  y: (point.y - pivot.y) * scaleY + pivot.y,
);

DrawRect _boundingRect(DrawPoint a, DrawPoint b, DrawPoint c, DrawPoint d) {
  final minX = math.min(math.min(a.x, b.x), math.min(c.x, d.x));
  final minY = math.min(math.min(a.y, b.y), math.min(c.y, d.y));
  final maxX = math.max(math.max(a.x, b.x), math.max(c.x, d.x));
  final maxY = math.max(math.max(a.y, b.y), math.max(c.y, d.y));
  return DrawRect(minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}
