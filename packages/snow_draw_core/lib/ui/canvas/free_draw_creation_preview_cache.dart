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
/// tail path for in-flight points. Sealed chunks stay spatially indexed so
/// paint can resolve only candidates intersecting the viewport.
class FreeDrawCreationPreviewCache {
  static const _chunkPointThreshold = 128;
  static const _segmentScanThreshold = 32;
  static const _indexTileSize = 512.0;
  static const _maxTileToSegmentRatio = 8;
  static const _maxSealedSegmentCount = 48;
  static const _compactionBatchSize = 12;
  static const _minCullPadding = 1.0;

  String? _elementId;
  FreeDrawPreviewStrokeSignature? _signature;
  var _processedPointCount = 0;
  DrawPoint? _lastProcessedPoint;

  DrawPoint? _tailLastPoint;
  var _tailPath = Path();
  var _tailPointCount = 0;
  final _tailPoints = <DrawPoint>[];
  final _tailBounds = _MutableBoundsAccumulator();
  double _cullPadding = _minCullPadding;

  final _sealedSegments = <_PreviewPictureSegment>[];
  final _segmentIndex = <_SegmentTileKey, List<int>>{};
  final _candidateSegmentIndices = <int>[];
  final _candidateSegmentIndexSet = <int>{};
  var _tailMutationCount = 0;

  @visibleForTesting
  static int get chunkPointThresholdForTest => _chunkPointThreshold;

  @visibleForTesting
  static int get segmentScanThresholdForTest => _segmentScanThreshold;

  @visibleForTesting
  static double get indexTileSizeForTest => _indexTileSize;

  @visibleForTesting
  static int get maxSealedSegmentCountForTest => _maxSealedSegmentCount;

  @visibleForTesting
  static int get compactionBatchSizeForTest => _compactionBatchSize;

  @visibleForTesting
  int get sealedSegmentCount => _sealedSegments.length;

  @visibleForTesting
  int get tailPointCount => _tailPointCount;

  @visibleForTesting
  int get processedPointCount => _processedPointCount;

  @visibleForTesting
  int get tailMutationCount => _tailMutationCount;

  void clear() {
    _disposeSealedSegments();
    _elementId = null;
    _signature = null;
    _processedPointCount = 0;
    _lastProcessedPoint = null;
    _tailLastPoint = null;
    _tailPath = Path();
    _tailPointCount = 0;
    _tailPoints.clear();
    _tailBounds.reset();
    _cullPadding = _minCullPadding;
    _candidateSegmentIndices.clear();
    _candidateSegmentIndexSet.clear();
    _tailMutationCount = 0;
  }

  void sync({
    required String elementId,
    required List<DrawPoint> points,
    required FreeDrawPreviewStrokeSignature signature,
    required Paint strokePaint,
    int? visiblePointCount,
  }) {
    final effectivePointCount = _resolveVisiblePointCount(
      points: points,
      visiblePointCount: visiblePointCount,
    );
    if (effectivePointCount <= 0) {
      clear();
      return;
    }

    if (_needsReset(
      elementId: elementId,
      pointCount: effectivePointCount,
      signature: signature,
    )) {
      _resetForSession(elementId: elementId, signature: signature);
    }

    final lastProcessedPoint = _lastProcessedPoint;
    if (_processedPointCount > 0 && lastProcessedPoint != null) {
      final processedTailPoint = points[_processedPointCount - 1];
      if (processedTailPoint != lastProcessedPoint &&
          !_tryUpdateTailLastPoint(processedTailPoint)) {
        _resetForSession(elementId: elementId, signature: signature);
      }
    }

    if (_processedPointCount == 0) {
      _startTail(points.first);
    }

    for (var i = _processedPointCount; i < effectivePointCount; i++) {
      _appendPoint(points[i], strokePaint);
    }

    _processedPointCount = effectivePointCount;
    _lastProcessedPoint = points[effectivePointCount - 1];
  }

  void paint({
    required Canvas canvas,
    required DrawRect viewportRect,
    required Paint strokePaint,
  }) {
    if (_sealedSegments.length <= _segmentScanThreshold) {
      for (final segment in _sealedSegments) {
        if (_rectsIntersect(segment.bounds, viewportRect)) {
          canvas.drawPicture(segment.picture);
        }
      }
    } else {
      _collectCandidateSegmentIndices(viewportRect);
      for (final segmentIndex in _candidateSegmentIndices) {
        final segment = _sealedSegments[segmentIndex];
        if (_rectsIntersect(segment.bounds, viewportRect)) {
          canvas.drawPicture(segment.picture);
        }
      }
      _candidateSegmentIndices.clear();
      _candidateSegmentIndexSet.clear();
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
    required int pointCount,
    required FreeDrawPreviewStrokeSignature signature,
  }) {
    if (_elementId != elementId || _signature != signature) {
      return true;
    }
    if (_processedPointCount == 0) {
      return false;
    }
    if (_processedPointCount > pointCount) {
      return true;
    }
    return _lastProcessedPoint == null;
  }

