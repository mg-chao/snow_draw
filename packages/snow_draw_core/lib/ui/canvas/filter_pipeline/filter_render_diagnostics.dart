import 'package:meta/meta.dart';

/// Captures operation counts for a single filter-render frame.
///
/// These counters are deterministic and intended for tests and lightweight
/// performance monitoring.
@immutable
class FilterRenderDiagnostics {
  const FilterRenderDiagnostics({
    required this.pictureRecorders,
    required this.saveLayers,
    required this.filterPasses,
    required this.batchCount,
    required this.batchCacheHits,
    required this.batchCacheMisses,
  });

  /// Number of picture recorders created by the filter pipeline.
  final int pictureRecorders;

  /// Number of `Canvas.saveLayer` calls used to apply filters.
  final int saveLayers;

  /// Number of filter passes executed.
  final int filterPasses;

  /// Number of non-empty element batches recorded.
  final int batchCount;

  /// Number of element batches served from the picture cache.
  final int batchCacheHits;

  /// Number of cacheable element batches that missed cache reuse.
  final int batchCacheMisses;

  /// Empty diagnostics snapshot.
  static const zero = FilterRenderDiagnostics(
    pictureRecorders: 0,
    saveLayers: 0,
    filterPasses: 0,
    batchCount: 0,
    batchCacheHits: 0,
    batchCacheMisses: 0,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FilterRenderDiagnostics &&
          other.pictureRecorders == pictureRecorders &&
          other.saveLayers == saveLayers &&
          other.filterPasses == filterPasses &&
          other.batchCount == batchCount &&
          other.batchCacheHits == batchCacheHits &&
          other.batchCacheMisses == batchCacheMisses;

  @override
  int get hashCode => Object.hash(
    pictureRecorders,
    saveLayers,
    filterPasses,
    batchCount,
    batchCacheHits,
    batchCacheMisses,
  );
}

/// Mutable collector that aggregates diagnostics for one paint call.
class FilterRenderDiagnosticsCollector {
  var _pictureRecorders = 0;
  var _saveLayers = 0;
  var _filterPasses = 0;
  var _batchCount = 0;
  var _batchCacheHits = 0;
  var _batchCacheMisses = 0;
  FilterRenderDiagnostics _lastFrame = FilterRenderDiagnostics.zero;

  /// Latest completed frame snapshot.
  FilterRenderDiagnostics get lastFrame => _lastFrame;

  /// Begins a new frame collection.
  void beginFrame() {
    _pictureRecorders = 0;
    _saveLayers = 0;
    _filterPasses = 0;
    _batchCount = 0;
    _batchCacheHits = 0;
    _batchCacheMisses = 0;
  }

  /// Records one picture recorder allocation.
  void markPictureRecorder() {
    _pictureRecorders += 1;
  }

  /// Records one saveLayer call.
  void markSaveLayer() {
    _saveLayers += 1;
  }

  /// Records one filter pass.
  void markFilterPass() {
    _filterPasses += 1;
  }

  /// Records one non-empty batch.
  void markBatch() {
    _batchCount += 1;
  }

  /// Records one batch cache hit.
  void markBatchCacheHit() {
    _batchCacheHits += 1;
  }

  /// Records one cache-eligible batch cache miss.
  void markBatchCacheMiss() {
    _batchCacheMisses += 1;
  }

  /// Finalizes the current frame.
  void endFrame() {
    _lastFrame = FilterRenderDiagnostics(
      pictureRecorders: _pictureRecorders,
      saveLayers: _saveLayers,
      filterPasses: _filterPasses,
      batchCount: _batchCount,
      batchCacheHits: _batchCacheHits,
      batchCacheMisses: _batchCacheMisses,
    );
  }
}
