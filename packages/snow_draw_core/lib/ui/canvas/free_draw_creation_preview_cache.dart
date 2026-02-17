import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

import '../../draw/types/draw_point.dart';
import '../../draw/types/draw_rect.dart';
import '../../draw/types/element_style.dart';

/// Immutable signature describing the effective preview stroke style.
///
/// The preview cache is reset whenever this signature changes.
@immutable
final class FreeDrawPreviewStrokeSignature {
  const FreeDrawPreviewStrokeSignature({
    required this.strokeStyle,
    required this.strokeWidth,
    required this.strokeColor,
  });

  final StrokeStyle strokeStyle;
  final double strokeWidth;
  final Color strokeColor;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FreeDrawPreviewStrokeSignature &&
          other.strokeStyle == strokeStyle &&
          other.strokeWidth == strokeWidth &&
          other.strokeColor == strokeColor;

  @override
  int get hashCode => Object.hash(strokeStyle, strokeWidth, strokeColor);
}

/// Incremental cache for low-latency free-draw creation previews.
///
/// The cache records sealed stroke chunks into pictures and keeps a mutable
/// tail path for in-flight points. Sealed chunks are compacted so the number
/// of per-frame draw calls stays bounded, preventing frame cost from growing
/// linearly with stroke length.
class FreeDrawCreationPreviewCache {
  static const _chunkPointThreshold = 128;
  static const _compactionTrigger = 14;
  static const _maxRecentSegments = 10;
  static const _minCullPadding = 1.0;

  String? _elementId;
  FreeDrawPreviewStrokeSignature? _signature;
  var _processedPointCount = 0;
  DrawPoint? _lastProcessedPoint;

  DrawPoint? _tailLastPoint;
  var _tailPath = Path();
  var _tailPointCount = 0;
  var _tailBounds = const _BoundsAccumulator();
  double _cullPadding = _minCullPadding;

  final _sealedSegments = <_PreviewPictureSegment>[];

  @visibleForTesting
  static int get chunkPointThresholdForTest => _chunkPointThreshold;

  @visibleForTesting
  static int get compactionTriggerForTest => _compactionTrigger;

  @visibleForTesting
  static int get maxRecentSegmentsForTest => _maxRecentSegments;

  @visibleForTesting
  int get sealedSegmentCount => _sealedSegments.length;

  @visibleForTesting
  int get tailPointCount => _tailPointCount;

  @visibleForTesting
  int get processedPointCount => _processedPointCount;

  void clear() {
    _disposeSealedSegments();
    _elementId = null;
    _signature = null;
    _processedPointCount = 0;
    _lastProcessedPoint = null;
    _tailLastPoint = null;
    _tailPath = Path();
    _tailPointCount = 0;
    _tailBounds = const _BoundsAccumulator();
    _cullPadding = _minCullPadding;
  }

  void sync({
    required String elementId,
    required List<DrawPoint> points,
    required FreeDrawPreviewStrokeSignature signature,
    required Paint strokePaint,
  }) {
    if (points.isEmpty) {
      clear();
      return;
    }

    if (_needsReset(
      elementId: elementId,
      points: points,
      signature: signature,
    )) {
      _resetForSession(elementId: elementId, signature: signature);
    }

    if (_processedPointCount == 0) {
      _startTail(points.first);
    }

    for (var i = _processedPointCount; i < points.length; i++) {
      _appendPoint(points[i], strokePaint);
    }

    _processedPointCount = points.length;
    _lastProcessedPoint = points.last;
  }

  void paint({
    required Canvas canvas,
    required DrawRect viewportRect,
    required Paint strokePaint,
  }) {
    for (final segment in _sealedSegments) {
      if (_rectsIntersect(segment.bounds, viewportRect)) {
        canvas.drawPicture(segment.picture);
      }
    }

    if (_tailPointCount < 2) {
      return;
    }

    final tailBounds = _tailBounds.toRect(padding: _cullPadding);
    if (_rectsIntersect(tailBounds, viewportRect)) {
      canvas.drawPath(_tailPath, strokePaint);
    }
  }

  bool _needsReset({
    required String elementId,
    required List<DrawPoint> points,
    required FreeDrawPreviewStrokeSignature signature,
  }) {
    if (_elementId != elementId || _signature != signature) {
      return true;
    }
    if (_processedPointCount == 0) {
      return false;
    }
    if (_processedPointCount > points.length) {
      return true;
    }
    final lastProcessedPoint = _lastProcessedPoint;
    if (lastProcessedPoint == null) {
      return true;
    }
    return points[_processedPointCount - 1] != lastProcessedPoint;
  }

  void _resetForSession({
    required String elementId,
    required FreeDrawPreviewStrokeSignature signature,
  }) {
    _disposeSealedSegments();
    _elementId = elementId;
    _signature = signature;
    _processedPointCount = 0;
    _lastProcessedPoint = null;
    _tailLastPoint = null;
    _tailPath = Path();
    _tailPointCount = 0;
    _tailBounds = const _BoundsAccumulator();
    _cullPadding = math.max(_minCullPadding, signature.strokeWidth / 2);
  }

