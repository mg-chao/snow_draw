import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snow_draw_engine/snow_draw_engine.dart';
import 'package:snow_draw_flutter_backend/ui/canvas/free_draw_creation_preview_cache.dart';

const _defaultStrokeColor = Color(0xFF1576FE);

void main() {
  group('FreeDrawCreationPreviewCache', () {
    test('sync keeps small previews in the tail path', () {
      final cache = FreeDrawCreationPreviewCache();
      final points = _buildPoints(16);

      _sync(cache: cache, elementId: 'stroke-1', points: points);

      expect(cache.processedPointCount, points.length);
      expect(cache.tailPointCount, points.length);
      expect(cache.sealedSegmentCount, 0);
    });

    test('sync keeps sealed segments for indexed viewport culling', () {
      final cache = FreeDrawCreationPreviewCache();
      final chunkSize = FreeDrawCreationPreviewCache.chunkPointThresholdForTest;
      final scanThreshold =
          FreeDrawCreationPreviewCache.segmentScanThresholdForTest;
      final points = _buildPoints(chunkSize * (scanThreshold + 4));

      _sync(
        cache: cache,
        elementId: 'stroke-compact',
        points: points,
        strokeWidth: 3,
      );

      expect(cache.sealedSegmentCount, greaterThan(scanThreshold));
      expect(cache.processedPointCount, points.length);
    });

    test('sync compacts old sealed segments to keep draw calls bounded', () {
      final cache = FreeDrawCreationPreviewCache();
      final chunkSize = FreeDrawCreationPreviewCache.chunkPointThresholdForTest;
      final maxSegments =
          FreeDrawCreationPreviewCache.maxSealedSegmentCountForTest;
      final compactionBatch =
          FreeDrawCreationPreviewCache.compactionBatchSizeForTest;
      final points = _buildPoints(chunkSize * (maxSegments + compactionBatch));

      _sync(
        cache: cache,
        elementId: 'stroke-compaction',
        points: points,
        strokeWidth: 4,
      );

      expect(cache.processedPointCount, points.length);
      expect(cache.sealedSegmentCount, lessThanOrEqualTo(maxSegments));
    });

    test('sync resets when point history rewinds', () {
      final cache = FreeDrawCreationPreviewCache();
      final initial = _buildPoints(64);

      _sync(cache: cache, elementId: 'stroke-reset', points: initial);

      final rewound = initial.sublist(0, 20);
      _sync(cache: cache, elementId: 'stroke-reset', points: rewound);

      expect(cache.processedPointCount, rewound.length);
      expect(cache.tailPointCount, rewound.length);
      expect(cache.sealedSegmentCount, 0);
    });

    test('sync mutates tail endpoint without resetting cache state', () {
      final cache = FreeDrawCreationPreviewCache();
      final initial = _buildPoints(48);

      _sync(cache: cache, elementId: 'stroke-tail-mutation', points: initial);

      final mutated = List<DrawPoint>.of(initial);
      mutated[mutated.length - 1] = const DrawPoint(x: 300, y: 120);
      _sync(cache: cache, elementId: 'stroke-tail-mutation', points: mutated);

      expect(cache.processedPointCount, mutated.length);
      expect(cache.tailPointCount, mutated.length);
      expect(cache.tailMutationCount, 1);
    });

    test(
      'sync keeps cache incremental when mutating a sealed boundary endpoint',
      () {
        final cache = FreeDrawCreationPreviewCache();
        final chunkSize =
            FreeDrawCreationPreviewCache.chunkPointThresholdForTest;
        final initial = _buildPoints(chunkSize);

        _sync(
          cache: cache,
          elementId: 'stroke-sealed-tail-mutation',
          points: initial,
        );

        final sealedBeforeMutation = cache.sealedSegmentCount;
        expect(cache.sealedSegmentCount, greaterThan(0));
        expect(cache.tailPointCount, 2);

        final mutated = List<DrawPoint>.of(initial);
        mutated[mutated.length - 1] = const DrawPoint(x: 2048, y: 1024);
        _sync(
          cache: cache,
          elementId: 'stroke-sealed-tail-mutation',
          points: mutated,
        );

        expect(cache.processedPointCount, mutated.length);
        expect(cache.sealedSegmentCount, sealedBeforeMutation);
        expect(cache.tailMutationCount, 1);
      },
    );

    test('sync avoids replay storms on repeated sealed boundary mutations', () {
      final cache = FreeDrawCreationPreviewCache();
      final chunkSize = FreeDrawCreationPreviewCache.chunkPointThresholdForTest;
      final points = _buildPoints(chunkSize);

      _sync(
        cache: cache,
        elementId: 'stroke-sealed-tail-mutation-loop',
        points: points,
      );

      final sealedSegmentCount = cache.sealedSegmentCount;
      final mutatedPoints = List<DrawPoint>.of(points);
      for (var index = 0; index < 24; index++) {
        mutatedPoints[mutatedPoints.length - 1] = DrawPoint(
          x: 2048 + index.toDouble(),
          y: 1024 + index.toDouble(),
        );
        _sync(
          cache: cache,
          elementId: 'stroke-sealed-tail-mutation-loop',
          points: mutatedPoints,
        );
      }

      expect(cache.processedPointCount, mutatedPoints.length);
      expect(cache.sealedSegmentCount, sealedSegmentCount);
      expect(cache.tailMutationCount, 24);
    });

    test('sync keeps cache stable when active line endpoint is excluded', () {
      final cache = FreeDrawCreationPreviewCache();
      final points = _buildPoints(32);
      final committedCount = points.length - 1;

      _sync(
        cache: cache,
        elementId: 'stroke-line',
        points: points,
        visiblePointCount: committedCount,
      );

      expect(cache.processedPointCount, committedCount);

      final movedTail = List<DrawPoint>.of(points)
        ..[points.length - 1] = const DrawPoint(x: 4096, y: 2048);
      _sync(
        cache: cache,
        elementId: 'stroke-line',
        points: movedTail,
        visiblePointCount: committedCount,
      );

      expect(cache.processedPointCount, committedCount);
      expect(cache.sealedSegmentCount, 0);
    });

    test('sync resets when stroke signature changes', () {
      final cache = FreeDrawCreationPreviewCache();
      final chunkSize = FreeDrawCreationPreviewCache.chunkPointThresholdForTest;
      final points = _buildPoints(chunkSize + 12);

      _sync(cache: cache, elementId: 'stroke-style', points: points);

      expect(cache.sealedSegmentCount, greaterThan(0));

      final shortPoints = points.sublist(0, 18);
      _sync(
        cache: cache,
        elementId: 'stroke-style',
        points: shortPoints,
        strokeWidth: 6,
        strokeColor: const Color(0xFF00A884),
      );

      expect(cache.processedPointCount, shortPoints.length);
      expect(cache.tailPointCount, shortPoints.length);
      expect(cache.sealedSegmentCount, 0);
    });

    test('clear drops cached preview state', () {
      final cache = FreeDrawCreationPreviewCache();
      _sync(cache: cache, elementId: 'stroke-clear', points: _buildPoints(24));
      cache.clear();

      expect(cache.processedPointCount, 0);
      expect(cache.tailPointCount, 0);
      expect(cache.sealedSegmentCount, 0);
    });

    test('paint executes safely with viewport culling', () {
      final cache = FreeDrawCreationPreviewCache();
      _sync(cache: cache, elementId: 'stroke-paint', points: _buildPoints(40));

      final recorder = PictureRecorder();
      final canvas = Canvas(recorder);
      expect(
        () => cache.paint(
          canvas: canvas,
          viewportRect: const DrawRect(
            minX: -10,
            minY: -10,
            maxX: 10,
            maxY: 10,
          ),
          strokePaint: _strokePaint(),
        ),
        returnsNormally,
      );
      recorder.endRecording().dispose();
    });
  });
}

void _sync({
  required FreeDrawCreationPreviewCache cache,
  required String elementId,
  required List<DrawPoint> points,
  int? visiblePointCount,
  double strokeWidth = 2,
  Color strokeColor = _defaultStrokeColor,
}) {
  cache.sync(
    elementId: elementId,
    points: points,
    visiblePointCount: visiblePointCount,
    signature: FreeDrawPreviewStrokeSignature(
      strokeStyle: StrokeStyle.solid,
      strokeWidth: strokeWidth,
      strokeColor: strokeColor,
    ),
    strokePaint: _strokePaint(strokeWidth: strokeWidth, color: strokeColor),
  );
}

Paint _strokePaint({
  double strokeWidth = 2,
  Color color = _defaultStrokeColor,
}) => Paint()
  ..style = PaintingStyle.stroke
  ..strokeWidth = strokeWidth
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round
  ..isAntiAlias = true
  ..color = color;

List<DrawPoint> _buildPoints(int count) => List<DrawPoint>.generate(
  count,
  (index) => DrawPoint(x: index * 3.0, y: (index % 5) * 2.0),
  growable: false,
);