  int _resolveVisiblePointCount({
    required List<DrawPoint> points,
    required int? visiblePointCount,
  }) {
    if (visiblePointCount == null) {
      return points.length;
    }
    if (visiblePointCount <= 0) {
      return 0;
    }
    if (visiblePointCount > points.length) {
      return points.length;
    }
    return visiblePointCount;
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
    _tailPoints.clear();
    _tailBounds.reset();
    _cullPadding = math.max(_minCullPadding, signature.strokeWidth / 2);
    _tailMutationCount = 0;
  }

  void _startTail(DrawPoint startPoint) {
    _tailPoints
      ..clear()
      ..add(startPoint);
    _rebuildTailPath();
  }

  void _appendPoint(DrawPoint point, Paint strokePaint) {
    final lastPoint = _tailLastPoint;
    if (lastPoint == null) {
      _startTail(point);
      return;
    }

    if (lastPoint.x == point.x && lastPoint.y == point.y) {
      _tailLastPoint = point;
      _tailPoints[_tailPoints.length - 1] = point;
      return;
    }

    _tailPath.lineTo(point.x, point.y);
    _tailBounds.includePoint(point);
    _tailLastPoint = point;
    _tailPoints.add(point);
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

    final segmentIndex = _sealedSegments.length;
    _sealedSegments.add(
      _PreviewPictureSegment(
        picture: recorder.endRecording(),
        bounds: tailBounds,
      ),
    );
    _indexSegmentBounds(segmentIndex: segmentIndex, bounds: tailBounds);
    _compactSealedSegmentsIfNeeded();

    final tailLastPoint = _tailLastPoint;
    _tailPath = Path();
    _tailBounds.reset();
    _tailPoints.clear();
    if (tailLastPoint != null) {
      _startTail(tailLastPoint);
    } else {
      _tailPointCount = 0;
      _tailLastPoint = null;
    }
  }

  bool _tryUpdateTailLastPoint(DrawPoint point) {
    if (_tailPoints.isEmpty) {
      return false;
    }
    if (_tailPoints.length == 1 && _sealedSegments.isNotEmpty) {
      return false;
    }
    final lastProcessedPoint = _lastProcessedPoint;
    if (lastProcessedPoint == null || _tailPoints.last != lastProcessedPoint) {
      return false;
    }
    _tailPoints[_tailPoints.length - 1] = point;
    _rebuildTailPath();
    _lastProcessedPoint = point;
    _tailMutationCount += 1;
    return true;
  }

  void _rebuildTailPath() {
    _tailPath = Path();
    _tailBounds.reset();
    _tailPointCount = _tailPoints.length;
    if (_tailPoints.isEmpty) {
      _tailLastPoint = null;
      return;
    }

    final first = _tailPoints.first;
    _tailPath.moveTo(first.x, first.y);
    _tailBounds.includePoint(first);
    var previous = first;
    for (var index = 1; index < _tailPoints.length; index++) {
      final point = _tailPoints[index];
      if (point.x == previous.x && point.y == previous.y) {
        previous = point;
        continue;
      }
      _tailPath.lineTo(point.x, point.y);
      _tailBounds.includePoint(point);
      previous = point;
    }
    _tailLastPoint = _tailPoints.last;
  }

  void _compactSealedSegmentsIfNeeded() {
    while (_sealedSegments.length > _maxSealedSegmentCount) {
      if (!_compactOldestSegments()) {
        break;
      }
    }
  }

  bool _compactOldestSegments() {
    if (_sealedSegments.length < 2) {
      return false;
    }

    final batchSize = math.min(_compactionBatchSize, _sealedSegments.length);
    if (batchSize < 2) {
      return false;
    }

    final merged = _mergeSegments(_sealedSegments.take(batchSize));
    if (merged == null) {
      return false;
    }

    for (var index = 0; index < batchSize; index++) {
      _sealedSegments[index].dispose();
    }
    _sealedSegments
      ..removeRange(0, batchSize)
      ..insert(0, merged);
    _rebuildSegmentIndex();
    return true;
  }

  _PreviewPictureSegment? _mergeSegments(
    Iterable<_PreviewPictureSegment> source,
  ) {
    final segments = source.toList(growable: false);
    if (segments.length < 2) {
      return null;
    }

    var bounds = segments.first.bounds;
    for (var index = 1; index < segments.length; index++) {
      bounds = _unionRect(bounds, segments[index].bounds);
    }

    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    for (final segment in segments) {
      canvas.drawPicture(segment.picture);
    }

    return _PreviewPictureSegment(
      picture: recorder.endRecording(),
      bounds: bounds,
    );
  }

