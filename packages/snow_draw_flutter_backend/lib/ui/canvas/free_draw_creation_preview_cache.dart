import 'dart:math' as math;
import 'dart:ui';

import 'package:meta/meta.dart';

import 'package:snow_draw_core/snow_draw_core.dart';

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
/// The cache records sealed stroke chunks and keeps a mutable tail path for
/// in-flight points. Older chunks are compacted into raster snapshots when
/// feasible so paint cost remains stable as the stroke grows.
///
/// Sealed chunks stay spatially indexed so paint can resolve only candidates
/// intersecting the viewport.
///
/// To avoid full-cache rebuilds during smoothing tail replacements, each seal
/// operation keeps a small point overlap in the mutable tail. The overlap
/// ensures the latest endpoint remains editable even after a chunk is sealed.
class FreeDrawCreationPreviewCache {
  static const _chunkPointThreshold = 128;
  static const _retainedTailPointCount = 2;
  static const _segmentScanThreshold = 32;
  static const _indexTileSize = 512.0;
  static const _maxTileToSegmentRatio = 8;
  static const _maxSealedSegmentCount = 48;
  static const _compactionBatchSize = 8;
  static const _minCullPadding = 1.0;
  static const _maxRasterExtent = 1536;
  static const int _maxRasterPixels = 1024 * 1024;

  static final _segmentImagePaint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.low;

  String? _elementId;
  FreeDrawPreviewStrokeSignature? _signature;
  var _processedPointCount = 0;
  DrawPoint? _lastProcessedPoint;

  var _tailPath = Path();
  final _tailPoints = <DrawPoint>[];
  final _tailBounds = _MutableBoundsAccumulator();
  double _cullPadding = _minCullPadding;

  final _sealedSegments = <_PreviewSegment>[];
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
  int get tailPointCount => _tailPoints.length;

  @visibleForTesting
  int get processedPointCount => _processedPointCount;

  @visibleForTesting
  int get tailMutationCount => _tailMutationCount;