  void _startTail(DrawPoint startPoint) {
    _tailPath.moveTo(startPoint.x, startPoint.y);
    _tailBounds = _tailBounds.includePoint(startPoint);
    _tailLastPoint = startPoint;
    _tailPointCount = 1;
  }

  void _appendPoint(DrawPoint point, Paint strokePaint) {
    final lastPoint = _tailLastPoint;
    if (lastPoint == null) {
      _startTail(point);
      return;
    }

    if (lastPoint.x == point.x && lastPoint.y == point.y) {
      _tailLastPoint = point;
      return;
    }

    _tailPath.lineTo(point.x, point.y);
    _tailBounds = _tailBounds.includePoint(point);
    _tailLastPoint = point;
    _tailPointCount += 1;

    if (_tailPointCount >= _chunkPointThreshold) {
      _sealTail(strokePaint);
    }
  }

  void _sealTail(Paint strokePaint) {
    if (_tailPointCount < 2) {
      return;
    }

    final tailBounds = _tailBounds.toRect(padding: _cullPadding);
    final recorder = PictureRecorder();
    Canvas(recorder).drawPath(_tailPath, strokePaint);

    _sealedSegments.add(
      _PreviewPictureSegment(
        picture: recorder.endRecording(),
        bounds: tailBounds,
      ),
    );

    _maybeCompactSealedSegments();

    final tailLastPoint = _tailLastPoint;
    _tailPath = Path();
    _tailBounds = const _BoundsAccumulator();
    if (tailLastPoint != null) {
      _tailPath.moveTo(tailLastPoint.x, tailLastPoint.y);
      _tailBounds = _tailBounds.includePoint(tailLastPoint);
      _tailPointCount = 1;
    } else {
      _tailPointCount = 0;
    }
  }

  void _maybeCompactSealedSegments() {
    if (_sealedSegments.length <= _compactionTrigger) {
      return;
    }

    final mergeCount = _sealedSegments.length - _maxRecentSegments + 1;
    if (mergeCount < 2 || mergeCount > _sealedSegments.length) {
      return;
    }

    final segmentsToMerge = _sealedSegments
        .sublist(0, mergeCount)
        .toList(growable: false);

    final recorder = PictureRecorder();
    final mergeCanvas = Canvas(recorder);
    var mergedBounds = const _BoundsAccumulator();
    for (final segment in segmentsToMerge) {
      mergeCanvas.drawPicture(segment.picture);
      mergedBounds = mergedBounds.includeRect(segment.bounds);
    }

    final mergedSegment = _PreviewPictureSegment(
      picture: recorder.endRecording(),
      bounds: mergedBounds.toRect(),
    );

    for (final segment in segmentsToMerge) {
      segment.dispose();
    }

    _sealedSegments
      ..removeRange(0, mergeCount)
      ..insert(0, mergedSegment);
  }

  void _disposeSealedSegments() {
    for (final segment in _sealedSegments) {
      segment.dispose();
    }
    _sealedSegments.clear();
  }
}

@immutable
final class _PreviewPictureSegment {
  const _PreviewPictureSegment({required this.picture, required this.bounds});

  final Picture picture;
  final DrawRect bounds;

  void dispose() {
    picture.dispose();
  }
}

@immutable
final class _BoundsAccumulator {
  const _BoundsAccumulator({
    this.hasValue = false,
    this.minX = 0,
    this.minY = 0,
    this.maxX = 0,
    this.maxY = 0,
  });

  final bool hasValue;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;

  _BoundsAccumulator includePoint(DrawPoint point) {
    if (!hasValue) {
      return _BoundsAccumulator(
        hasValue: true,
        minX: point.x,
        minY: point.y,
        maxX: point.x,
        maxY: point.y,
      );
    }

    return _BoundsAccumulator(
      hasValue: true,
      minX: math.min(minX, point.x),
      minY: math.min(minY, point.y),
      maxX: math.max(maxX, point.x),
      maxY: math.max(maxY, point.y),
    );
  }

  _BoundsAccumulator includeRect(DrawRect rect) {
    if (!hasValue) {
      return _BoundsAccumulator(
        hasValue: true,
        minX: rect.minX,
        minY: rect.minY,
        maxX: rect.maxX,
        maxY: rect.maxY,
      );
    }

    return _BoundsAccumulator(
      hasValue: true,
      minX: math.min(minX, rect.minX),
      minY: math.min(minY, rect.minY),
      maxX: math.max(maxX, rect.maxX),
      maxY: math.max(maxY, rect.maxY),
    );
  }

  DrawRect toRect({double padding = 0}) {
    if (!hasValue) {
      return const DrawRect();
    }

    final clampedPadding = padding < 0 ? 0.0 : padding;
    return DrawRect(
      minX: minX - clampedPadding,
      minY: minY - clampedPadding,
      maxX: maxX + clampedPadding,
      maxY: maxY + clampedPadding,
    );
  }
}

bool _rectsIntersect(DrawRect a, DrawRect b) {
  if (a.maxX < b.minX || b.maxX < a.minX) {
    return false;
  }
  if (a.maxY < b.minY || b.maxY < a.minY) {
    return false;
  }
  return true;
}