  void _rebuildSegmentIndex() {
    _segmentIndex.clear();
    for (var index = 0; index < _sealedSegments.length; index++) {
      _indexSegmentBounds(
        segmentIndex: index,
        bounds: _sealedSegments[index].bounds,
      );
    }
  }

  void _collectCandidateSegmentIndices(DrawRect viewportRect) {
    _candidateSegmentIndices.clear();
    _candidateSegmentIndexSet.clear();

    if (_sealedSegments.isEmpty) {
      return;
    }

    final tileMinX = _resolveTileIndex(viewportRect.minX);
    final tileMaxX = _resolveTileIndex(viewportRect.maxX);
    final tileMinY = _resolveTileIndex(viewportRect.minY);
    final tileMaxY = _resolveTileIndex(viewportRect.maxY);
    final tileSpanX = tileMaxX - tileMinX + 1;
    final tileSpanY = tileMaxY - tileMinY + 1;
    final tileCountEstimate = tileSpanX * tileSpanY;
    if (tileCountEstimate > _sealedSegments.length * _maxTileToSegmentRatio) {
      for (
        var segmentIndex = 0;
        segmentIndex < _sealedSegments.length;
        segmentIndex++
      ) {
        _candidateSegmentIndices.add(segmentIndex);
      }
      return;
    }

    for (var tileY = tileMinY; tileY <= tileMaxY; tileY++) {
      for (var tileX = tileMinX; tileX <= tileMaxX; tileX++) {
        final indices = _segmentIndex[_SegmentTileKey(x: tileX, y: tileY)];
        if (indices == null) {
          continue;
        }
        for (final segmentIndex in indices) {
          if (_candidateSegmentIndexSet.add(segmentIndex)) {
            _candidateSegmentIndices.add(segmentIndex);
          }
        }
      }
    }
    if (_candidateSegmentIndices.length > 1) {
      _candidateSegmentIndices.sort();
    }
  }

  void _indexSegmentBounds({
    required int segmentIndex,
    required DrawRect bounds,
  }) {
    final tileMinX = _resolveTileIndex(bounds.minX);
    final tileMaxX = _resolveTileIndex(bounds.maxX);
    final tileMinY = _resolveTileIndex(bounds.minY);
    final tileMaxY = _resolveTileIndex(bounds.maxY);

    for (var tileY = tileMinY; tileY <= tileMaxY; tileY++) {
      for (var tileX = tileMinX; tileX <= tileMaxX; tileX++) {
        final key = _SegmentTileKey(x: tileX, y: tileY);
        _segmentIndex.putIfAbsent(key, () => <int>[]).add(segmentIndex);
      }
    }
  }

  int _resolveTileIndex(double coordinate) {
    if (coordinate.isNaN || coordinate.isInfinite) {
      return 0;
    }
    return (coordinate / _indexTileSize).floor();
  }

  void _disposeSealedSegments() {
    for (final segment in _sealedSegments) {
      segment.dispose();
    }
    _sealedSegments.clear();
    _segmentIndex.clear();
  }
}

DrawRect _unionRect(DrawRect a, DrawRect b) => DrawRect(
  minX: math.min(a.minX, b.minX),
  minY: math.min(a.minY, b.minY),
  maxX: math.max(a.maxX, b.maxX),
  maxY: math.max(a.maxY, b.maxY),
);

@immutable
final class _PreviewPictureSegment {
  const _PreviewPictureSegment({required this.picture, required this.bounds});

  final Picture picture;
  final DrawRect bounds;

  void dispose() {
    picture.dispose();
  }
}

final class _MutableBoundsAccumulator {
  var hasValue = false;
  var minX = 0.0;
  var minY = 0.0;
  var maxX = 0.0;
  var maxY = 0.0;

  void reset() {
    hasValue = false;
    minX = 0.0;
    minY = 0.0;
    maxX = 0.0;
    maxY = 0.0;
  }

  void includePoint(DrawPoint point) {
    if (!hasValue) {
      hasValue = true;
      minX = point.x;
      minY = point.y;
      maxX = point.x;
      maxY = point.y;
      return;
    }

    minX = math.min(minX, point.x);
    minY = math.min(minY, point.y);
    maxX = math.max(maxX, point.x);
    maxY = math.max(maxY, point.y);
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

@immutable
final class _SegmentTileKey {
  const _SegmentTileKey({required this.x, required this.y});

  final int x;
  final int y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SegmentTileKey && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);
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