  void clear() {
    _disposeSealedSegments();
    _elementId = null;
    _signature = null;
    _resetMutableState(cullPadding: _minCullPadding);
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

    final startIndex = _processedPointCount == 0 ? 1 : _processedPointCount;
    for (var i = startIndex; i < effectivePointCount; i++) {
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
          segment.paint(canvas, imagePaint: _segmentImagePaint);
        }
      }
    } else {
      _collectCandidateSegmentIndices(viewportRect);
      for (final segmentIndex in _candidateSegmentIndices) {
        final segment = _sealedSegments[segmentIndex];
        if (_rectsIntersect(segment.bounds, viewportRect)) {
          segment.paint(canvas, imagePaint: _segmentImagePaint);
        }
      }
      _candidateSegmentIndices.clear();
      _candidateSegmentIndexSet.clear();
    }

    if (_tailPoints.length < 2) {
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
  }) =>
      _elementId != elementId ||
      _signature != signature ||
      _processedPointCount > pointCount;

  int _resolveVisiblePointCount({
    required List<DrawPoint> points,
    required int? visiblePointCount,
  }) {
    final requestedCount = visiblePointCount ?? points.length;
    return requestedCount.clamp(0, points.length);
  }

  void _resetForSession({
    required String elementId,
    required FreeDrawPreviewStrokeSignature signature,
  }) {
    _disposeSealedSegments();
    _elementId = elementId;
    _signature = signature;
    _resetMutableState(
      cullPadding: math.max(_minCullPadding, signature.strokeWidth / 2),
    );
  }

  void _resetMutableState({required double cullPadding}) {
    _processedPointCount = 0;
    _lastProcessedPoint = null;
    _tailPath = Path();
    _tailPoints.clear();
    _tailBounds.reset();
    _cullPadding = cullPadding;
    _candidateSegmentIndices.clear();
    _candidateSegmentIndexSet.clear();
    _tailMutationCount = 0;
  }

  void _startTail(DrawPoint startPoint) {
    _tailPoints
      ..clear()
      ..add(startPoint);
    _rebuildTailPath();
  }

  void _appendPoint(DrawPoint point, Paint strokePaint) {
    final lastPoint = _tailPoints.last;

    if (lastPoint.x == point.x && lastPoint.y == point.y) {
      _tailPoints[_tailPoints.length - 1] = point;
      return;
    }

    _tailPath.lineTo(point.x, point.y);
    _tailBounds.includePoint(point);
    _tailPoints.add(point);

    if (_tailPoints.length >= _chunkPointThreshold) {
      _sealTail(strokePaint);
    }
  }

  void _sealTail(Paint strokePaint) {
    if (_tailPoints.length < _chunkPointThreshold) {
      return;
    }

    final retainedCount = math.min(_tailPoints.length, _retainedTailPointCount);
    final sealedPointCount = _tailPoints.length - retainedCount + 1;

    final sealedPath = Path();
    final sealedBounds = _MutableBoundsAccumulator();
    final first = _tailPoints.first;
    sealedPath.moveTo(first.x, first.y);
    sealedBounds.includePoint(first);

    var previous = first;
    for (var index = 1; index < sealedPointCount; index++) {
      final point = _tailPoints[index];
      if (point.x == previous.x && point.y == previous.y) {
        previous = point;
        continue;
      }
      sealedPath.lineTo(point.x, point.y);
      sealedBounds.includePoint(point);
      previous = point;
    }

    final tailBounds = sealedBounds.toRect(padding: _cullPadding);
    final recorder = PictureRecorder();
    Canvas(recorder, Rect.fromLTWH(0, 0, tailBounds.width, tailBounds.height))
      ..translate(-tailBounds.minX, -tailBounds.minY)
      ..drawPath(sealedPath, strokePaint);

    final segmentIndex = _sealedSegments.length;
    final picture = recorder.endRecording();
    _sealedSegments.add(
      _PreviewSegment.vector(bounds: tailBounds, picture: picture),
    );
    _indexSegmentBounds(segmentIndex: segmentIndex, bounds: tailBounds);
    _compactSealedSegmentsIfNeeded();

    final retainedStartIndex = sealedPointCount - 1;
    final retainedPoints = _tailPoints.sublist(
      retainedStartIndex,
      _tailPoints.length,
    );
    _tailPoints
      ..clear()
      ..addAll(retainedPoints);
    _rebuildTailPath();
  }

  bool _tryUpdateTailLastPoint(DrawPoint point) {
    final lastProcessedPoint = _lastProcessedPoint;
    if (lastProcessedPoint == null ||
        _tailPoints.isEmpty ||
        _tailPoints.last != lastProcessedPoint) {
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
    if (_tailPoints.isEmpty) {
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
  }

  void _compactSealedSegmentsIfNeeded() {
    while (_sealedSegments.length > _maxSealedSegmentCount) {
      _compactOldestSegments();
    }
  }

  void _compactOldestSegments() {
    final batchSize = math.min(_compactionBatchSize, _sealedSegments.length);
    final merged = _mergeSegments(
      _sealedSegments.take(batchSize).toList(growable: false),
    );

    for (var index = 0; index < batchSize; index++) {
      _sealedSegments[index].dispose();
    }
    _sealedSegments
      ..removeRange(0, batchSize)
      ..insert(0, merged);
    _rebuildSegmentIndex();
  }

  _PreviewSegment _mergeSegments(List<_PreviewSegment> segments) {
    var bounds = segments.first.bounds;
    for (var index = 1; index < segments.length; index++) {
      bounds = _unionRect(bounds, segments[index].bounds);
    }

    final recorder = PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, bounds.width, bounds.height),
    );
    for (final segment in segments) {
      segment.paintTranslated(
        canvas,
        dx: segment.bounds.minX - bounds.minX,
        dy: segment.bounds.minY - bounds.minY,
        imagePaint: _segmentImagePaint,
      );
    }

    final picture = recorder.endRecording();
    final rasterized = _tryRasterizeSegmentPicture(
      picture: picture,
      width: bounds.width,
      height: bounds.height,
    );
    if (rasterized != null) {
      picture.dispose();
      return _PreviewSegment.raster(bounds: bounds, image: rasterized);
    }
    return _PreviewSegment.vector(bounds: bounds, picture: picture);
  }

  Image? _tryRasterizeSegmentPicture({
    required Picture picture,
    required double width,
    required double height,
  }) {
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return null;
    }

    final pixelWidth = width.ceil();
    final pixelHeight = height.ceil();
    if (pixelWidth > _maxRasterExtent || pixelHeight > _maxRasterExtent) {
      return null;
    }
    if (pixelWidth * pixelHeight > _maxRasterPixels) {
      return null;
    }

    try {
      return picture.toImageSync(pixelWidth, pixelHeight);
    } on Object {
      return null;
    }
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
final class _PreviewSegment {
  const _PreviewSegment._({required this.bounds, this.picture, this.image});

  const _PreviewSegment.vector({
    required DrawRect bounds,
    required Picture picture,
  }) : this._(bounds: bounds, picture: picture);

  const _PreviewSegment.raster({required DrawRect bounds, required Image image})
    : this._(bounds: bounds, image: image);

  final DrawRect bounds;
  final Picture? picture;
  final Image? image;

  void paint(Canvas canvas, {required Paint imagePaint}) {
    paintTranslated(
      canvas,
      dx: bounds.minX,
      dy: bounds.minY,
      imagePaint: imagePaint,
    );
  }

  void paintTranslated(
    Canvas canvas, {
    required double dx,
    required double dy,
    required Paint imagePaint,
  }) {
    final raster = image;
    if (raster != null) {
      final destination = Rect.fromLTWH(dx, dy, bounds.width, bounds.height);
      canvas.drawImageRect(
        raster,
        Rect.fromLTWH(0, 0, raster.width.toDouble(), raster.height.toDouble()),
        destination,
        imagePaint,
      );
      return;
    }

    final vector = picture!;
    canvas
      ..save()
      ..translate(dx, dy)
      ..drawPicture(vector)
      ..restore();
  }

  void dispose() {
    picture?.dispose();
    image?.dispose();
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

    return DrawRect(
      minX: minX - padding,
      minY: minY - padding,
      maxX: maxX + padding,
      maxY: maxY + padding,
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
